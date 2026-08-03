# Visão Geral — Macros/Automações para Pipelines + Card Único por Pipeline

## Objetivo

Duas mudanças de produto no recurso de Pipeline/Kanban (CRM de oportunidades):

1. **Macros e Automation Rules aplicáveis a pipelines/estágios/cards** — hoje macros e
   automações só atuam sobre `Conversation`. Passam a existir ações e (num segundo momento)
   gatilhos nativos de pipeline, cobrindo tudo que hoje só é possível fazer manualmente no
   Kanban ou via API.
2. **Um card por contato por pipeline** — hoje um mesmo contato pode ter vários cards no
   mesmo pipeline (nada impede isso: sem validação de unicidade em `PipelineItem`, sem índice
   único no banco). Passa a ser no máximo 1 card por contato por pipeline, com migração de
   dados que mescla os duplicados existentes antes de travar a regra.

Este documento é o índice; cada arquivo `NN-*.md` nesta pasta é uma task de implementação
independente, na ordem recomendada de execução. Nenhuma task aqui foi implementada ainda —
são especificações prontas para pegar e codar.

## Ordem de execução

| # | Task | Depende de |
|---|------|------------|
| [01](01-schema-validacao-card-unico.md) | Schema: coluna `pipeline_id` + validação de unicidade | — |
| [02](02-migracao-mesclagem-duplicados.md) | Migração de dados: mesclar cards duplicados existentes | 01 |
| [03](03-reforco-criacao-edicao-card-unico.md) | Reforçar a regra em todos os pontos de criação/edição | 01, 02 |
| [04](04-automacao-acoes-pipeline-backend.md) | Automation Rules: novas ações de pipeline (backend) | 01 |
| [05](05-automacao-acoes-pipeline-frontend.md) | Automation Rules: novas ações de pipeline (frontend) | 04 |
| [06](06-macro-tipo-pipeline-e-servico-execucao.md) | Macros: `macro_type` + serviço de execução em pipeline | 01, 04 |
| [07](07-macro-pipeline-job-controller-rota.md) | Macros: job, controller e rota para executar em cards | 06 |
| [08](08-macro-pipeline-frontend-kanban.md) | Macros: UI "Rodar macro" no Kanban + editor | 06, 07 |
| [09](09-automacao-gatilhos-nativos-pipeline.md) | Automação: gatilhos nativos do pipeline (card criado/mudou de estágio) | 04 |
| [10](10-kanban-atualizacao-tempo-real.md) | Kanban: atualização em tempo real (ActionCable) | 09 (recomendado, não obrigatório) |

Tasks 01-03 = **Grupo A** (card único). Tasks 04-05 = **Grupo B** (ações de automação a
partir de eventos de conversa existentes). Tasks 06-08 = **Grupo C** (macros de pipeline).
Tasks 09-10 = **Grupo D** (gatilhos nativos + tempo real).

## Decisões de produto já confirmadas com o cliente

- Cards duplicados existentes: mesclados automaticamente por uma migração de dados (com
  relatório de dry-run antes de rodar em produção), não apagados sem critério.
- Critério de mesclagem: `won` > `normal` (mais avançado) > `start` > `lost`; valor do
  vencedor **não** é somado (perdedores ficam registrados na nota, nunca descartados).
- Tentativa de criar um 2º card do mesmo contato no mesmo pipeline (UI, API, automação,
  exportação entre pipelines): **bloqueada com erro**, nunca resolvida com upsert silencioso.
- Automação de pipeline cobre tanto "evento de conversa → ação de pipeline" quanto gatilhos
  nativos do próprio pipeline ("card entrou no estágio Ganho → ...").
- As novas ações/eventos ficam em CE (`app/`), no mesmo lugar onde o Pipeline/Kanban já vive
  hoje — não em `enterprise/`.

## Padrões existentes no código que estas tasks devem seguir (não reinventar)

- `PipelineMember#validates :user_id, uniqueness: { scope: :pipeline_id }`
  (`app/models/pipeline_member.rb`) — padrão exato de unicidade escopada para mirror na task 01.
- `ActionService` (`app/services/action_service.rb`) → `AutomationRules::ActionService` /
  `Macros::ExecutionService` — dispatch dinâmico `send(action[:action_name], action[:action_params])`;
  cada ação nova é só mais um método privado.
- `Current.executed_by = rule` (setado em `AutomationRules::ActionService#initialize`) +
  `dispatcher_dispatch` (usado em `conversation.rb`/`message.rb`, propaga
  `performed_by: Current.executed_by`) + `AutomationRuleListener#performed_by_automation?` —
  o guard anti-loop **já é genérico**; a task 09 só precisa fazer `PipelineItem` participar do
  mesmo mecanismo, não reinventar nada.
- `enterprise/app/models/enterprise/automation_rule.rb` (`super + %w[...]`) — padrão de
  extensão CE/EE, citado como referência caso este recurso vire Enterprise no futuro (não é o
  caso agora).
- `RequestExceptionHandler` (incluído em `application_controller.rb`) já tem
  `rescue_from ActiveRecord::RecordInvalid` global — qualquer `.save!`/`.update!` que falhar
  numa validação de model já vira 422 automaticamente, sem precisar de rescue manual extra.
- pt_BR é mantido pelo próprio projeto para automação/macros/kanban (`automation.json`,
  `macros.json`, `kanban.json` já existem em pt_BR) — toda chave de i18n nova destas tasks
  precisa ir nos dois locales, ao contrário da regra geral do AGENTS.md de só tocar arquivos en.

## Auditoria pós-implementação (2026-08-01) — tasks de correção

As 10 tasks acima foram implementadas (branch `feature/pipeline-automations-and-unique-card`,
ainda não commitada). Uma auditoria completa (3 agentes Explore + verificação manual) comparou a
implementação real contra cada spec e encontrou bugs, um risco de segurança não fechado, uma
redundância e um problema de UI silencioso, além de investigar a fundo o relato de que a
atualização em tempo real do Kanban não funciona. Tasks de correção, em ordem recomendada de
execução (11 é a mais crítica — risco de travar `db:migrate` em produção):

| # | Task | Cobre |
|---|------|-------|
| [11](11-fix-current-account-automacao-pipeline.md) | `Current.account` ausente no contexto assíncrono de automação de pipeline | tasks 02, 04, 09 |
| [12](12-fix-log-invalido-move-pipeline-item-stage.md) | Mensagem de log incorreta em `move_pipeline_item_stage` | task 04 |
| [13](13-fix-strong-params-actions-pipeline.md) | Strong params de `actions`/`action_params` nunca filtram de verdade | tasks 04, 07 |
| [14](14-fix-macro-pipeline-vazando-lista-conversa.md) | Macros de pipeline aparecendo na lista de macros de conversa | task 08 |
| [15](15-fix-estado-obsoleto-inputs-automacao-pipeline.md) | Estado obsoleto nos inputs compostos de pipeline ao trocar de ação | task 05 |
| [16](16-refactor-composable-selecao-pipeline.md) | Redundância de seleção de pipeline em 5 componentes (refactor) | tasks 05, 08 |
| [17](17-limpeza-itens-menores-pipeline.md) | Limpeza: 4 itens menores agrupados | várias |
| [18](18-diagnostico-tempo-real-kanban.md) | Diagnóstico ao vivo do tempo real (revisão estática não achou bug de código) | task 10 |

## Riscos consolidados (ver detalhe em cada task)

1. Condição de corrida na criação de cards sem índice único no banco (mitigado na task 01).
2. Perda de dado na migração de mesclagem — mitigado por relatório de dry-run + log estruturado
   (task 02); é a task de maior risco do plano.
3. Loop infinito de automação — mecanismo genérico já existe, mas testar explicitamente um
   ciclo de 2 regras (task 09).
4. Strong params de `action_params` em formato hash — precisa verificação prática antes de
   assumir que funciona sem ajuste (tasks 04 e 07).
5. Autorização em execução em lote de macro sobre múltiplos cards (task 07).
6. i18n duplicado (en + pt_BR) em todas as tasks de frontend.
7. Dívida técnica pré-existente (3 whitelists de ações sem fonte única de verdade) — mitigada
   parcialmente pelo módulo compartilhado da task 06, não é bloqueio.
8. Esforço incerto do broadcast em tempo real (task 10) — avaliar antes de comprometer prazo.
