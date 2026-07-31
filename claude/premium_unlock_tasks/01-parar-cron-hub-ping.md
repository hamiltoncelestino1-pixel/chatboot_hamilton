# Task: Parar o cron do ping/telemetria pro hub da Chatwoot

## Objetivo

Impedir que a cadeia de jobs que faz ping pro `hub.2.chatwoot.com` (e, como consequência, dispara
o reset de features/branding) rode em produção. Camada 1 das 3 de defesa em profundidade — ver
`00-visao-geral.md`.

Esta task **não** mexe na lógica do que acontece se o job rodar (isso é a task `03`) nem no valor
de `INSTALLATION_PRICING_PLAN` (task `02`) — só impede o disparo do cron.

---

## Contexto importante

`config/schedule.yml` (linhas 1-10):
```yaml
# https://github.com/ondrejbartas/sidekiq-cron
# use https://crontab.guru/ to validate
# validations for this file exist in /spec/configs/schedule_spec.rb

# executed daily at 0000 UTC
# schedules daily deferred jobs at stable times for each installation
internal_check_new_versions_job:
  cron: '0 0 * * *'
  class: 'Internal::TriggerDailyScheduledItemsJob'
  queue: scheduled_jobs
```

`Internal::TriggerDailyScheduledItemsJob` (`app/jobs/internal/trigger_daily_scheduled_items_job.rb`)
só agenda `Internal::CheckNewVersionsJob` (que faz o ping de fato) se `Rails.env.production?` —
em dev/staging esse job já é essencialmente um no-op, mas em produção dispara todo dia.

**Precedente real no repo de exatamente essa remoção**: o commit `1987ac3d9` já removeu o cron
`bulk_auto_assignment_job` do `schedule.yml` da mesma forma (comentando/removendo a entrada).
Confirmado por leitura de `lib/tasks/db_enhancements.rake` + `config/initializers/sidekiq.rb`:
toda entrada carregada via `schedule.yml` desde esse commit já tem a tag `source: 'schedule'`
aplicada por `Sidekiq::Cron::Job.load_from_hash!(schedule, source: 'schedule')`. Isso significa
que, quando a entrada sumir do YAML, o próximo deploy **remove automaticamente a entrada
correspondente do Redis** — não é necessário nenhum `Sidekiq::Cron::Job.destroy` manual em
código (diferente do que foi preciso para o `bulk_auto_assignment_job`, que predatava essa tag).

`spec/configs/schedule_spec.rb` (lido por completo antes desta task):
```ruby
RSpec.context 'with valid schedule.yml' do
  it 'does not have duplicates' do
    ...
    invalid_line_starts = [' ', '#', "\n"]
    File.open(file).each do |f|
      f.each_line do |line|
        next if invalid_line_starts.include?(line[0])
        schedule_keys << line.split(':')[0]
      end
    end
    expect(schedule_keys.count).to eq(schedule_keys.uniq.count)
  end
end
```
Linhas que começam com `#` são explicitamente ignoradas pelo parser do teste — **comentar a
entrada não quebra esse spec**, confirmado antes de propor a mudança.

---

## 1. `config/schedule.yml`

```diff
 # https://github.com/ondrejbartas/sidekiq-cron
 # use https://crontab.guru/ to validate
 # validations for this file exist in /spec/configs/schedule_spec.rb

-# executed daily at 0000 UTC
-# schedules daily deferred jobs at stable times for each installation
-internal_check_new_versions_job:
-  cron: '0 0 * * *'
-  class: 'Internal::TriggerDailyScheduledItemsJob'
-  queue: scheduled_jobs
+# internal_check_new_versions_job: DESATIVADO DE PROPÓSITO.
+# Esse job fazia ping diário pro hub.2.chatwoot.com (telemetria + checagem de versão nova) e,
+# via Enterprise::Internal::CheckNewVersionsJob, disparava Internal::ReconcilePlanConfigService
+# — que resetava branding (INSTALLATION_NAME/LOGO/BRAND_NAME/...) e desligava features premium
+# pra TODAS as contas toda madrugada em produção, sempre que INSTALLATION_PRICING_PLAN fosse
+# 'community' (o default desta instalação). Este fork não usa licenciamento real — ver
+# claude/premium_unlock_tasks/00-visao-geral.md para o plano completo (3 camadas de defesa).
+# Não reativar sem uma decisão de produto explícita.
 # # executed At every 5th minute..
 trigger_scheduled_items_job:
   cron: '*/5 * * * *'
   class: 'TriggerScheduledItemsJob'
   queue: scheduled_jobs
```

---

## Verificação

- `bundle exec rspec spec/configs/schedule_spec.rb` — deve passar sem alteração nenhuma no spec.
- Manual pós-deploy (staging ou produção, não é possível verificar isso localmente): abrir
  `/sidekiq/cron` no ambiente e confirmar que a entrada `internal_check_new_versions_job` some da
  lista depois do primeiro deploy com essa mudança (o próprio `Sidekiq::Cron::Job.load_from_hash!`
  cuida da remoção, não precisa de comando manual).
- Confirmar que `trigger_scheduled_items_job` e as outras entradas do arquivo continuam intactas
  (`bundle exec rspec spec/configs/schedule_spec.rb` cobre isso via checagem de duplicatas, mas
  vale uma revisão visual do diff pra garantir que só a entrada certa foi comentada).
- `bundle exec rubocop`/lint de YAML não se aplica a `schedule.yml` (não é Ruby), mas conferir que
  o arquivo continua um YAML válido (`Psych.safe_load(File.read('config/schedule.yml'))` no
  console não deve lançar erro).
