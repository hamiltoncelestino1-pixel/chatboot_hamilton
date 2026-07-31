# Visão Geral — Remover a trava de reset noturno de features premium/branding

## Objetivo

Existe um mecanismo herdado do Chatwoot que, todo dia em produção, faz um ping pro servidor da
Chatwoot (`hub.2.chatwoot.com`) e, com base na resposta (ou mesmo se o ping falhar), **desliga
features premium pra todas as contas e reseta a configuração de branding de volta pro padrão
Chatwoot** — sempre que `InstallationConfig['INSTALLATION_PRICING_PLAN']` estiver como
`'community'`, que é o valor **default** desta instalação (nunca foi mudado).

Isso atrapalha diretamente o objetivo de "destravar features + manter o rebrand da Noble": sem
essa remoção, qualquer feature destravada globalmente (ex. `advanced_assignment`, do ciclo
anterior) e o próprio rebrand de marca correm risco de ser revertidos silenciosamente numa
madrugada, sem nenhum aviso na aplicação.

Escopo escolhido: não só neutralizar o reset, mas **desligar o ping/telemetria por completo**.

Este documento é o índice; cada arquivo `NN-*.md` nesta pasta é uma task independente. Nenhuma
task aqui foi implementada ainda.

## Arquitetura: defesa em profundidade em 3 camadas independentes

Cada camada ataca uma falha diferente da cadeia — nenhuma depende da outra pra ser eficaz. Isso
importa especificamente porque, se este fork algum dia voltar a sincronizar com o upstream
oficial do Chatwoot, um merge automático poderia reintroduzir isoladamente qualquer uma das 3
peças — com as 3 camadas, mesmo que 1 volte, as outras 2 seguram.

1. **Parar o cron que dispara tudo** — comentar a entrada em `config/schedule.yml`.
2. **Fixar `INSTALLATION_PRICING_PLAN` permanentemente longe de `'community'`** — migration
   setando `'enterprise'`.
3. **Neutralizar `Internal::ReconcilePlanConfigService#perform`** — vira um no-op documentado.

## Ordem de execução

| # | Task | Depende de |
|---|------|------------|
| [01](01-parar-cron-hub-ping.md) | Parar o cron do ping/telemetria | — |
| [02](02-fixar-pricing-plan-enterprise.md) | Fixar `INSTALLATION_PRICING_PLAN` em `'enterprise'` | — |
| [03](03-neutralizar-reconcile-service.md) | Neutralizar `ReconcilePlanConfigService` | — |

As 3 tasks são genuinamente independentes entre si (confirmado: nenhuma migration/config
sobrescreve o que a outra faz) — podem ser feitas em qualquer ordem e cabem num único commit/PR.

## Cadeia completa (confirmada linha por linha antes de propor este plano)

```
config/schedule.yml (cron diário 0h)
  → Internal::TriggerDailyScheduledItemsJob (agenda em horário fixo do dia, só se Rails.env.production?)
    → Internal::CheckNewVersionsJob (ping HTTP pro hub.2.chatwoot.com)
      → Enterprise::Internal::CheckNewVersionsJob (override sempre ativo neste fork)
        → grava INSTALLATION_PRICING_PLAN a partir da resposta do ping
        → chama reconcile_premium_config_and_features INCONDICIONALMENTE (mesmo se o ping falhar)
          → Internal::ReconcilePlanConfigService#perform
            → return cedo se pricing_plan != 'community'
            → senão: reseta branding (enterprise/config/premium_installation_config.yml)
            → e desliga features premium pra TODAS as contas (enterprise/config/premium_features.yml)
```

`ChatwootHub.pricing_plan` (`lib/chatwoot_hub.rb`) lê `InstallationConfig['INSTALLATION_PRICING_PLAN']`,
default `'community'` (`config/installation_config.yml`) — nunca alterado nesta instalação.

## O que é resetado quando dispara (confirmado)

- `enterprise/config/premium_features.yml`: `disable_branding`, `audit_logs`, `sla`,
  `custom_roles`, `captain_integration`, `csat_review_notes`, `conversation_required_attributes`.
  **`advanced_assignment` não está nessa lista** — o trabalho do ciclo anterior nunca esteve em
  risco por esse mecanismo especificamente, mas o branding e as outras 7 features sim.
- `enterprise/config/premium_installation_config.yml`: branding completo — `INSTALLATION_NAME`,
  `LOGO`, `LOGO_DARK`, `LOGO_THUMBNAIL`, `BRAND_NAME`, `BRAND_URL`, `TERMS_URL`, `PRIVACY_URL`.

## Decisões de produto já confirmadas

- Escopo: desligar o ping/telemetria por completo, não só o reset.
- Valor de destino pra `INSTALLATION_PRICING_PLAN`: **`'enterprise'`**, não `'premium'`. Motivo
  crítico: `enterprise/app/models/enterprise/concerns/user.rb` bloqueia criação de usuário novo
  quando `pricing_plan == 'premium'` **e** `User.count >= INSTALLATION_PRICING_PLAN_QUANTITY`
  (default `0`) — usar `'premium'` travaria a criação de usuários na conta inteira.
  `'enterprise'` é, inclusive, o valor que `ChatwootApp.self_hosted_enterprise?`
  (`lib/chatwoot_app.rb`) já espera para este cenário de instalação self-hosted.
- Branch dedicada: `fix/remove-premium-reset-lock`, separada do trabalho de assignment (que já
  tinha mudanças em andamento numa branch própria).

## Padrões existentes no código que estas tasks devem seguir (não reinventar)

- **Remover entrada de cron via `schedule.yml`**: já existe precedente real no repo — commit
  `1987ac3d9` removeu o cron `bulk_auto_assignment_job` da mesma forma. Confirmado: toda entrada
  carregada via `schedule.yml` desde esse commit já tem a tag `source: 'schedule'`
  (`lib/tasks/db_enhancements.rake`), então `Sidekiq::Cron::Job.load_from_hash!` **remove
  automaticamente do Redis** a entrada que sumir do YAML no próximo deploy — não precisa de
  nenhuma limpeza manual extra em `config/initializers/sidekiq.rb`.
- **Migration de dado em `InstallationConfig`**: mesmo padrão já usado no ciclo de assignment,
  `db/migrate/20260729120000_enable_advanced_assignment_globally.rb` — usar como referência de
  estilo (`find_or_initialize_by` + `update!`, sem `down`).
- **`spec/configs/schedule_spec.rb`** só verifica ausência de chaves duplicadas, ignorando
  linhas que começam com espaço/`#`/quebra de linha — comentar uma entrada não quebra esse spec,
  confirmado lendo o próprio spec antes de propor a mudança.

## Riscos consolidados (detalhe em cada task)

1. **Perda do banner de "nova versão disponível"** no dashboard (lido de
   `Redis::Alfred::LATEST_CHATWOOT_VERSION`, nunca mais atualizado sem o ping) — trade-off aceito
   conscientemente ao escolher desligar o ping por completo, não é bug.
2. **`INSTALLATION_PRICING_PLAN = 'enterprise'` libera superfícies extras** que hoje não existem
   na prática: seções extras no painel Super Admin > App Configs, checkboxes de feature editáveis
   na tela de edição de conta, e login SAML habilitado em `dashboard_controller.rb`. Não é
   regressão — é consistente com o objetivo geral do fork — mas o time deve saber que essas
   telas passam a existir/ficar acessíveis.
3. **Se este fork voltar a sincronizar com o upstream do Chatwoot**, um merge poderia
   reintroduzir isoladamente qualquer uma das 3 camadas — mitigado pela própria arquitetura de
   defesa em profundidade (task 03 sozinha já impede qualquer dano, mesmo que 01/02 revertam).
4. **Validação operacional pós-deploy** (não é código): conferir no Sidekiq Cron Web UI
   (`/sidekiq/cron`) que a entrada `internal_check_new_versions_job` sumiu do Redis depois do
   próximo deploy em produção.
