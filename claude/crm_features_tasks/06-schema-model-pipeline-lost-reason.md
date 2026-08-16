# Task 06 — Schema + model `PipelineLostReason`

Feature 2 (parte 1 de 3).

## Objetivo

Criar a entidade "motivo de perda", lista configurável por conta (decisão já confirmada com
o usuário — não texto livre, não custom attribute genérico), seguindo o padrão de
`CannedResponse`/`Macro` (tabela dedicada `belongs_to :account`).

## O que criar

1. Migration 1:
   ```ruby
   create_table :pipeline_lost_reasons do |t|
     t.string :title, null: false
     t.references :account, null: false, foreign_key: true
     t.timestamps
   end
   add_index :pipeline_lost_reasons, [:account_id, :title], unique: true
   ```
2. Migration 2 (separada, ou combinada se o projeto costuma combinar — conferir precedente
   em `claude/pipeline_tasks/01-*.md`, que separou schema+validação em tasks distintas):
   ```ruby
   add_reference :pipeline_items, :pipeline_lost_reason, foreign_key: true
   ```
   Opcional (`null: true`) — só obrigatório condicionalmente (ver model abaixo).
3. `app/models/pipeline_lost_reason.rb`:
   ```ruby
   class PipelineLostReason < ApplicationRecord
     belongs_to :account
     has_many :pipeline_items, dependent: :nullify

     validates :title, presence: true, uniqueness: { scope: :account_id }
   end
   ```
   (`dependent: :nullify` em vez de `:destroy`/`:restrict` — se um motivo for removido da
   lista, os cards que já usaram esse motivo não devem ser apagados nem impedir a remoção;
   confirmar essa decisão faz sentido durante a implementação, é a opção menos destrutiva).
4. `app/models/pipeline_item.rb`:
   ```ruby
   belongs_to :pipeline_lost_reason, optional: true
   validates :pipeline_lost_reason_id, presence: true, if: -> { pipeline_stage&.lost? }
   ```

## Riscos

- A validação condicional (`if: -> { pipeline_stage&.lost? }`) precisa disparar tanto na
  criação quanto na atualização de um card já existente que muda pra `lost` — testar os dois
  caminhos.
- Confirmar que mover um card **para fora** de `lost` (ex. reabrir uma oportunidade) não
  exige limpar `pipeline_lost_reason_id` automaticamente — decisão recomendada: manter o
  histórico do último motivo registrado, não apagar ao sair do estágio (é dado informativo,
  não uma trava).

## Testes

Testar manualmente no Docker local: criar motivos de perda via `rails console`, mover um
card pra `lost` sem motivo (deve falhar a validação), mover com motivo (deve funcionar),
remover um motivo já usado por um card (card deve continuar existindo com
`pipeline_lost_reason_id: nil`).

## Critério de pronto

- Migrations aplicadas e revertíveis.
- Validação condicional funcionando nos dois caminhos (criação e update).
- `bundle exec rubocop -a` limpo nos arquivos tocados.
