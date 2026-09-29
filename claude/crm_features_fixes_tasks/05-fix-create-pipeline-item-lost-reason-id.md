# Task 05 — Fix: `create_params` não aceita `pipeline_lost_reason_id`, apesar do Swagger documentar

Severidade: 🟠 Alta. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).
Depende da task 01 (mesma validação de `pipeline_lost_reason_id` está envolvida).

## Objetivo

`app/controllers/api/v1/accounts/pipeline_items_controller.rb:113-127`:

```ruby
def create_params
  params.require(:pipeline_item).permit(
    :pipeline_stage_id, :contact_id, :conversation_id,
    :title, :value, :notes, :position, :assignee_id, :team_id,
    custom_attributes: {}
  )
end

def update_params
  params.require(:pipeline_item).permit(
    :pipeline_stage_id, :conversation_id,
    :title, :value, :notes, :position, :assignee_id, :team_id, :pipeline_lost_reason_id,
    custom_attributes: {}
  )
end
```

`update_params` permite `:pipeline_lost_reason_id`; `create_params` não. Confirmado que
`swagger/definitions/request/pipeline_item/create_update_payload.yml:24` documenta
`pipeline_lost_reason_id` num payload **compartilhado** entre `create.yml` e `update.yml`
(`swagger/paths/application/pipelines/items/create.yml:13` referencia o mesmo
`pipeline_item_create_update_payload` usado por `update.yml:13`).

**Efeito**: um cliente de API que segue o contrato documentado no Swagger e envia
`pipeline_lost_reason_id` no `POST /pipeline_items` apontando pra um estágio `lost` tem o
parâmetro silenciosamente descartado pelo strong params — a validação
(`app/models/pipeline_item.rb:71`) falha, e não existe forma de satisfazê-la nesse endpoint.
Card não pode ser criado diretamente em "perdido" via API, mesmo sendo um caso de uso legítimo
(ex. importação de dados históricos).

## O que corrigir

Adicionar `:pipeline_lost_reason_id` a `create_params`, mesmo formato de `update_params` na
linha ao lado.

## Testes

Testar manualmente: `POST /api/v1/accounts/:account_id/pipeline_items` com
`pipeline_stage_id` de um estágio `lost` e `pipeline_lost_reason_id` válido — card deve ser
criado com sucesso, sem erro de validação.

## Critério de pronto

- `create_params` permite `pipeline_lost_reason_id`.
- Criar card diretamente em estágio `lost` via API funciona, condizente com o Swagger já
  documentado.
- `bundle exec rubocop -a` limpo no arquivo tocado.

## Resultado (2026-09-29)

Uma linha em `create_params` (`pipeline_items_controller.rb:159`), acrescentando
`:pipeline_lost_reason_id` na mesma posição em que aparece no `update_params` (linha 167).

**Swagger não precisou de alteração** — confirmado que
`swagger/definitions/request/pipeline_item/create_update_payload.yml` já documentava o campo e é
compartilhado por `create.yml:13` e `update.yml:13`. Era o código que divergia do contrato, não o
contrário; nenhum `swagger:build` foi necessário.

**Verificação empírica** (`rails runner` no Docker local, conta 1, stage lost 440, reason 2),
os três cenários medidos e não inferidos:

| Cenário | Resultado |
|---|---|
| `permit` recebe `pipeline_lost_reason_id` | `true` (antes era descartado) |
| Estágio `lost` **com** reason | válido, `save!` OK (criado id 116378, revertido por `ActiveRecord::Rollback`) |
| Estágio `lost` **sem** reason | continua inválido: `["Pipeline lost reason can't be blank"]` — a regra não foi afrouxada |
| Estágio normal sem reason | continua válido — caminho que a UI usa, sem regressão |

Nada persistido no banco de dev (a criação rodou dentro de transação com rollback).

**Suítes:** `rspec spec/controllers/api/v1/accounts/pipeline_items_controller_spec.rb` →
6 examples, 0 failures.

**Rubocop:** 1 ofensa no arquivo, **pré-existente e fora do diff** —
`Rails/SkipsModelValidations` na linha 79 (`update_column` dentro do `reorder`, vindo da task 24
de `claude/pipeline_performance_tasks/`). Confirmado com `git show HEAD:<arquivo>` que a linha 79
é idêntica no HEAD e que o diff toca apenas a linha 159. Diferente de
`Tasks::TriggerDueTasksJob`, que usa `update_column` com `# rubocop:disable` explícito, o
`reorder` não tem a diretiva — dívida de lint conhecida daquele épico, não tratada aqui.
