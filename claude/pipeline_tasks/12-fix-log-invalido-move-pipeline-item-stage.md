# Task 12 — Fix: mensagem de log incorreta em `move_pipeline_item_stage` (automação)

Task de correção pós-implementação da task 04. Achado na auditoria de 2026-08-01.

## Objetivo

`app/services/automation_rules/action_service.rb:86-93`:

```ruby
def move_pipeline_item_stage(params)
  params = params[0]
  item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
  return log_no_pipeline_item('move_pipeline_item_stage', params[:pipeline_id]) if item.blank?

  target_stage = move_stage(item, params[:target_stage_id])
  log_no_pipeline_item('move_pipeline_item_stage', params[:pipeline_id]) if target_stage.blank?
end
```

O segundo `if` (linha 92) reusa `log_no_pipeline_item`, cuja mensagem diz **"no pipeline_item
found"** — mas nesse ponto o card **já foi encontrado** (`item.blank?` já retornou `false` na
linha anterior). O motivo real de `target_stage.blank?` aqui é que `params[:target_stage_id]`
não pertence ao pipeline do card (é isso que `move_stage`, em
`app/services/concerns/pipeline_item_actions.rb:9-15`, retorna `nil` para). A mensagem logada é
factualmente incorreta e vai confundir quem depurar produção — o card existe, o problema é o
estágio configurado na regra.

**Comparação com o código irmão (mesmo padrão, resolvido corretamente lá):**
`AutomationRules::PipelineActionService` (task 09), que compartilha a mesma lógica de
`move_stage` via o módulo `PipelineItemActions`, tem seu próprio helper de log correto:

```ruby
# app/services/automation_rules/pipeline_action_service.rb
def log_invalid_target_stage(target_stage_id)
  Rails.logger.info(
    "[AutomationRules::PipelineActionService] target_stage_id=#{target_stage_id} does not belong to " \
    "pipeline_item##{@pipeline_item.id}'s pipeline (pipeline_id=#{@pipeline_item.pipeline_id})"
  )
end
```

A inconsistência é só em `action_service.rb` (task 04) — o serviço espelho da task 09 já faz
certo.

## O que corrigir

Em `app/services/automation_rules/action_service.rb`, extrair um segundo helper de log
(`log_invalid_target_stage`), mirror do já existente em `pipeline_action_service.rb`, e usá-lo no
segundo `if` de `move_pipeline_item_stage`:

```ruby
def move_pipeline_item_stage(params)
  params = params[0]
  item = resolve_pipeline_item_for_conversation(params[:pipeline_id])
  return log_no_pipeline_item('move_pipeline_item_stage', params[:pipeline_id]) if item.blank?

  target_stage = move_stage(item, params[:target_stage_id])
  log_invalid_target_stage(params[:target_stage_id], item) if target_stage.blank?
end

def log_invalid_target_stage(target_stage_id, item)
  Rails.logger.info(
    "[AutomationRules::ActionService] target_stage_id=#{target_stage_id} does not belong to " \
    "pipeline_item##{item.id}'s pipeline (pipeline_id=#{item.pipeline_id})"
  )
end
```

## Testes

`spec/services/automation_rules/action_service_spec.rb`, describe `'#perform with
move_pipeline_item_stage action'` (linhas ~241-263) — hoje só testa "does nothing when the
contact has no card in the pipeline". Adicionar o exemplo simétrico que falta (espelhando o já
existente em `pipeline_action_service_spec.rb:25-31`): card existe, `target_stage_id` não
pertence ao pipeline do card → card permanece no estágio original, e a mensagem logada (pode ser
verificada via `expect(Rails.logger).to receive(:info).with(/does not belong to/)` ou equivalente)
não menciona "no pipeline_item found".

## Critério de pronto

- Novo exemplo de spec passando, cobrindo especificamente o cenário de `target_stage_id`
  inválido (não só "card inexistente").
- Mensagem de log correta e simétrica entre `action_service.rb` e `pipeline_action_service.rb`.
