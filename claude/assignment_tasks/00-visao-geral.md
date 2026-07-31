# Visão Geral — Atribuição por Demanda + Fim do Online-Only + Fallback Anti-Silêncio

## Objetivo

Três mudanças no mecanismo de atribuição automática de conversas (inbox):

1. **Modo de atribuição por inbox**: além do rodízio (round robin) atual, poder escolher
   "por demanda" (atribui sempre ao agente com menos conversas abertas naquela inbox).
2. **Fim da regra "só agente online"**: qualquer membro da inbox pode receber conversa
   automaticamente, esteja online ou não — configurável por inbox, default = sem restrição.
3. **Fallback anti-silêncio**: nunca pode haver conversa sem atribuição por causa de limite de
   capacidade ou de rate-limit ("fair distribution") — se todos os candidatos forem filtrados
   por esses motivos operacionais, atribui mesmo assim ao menos ocupado e loga bem alto. Só
   fica sem atribuição se a inbox não tiver **nenhum** membro ou se o filtro de **time** zerar
   tudo (fronteiras de negócio intencionais, não recebem fallback).

Este documento é o índice; cada arquivo `NN-*.md` nesta pasta é uma task de implementação
independente. Nenhuma task aqui foi implementada ainda — são especificações prontas para pegar
e codar.

## Achado que muda o escopo do trabalho

O algoritmo "por demanda" (least-busy) **já existe implementado e testado**:
`enterprise/app/services/enterprise/auto_assignment/balanced_selector.rb`. Hoje só é acessível
criando/vinculando um objeto `AssignmentPolicy` numa tela separada de Settings
(`routes/dashboard/settings/assignmentPolicy/`), e só funciona se a feature de conta
`advanced_assignment` estiver habilitada — hoje `enabled: false, premium: true` em
`config/features.yml`, ou seja, desligada por padrão e marcada como premium.

O trabalho aqui é majoritariamente **destravar e expor** essa infraestrutura já pronta de forma
mais direta (toggle na própria aba da inbox, sem exigir criar uma Policy separada), não
reescrever o algoritmo.

## Ordem de execução

| # | Task | Depende de |
|---|------|------------|
| [01](01-feature-advanced-assignment-global.md) | Destravar `advanced_assignment` globalmente (migration + `features.yml`) | — |
| [02](02-schema-assignment-mode.md) | Validação `assignment_mode` no jsonb + controller | — |
| [03](03-selector-assignment-mode-service.md) | Selector por inbox sem exigir `AssignmentPolicy` | 01, 02 |
| [04](04-frontend-toggle-assignment-mode.md) | UI: toggles de modo + online-only em `CollaboratorsPage.vue` | 01, 02, 03, 05 |
| [05](05-remover-online-only-fluxo-v2.md) | Fim do online-only no fluxo dominante (`InboxAgentAvailability`) | — |
| [06](06-remover-online-only-legado-time.md) | Fim do online-only no fluxo legado / reatribuição por time | — |
| [07](07-fallback-capacidade-rate-limit.md) | Fallback: nunca sem atribuição por capacidade/rate-limit | 03 |

Tasks 05-06 são independentes de 01-03 e podem ser feitas em paralelo. Task 04 depende de todas
as anteriores porque a UI expõe os dois toggles (modo de atribuição E online-only) na mesma
tela. Task 07 depende só de 03 (mesmo método `find_available_agent`).

## Decisões de produto já confirmadas

- **Instalação single-tenant** (só a conta "Noble Company" nesta instância) — confirmado
  explicitamente antes de aprovar a migration de backfill em `Account.find_in_batches`. Se este
  fork vier a ser usado como base multi-tenant no futuro, a task 01 precisa ser revisada antes
  de rodar de novo (não assumir que continua seguro sem reconfirmar).
- `premium: true` em `config/features.yml` **não bloqueia nada tecnicamente** neste fork — só
  controla agrupamento visual no painel Super Admin (`app/helpers/super_admin/*_helper.rb`).
  Removê-lo de `advanced_assignment` é seguro.
- O modo de atribuição (`assignment_mode`) e a config de online-only
  (`restrict_to_online_agents`) vivem dentro do jsonb `inboxes.auto_assignment_config` já
  existente — **sem migration de schema nova**, só validação de valores aceitos.
- `assignment_mode` reaproveita os mesmos literais já usados por `AssignmentPolicy#assignment_order`
  (`'round_robin'` / `'balanced'`) — vocabulário único no projeto, sem inventar termos novos
  (ex: não usar `'by_demand'`/`'least_busy'`).
- Fallback de capacidade/rate-limit: **estourar o limite como último recurso**, nunca deixar
  vazio — decisão explícita do usuário, com log estruturado obrigatório (não é silencioso).
  `filter_agents_by_team` **não** recebe esse fallback (fronteira rígida intencional).
- i18n: seguir a regra geral do `AGENTS.md` (só `en.yml`/`en.json`) — diferente da exceção já
  documentada para o domínio Kanban/Pipeline (que mantém pt_BR por decisão própria daquele
  ciclo). Este domínio (Inbox/Assignment) não tem essa exceção.

## Padrões existentes no código que estas tasks devem seguir (não reinventar)

- **Least-busy sem Redis**: `enterprise/app/services/enterprise/auto_assignment/balanced_selector.rb`
  já implementa via `inbox.conversations.open.where(assignee_id: ids).group(:assignee_id).count`
  + `Array#min_by` — reaproveitar essa classe integralmente, não duplicar a query em outro lugar.
- **Destravar feature globalmente**: dois precedentes reais no repo a combinar —
  `db/migrate/20260409091202_enable_assignment_v2_for_new_accounts.rb` (atualiza
  `InstallationConfig['ACCOUNT_LEVEL_FEATURE_DEFAULTS']` + `GlobalConfig.clear_cache`, para
  contas **novas**) e `db/migrate/20260120121402_enable_captain_tasks_for_existing_accounts.rb`
  (`Account.find_in_batches { |a| a.enable_features!(...) }`, para contas **existentes**).
- **Validação condicional community/enterprise**: `ensure_valid_max_assignment_limit` em
  `app/models/inbox.rb` (stub vazio, comentário `# overridden in enterprise/...`) +
  implementação real em `enterprise/app/models/enterprise/inbox.rb` — mesmo padrão a replicar
  para `ensure_valid_assignment_mode`.
- **`prepend_mod_with`**: todos os concerns/services tocados (`InboxAgentAvailability`,
  `Enterprise::AutoAssignment::AssignmentService`) já usam esse mecanismo de extensão — não
  criar um caminho de código paralelo, estender os métodos existentes.
- **`RequestExceptionHandler`** já tem `rescue_from ActiveRecord::RecordInvalid` global —
  validações novas em `Inbox` não precisam de rescue manual no controller.

## Riscos consolidados (detalhe em cada task)

1. Backfill de feature flag afeta **todas** as contas da instalação de uma vez — mitigado por
   confirmação explícita de single-tenancy antes de rodar (task 01).
2. `CollaboratorsPage.vue` tem hoje 3 estados mutuamente exclusivos; destravar `advanced_assignment`
   globalmente torna 1 deles código morto e faria outro virar o padrão indesejado — precisa de
   um 4º branch novo com precedência, não só "ligar a feature e torcer" (task 04).
3. Fluxo "legado" (`AgentAssignmentService`) não é só usado com `assignment_v2` desligado —
   também roda em toda reatribuição por time (`find_assignee_from_team`), então tem a MESMA
   prioridade do fluxo v2, não é aceitável tratar como secundário (tasks 05/06).
4. Rate-limit "fair distribution" tem default de 5 assignments/5min mesmo sem `AssignmentPolicy`
   — o cenário de fallback é plausível em pico de tráfego real, não hipotético (task 07).
5. Fallback pode sobrecarregar um agente em cenários extremos (todos no limite) — aceito como
   tradeoff consciente, mitigado só por visibilidade via log (task 07).
6. Sessões de dashboard já abertas não veem os novos toggles até recarregar a página (feature
   flag cacheada no Vuex client-side) — não é bug, documentar em release notes.

## Auditoria pós-implementação (tasks 08-15)

Depois que as tasks `01`-`07` foram implementadas, uma auditoria completa (bugs, código
morto, redundância, desvio de padrão) encontrou a maior parte do trabalho fiel ao spec,
com um punhado de problemas pontuais registrados como tasks de ajuste adicionais:

| # | Task | Tipo |
|---|------|------|
| [08](08-fix-dead-code-capacity-fallback.md) | Consolidar fallback de capacidade v2 duplicado (código morto por shadowing de `prepend_mod_with`) | Bug/código morto |
| [09](09-fix-stale-assignment-service-spec.md) | Corrigir teste inválido "returns 0 when no agents are online" | Bug em teste |
| [10](10-fix-dynamic-i18n-key-lint.md) | Remover chave i18n dinâmica em `assignmentModeOptions` (quebra `no-dynamic-keys`) | Bug/lint |
| [11](11-cobertura-policy-precedence-e2e.md) | Teste end-to-end de precedência de `AssignmentPolicy` | Cobertura |
| [12](12-cobertura-fallback-log-reason.md) | Asserções de log de fallback cobrindo `reason=`/`action=` | Cobertura |
| [13](13-cobertura-controller-invalid-mode.md) | Teste de integração do controller para `assignment_mode` inválido | Cobertura |
| [14](14-cobertura-frontend-template-wiring.md) | Fiação real do template + cenário `showDirectAssignmentModeUI === false` | Cobertura |
| [15](15-limpeza-qualidade-specs-menores.md) | Nomenclatura/consistência de specs + decisão documentada sobre `spec/db/migrate/` | Qualidade menor |

Nenhuma dessas tasks foi implementada ainda (assim como `01`-`07` originalmente) — são
especificações prontas para pegar e codar.
