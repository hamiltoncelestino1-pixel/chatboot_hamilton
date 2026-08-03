# Task 13 — Fix: strong params de `actions`/`action_params` nunca filtram de verdade

Task de correção pós-implementação das tasks 04 e 07. Achado na auditoria de 2026-08-01.
**Decisão já confirmada com o cliente: unificar as duas fontes e filtrar de verdade** (não só
documentar o bypass) — fechando a superfície de mass-assignment.

## Objetivo

As tasks 04 (item 4) e 07 (item 3) pediam para verificar se `action_params: []` no `permit`
aceita um array contendo hash (formato necessário pelas novas ações de pipeline,
`[{pipeline_id:, target_stage_id:, ...}]`), já que a forma `chave: []` do Rails strong params
trata o array como lista de **escalares permitidos** — elementos `Hash` são removidos
silenciosamente.

Isso **nunca foi de fato corrigido** em nenhum dos dois controllers, e o motivo pelo qual os
testes existentes passam mesmo assim é que `actions`/`action_params` nunca vêm do `permit` — vêm
do `params[...]` bruto:

**`app/controllers/api/v1/accounts/automation_rules_controller.rb`:**
```ruby
def automation_rules_permit
  params.permit(
    :name, :description, :event_name, :active,
    conditions: [...],
    actions: [:action_name, { action_params: [] }]   # <- nunca usado para popular .actions=
  )
end
```
`create`/`update` chamam `validate_and_prepare_attachments(params[:actions])` (em
`AttachmentConcern`, pré-existente) e atribuem o retorno bruto (só levemente tratado para
`send_attachment`) direto em `@automation_rule.actions = actions` — **sem passar pelo permit**.

**`app/controllers/api/v1/accounts/macros_controller.rb`:**
```ruby
def permitted_params
  params.permit(
    :name, :visibility, :macro_type,
    actions: [:action_name, { action_params: [] }]   # <- mesmo problema
  )
end
```
`create`/`update` fazem exatamente o mesmo: `blobs, actions, error =
validate_and_prepare_attachments(params[:actions], @macro)` e depois `@macro.actions = actions`
— o `permit` nunca participa dessa atribuição.

**Consequência real (além de não ter cumprido o que a task pedia):** o campo `actions` de
`AutomationRule` e `Macro` nunca passou por um allowlist de mass-assignment do Rails — qualquer
chave arbitrária dentro de cada ação (`action_params`) chega ao jsonb sem filtragem alguma. Não é
uma regressão introduzida por estas tasks (o padrão já existia antes, para `send_attachment`/
`send_email_to_team`), mas as tasks 04/07 explicitamente pediam para fechar esse ponto e isso não
aconteceu.

## O que corrigir (abordagem aprovada: unificar e filtrar de verdade)

1. Em ambos os controllers, corrigir o `permit` para aceitar hash de fato:
   ```ruby
   actions: [:action_name, { action_params: [{}] }]
   ```
   (`[{}]` é a forma do Rails para "array de hashes, permite todas as chaves de cada hash" —
   equivalente ao que já seria necessário fazer explicitamente se a chave dentro de cada ação
   precisar ser restrita no futuro; por ora libera todas as chaves de `action_params`, mesmo
   comportamento observável de hoje mas agora através do allowlist).
2. Substituir o uso de `params[:actions]` bruto por `permitted_params[:actions]` (ou
   `automation_rules_permit[:actions]`) como entrada de `validate_and_prepare_attachments`, de
   forma que `.actions=` seja de fato populado a partir do valor filtrado pelo `permit`, não do
   `params` cru.
3. Testar explicitamente que os formatos antigos continuam funcionando após a mudança:
   - `add_label`/`remove_label` (array de strings escalares em `action_params`).
   - `send_email_to_team` (hash em `action_params`, já usado em produção hoje).
   - `send_attachment` (fluxo de blob_ids, que passa por `validate_and_prepare_attachments`
     separadamente — confirmar que a mudança no `permit` não quebra esse caminho).
   - As 8 novas ações de pipeline (hash em `action_params`).

## Testes

- `spec/controllers/api/v1/accounts/automation_rules_controller_spec.rb` — o exemplo existente
  `'stores a hash-shaped action_params (not just an array of scalars) intact'` (linha ~225) deve
  passar a exercitar de fato o caminho do `permit` (hoje passa por acidente); adicionar um
  exemplo negativo: enviar uma chave extra não esperada dentro de `action_params` de uma ação
  qualquer e confirmar que ela é preservada (já que `[{}]` permite todas as chaves) — documentando
  o comportamento, não restringindo chave por chave (fora de escopo desta task).
  Adicionar também um teste de regressão para `add_label` (array de strings) continuando a
  funcionar.
- `spec/controllers/api/v1/accounts/macros_controller_spec.rb` — mesmo tratamento, incluindo o
  exemplo já existente `'stores a hash-shaped action_params for a pipeline macro intact'`
  (linha ~568) passando a exercitar o `permit` de verdade.

## Critério de pronto

- `.actions=` populado a partir do valor já filtrado pelo `permit` em ambos os controllers (não
  mais do `params` bruto).
- `action_params: [{}]` aceitando hash corretamente, com todos os formatos antigos (escalar e
  hash) cobertos por teste de regressão.
- `bundle exec rubocop -a` limpo nos arquivos tocados.
