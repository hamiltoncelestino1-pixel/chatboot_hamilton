# Task 01 — Fix: automação/macro "mover card pra estágio perdido" sempre falha silenciosamente

Severidade: 🔴 Crítico. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

⚠️ **Esta task exige decisão de produto do usuário antes de implementar** — não é só um fix de
linha, muda a UX de configuração de automação/macro.

## Objetivo

`app/models/pipeline_item.rb:69-71`:

```ruby
# Not cleared automatically when a card leaves the lost stage (e.g. reopened) - it's kept as
# informational history of the last recorded reason, not a hard constraint.
validates :pipeline_lost_reason_id, presence: true, if: -> { pipeline_stage&.lost? }
```

Essa validação foi adicionada pelo commit `df0251e58` (feature de motivo de perda) e está
correta para o fluxo manual (drag-and-drop / painel do card, que já coleta o motivo via
`LostReasonModal.vue` antes de persistir). O problema é que **outros dois caminhos que também
movem um card pra um estágio `lost` não foram atualizados**:

`app/services/concerns/pipeline_item_actions.rb:9-15` (método pré-existente, não tocado pelo
commit):

```ruby
def move_stage(pipeline_item, target_stage_id)
  target_stage = PipelineStage.find_by(id: target_stage_id, pipeline_id: pipeline_item.pipeline_id)
  return nil if target_stage.blank?

  pipeline_item.update!(pipeline_stage_id: target_stage.id, position: next_position_for_stage(target_stage))
  target_stage
end
```

Nunca seta `pipeline_lost_reason_id`. Esse método é chamado por:
- `AutomationRules::PipelineActionService#move_pipeline_item_stage`
- `Macros::PipelineExecutionService#move_pipeline_item_stage`

Ambos os chamadores envolvem a execução inteira num `rescue StandardError => e` que só manda
pro `ChatwootExceptionTracker`/Sentry — sem propagar erro nenhum pro usuário.

**Efeito**: desde o deploy do commit `df0251e58`, **toda** automação ou macro configurada para
mover um card pra um estágio do tipo `lost` passou a falhar com `ActiveRecord::RecordInvalid`
dentro do `update!`, engolido silenciosamente. O admin configura a automação, ela "roda" sem
erro visível na UI, mas o card nunca muda de estágio. Só aparece no Sentry.

## Decisão de produto a confirmar com o usuário antes de codar

Duas abordagens possíveis:
1. **Coletar o motivo na configuração da automação/macro** — mesmo padrão já usado pra "criar
   task" (`AutomationActionCreatePipelineItemTaskInput.vue`, task 09 do épico CRM): quando o
   admin escolhe a ação "mover pra estágio X" e X é do tipo `lost`, a UI exige selecionar um
   `PipelineLostReason` fixo que será aplicado toda vez que a automação/macro rodar.
2. **Bloquear a ação na configuração** — não permitir escolher um estágio `lost` como alvo de
   `move_pipeline_item_stage` em automação/macro (mensagem explicando que isso só pode ser
   feito manualmente, já que exige um motivo específico por card).

A opção 1 é mais alinhada ao padrão já existente no projeto (task 09 do mesmo épico resolveu
exatamente esse tipo de problema assim) — recomendação é seguir essa linha, mas confirmar com
o usuário antes de implementar.

## O que corrigir (assumindo aprovação da opção 1)

1. Backend: `move_stage` (`pipeline_item_actions.rb:9-15`) passa a aceitar um parâmetro
   opcional `pipeline_lost_reason_id` e setá-lo no `update!` quando presente.
2. `AutomationRules::PipelineActionService#move_pipeline_item_stage` e
   `Macros::PipelineExecutionService#move_pipeline_item_stage` passam esse valor adiante,
   lido dos parâmetros da ação configurada (whitelist em `AutomationRule#actions_attributes`,
   `app/models/automation_rule.rb:42-49`, e no equivalente de `Macro` se houver whitelist
   própria — checar antes de assumir que é o mesmo lugar).
3. Frontend: novo input de seleção de `PipelineLostReason` na configuração da ação
   "mover estágio de pipeline", visível só quando o estágio alvo selecionado for do tipo
   `lost` — mesmo padrão reativo de `AutomationActionCreatePipelineItemTaskInput.vue`.
4. Automações/macros já configuradas e salvas **antes** deste fix, que apontam pra um estágio
   `lost` sem motivo, continuarão falhando até o admin reconfigurar — decidir se vale um aviso
   na UI de automação para configurações existentes nessa condição (fora do escopo mínimo, mas
   perguntar ao usuário se quer isso).

## Testes

Testar manualmente no Docker local: criar uma automação com ação "mover pra estágio perdido"
configurada com motivo fixo, disparar o evento gatilho, confirmar que o card muda de estágio
com `pipeline_lost_reason_id` preenchido. Repetir para uma macro equivalente. Confirmar que
mover pra um estágio **não**-`lost` via automação/macro continua funcionando sem exigir nada
novo (não regredir o caminho feliz).

## Critério de pronto

- Automação e macro configuradas para mover card pra estágio `lost` funcionam de ponta a
  ponta, sem exceção engolida pelo rescue genérico.
- Card movido por automação/macro tem `pipeline_lost_reason_id` preenchido corretamente.
- Mover pra estágio não-`lost` via automação/macro continua idêntico ao comportamento atual.
- `bundle exec rubocop -a` e `pnpm eslint:fix` limpos nos arquivos tocados.
