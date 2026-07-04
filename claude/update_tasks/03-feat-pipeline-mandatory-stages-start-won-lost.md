# Task: Etapas obrigatórias de pipeline — Início, Ganho e Perdido

## Objetivo

Todo pipeline deve nascer (e permanecer) com uma estrutura mínima obrigatória:

1. Uma etapa **inicial** ("start"), onde toda nova oportunidade é criada por padrão. Pode ser
   renomeada, mas nunca excluída.
2. Duas etapas **finais** obrigatórias, "Ganho" (won) e "Perdido" (lost). Também podem ser
   renomeadas, mas nunca excluídas.
3. Etapas intermediárias continuam totalmente livres (criar, renomear, excluir, reordenar).

Esta task é pré-requisito da task `05-fix-pipeline-settings-agents-tab-and-auto-assignment.md`, que
usa o conceito de "etapa final" (`won`/`lost`) para decidir o que conta como oportunidade aberta na
atribuição automática.

## Diagnóstico (código atual verificado)

`app/models/pipeline_stage.rb` não tem nenhum conceito de tipo — todas as etapas são simétricas.

`app/javascript/dashboard/routes/dashboard/settings/pipelines/PipelineStagesSection.vue:74-92`
(`confirmDelete`) permite excluir **qualquer** etapa sem checagem alguma, chamando
`kanban/deleteStage` diretamente.

`app/javascript/dashboard/routes/dashboard/settings/pipelines/AddPipeline.vue` cria só o registro
`Pipeline` — **nenhuma etapa é criada junto**. O pipeline nasce vazio; o usuário precisa clicar em
"Adicionar etapa" manualmente uma a uma em `PipelineStagesSection.vue`.

Pipelines já existentes no ambiente de testes (ex. "Funil de Vendas", visto em produção/dev com as
etapas "Nova Oportunidade", "Lead", "Qualificado", "Proposta", "Ganho") não têm essa estrutura
formalizada — precisam de uma migration de dados que não perca as etapas já em uso.

---

## 1. Backend

### 1.1 Migration de schema

```bash
bundle exec rails g migration AddStageTypeToPipelineStages stage_type:integer
```

```ruby
class AddStageTypeToPipelineStages < ActiveRecord::Migration[7.1]
  def change
    add_column :pipeline_stages, :stage_type, :integer, null: false, default: 0
  end
end
```

### 1.2 Migration de dados (data migration, arquivo separado)

```ruby
class BackfillPipelineStageTypes < ActiveRecord::Migration[7.1]
  disable_ddl_transaction!

  def up
    Pipeline.find_each do |pipeline|
      stages = pipeline.pipeline_stages.order(:position)
      next if stages.empty?

      first_stage = stages.first
      first_stage.update_column(:stage_type, PipelineStage.stage_types[:start])

      won_stage = stages.find { |s| s.name.match?(/\A(ganho|won)\z/i) }
      if won_stage
        won_stage.update_column(:stage_type, PipelineStage.stage_types[:won])
      else
        pipeline.pipeline_stages.create!(
          name: 'Ganho', color: '#1f9e51',
          position: (stages.map(&:position).max || 0) + 1,
          stage_type: PipelineStage.stage_types[:won], account_id: pipeline.account_id
        )
      end

      lost_stage = stages.find { |s| s.name.match?(/\A(perdido|lost)\z/i) }
      if lost_stage
        lost_stage.update_column(:stage_type, PipelineStage.stage_types[:lost])
      else
        pipeline.pipeline_stages.create!(
          name: 'Perdido', color: '#e35b5b',
          position: (pipeline.pipeline_stages.maximum(:position) || 0) + 1,
          stage_type: PipelineStage.stage_types[:lost], account_id: pipeline.account_id
        )
      end
    end
  end

  def down
    PipelineStage.update_all(stage_type: 0)
  end
end
```

**Nota**: rodar em `disable_ddl_transaction!` + `find_each` por segurança em bases com muitos
pipelines; se o volume for pequeno (esperado, dado o estágio do produto), uma transação única
também é aceitável — decidir no momento da implementação.

### 1.3 `app/models/pipeline_stage.rb`

```ruby
class PipelineStage < ApplicationRecord
  belongs_to :account
  belongs_to :pipeline
  has_many :pipeline_items, -> { order(:position) }, dependent: :destroy_async

  enum stage_type: { normal: 0, start: 1, won: 2, lost: 3 }

  validates :name,
            presence: { message: I18n.t('errors.validations.presence') },
            uniqueness: { scope: :pipeline_id }
  validates :stage_type, uniqueness: { scope: :pipeline_id }, unless: :normal?

  before_destroy :prevent_special_stage_deletion

  def push_event_data
    { id: id, name: name, color: color, position: position, pipeline_id: pipeline_id, stage_type: stage_type }
  end

  private

  def prevent_special_stage_deletion
    return if normal?

    errors.add(:base, I18n.t('errors.pipeline_stage.cannot_delete_special_stage'))
    throw :abort
  end
end
```

Adicionar a chave `errors.pipeline_stage.cannot_delete_special_stage` em `config/locales/en.yml`
(e demais locales relevantes, seguindo o padrão de erros já usado no projeto).

### 1.4 `app/models/pipeline.rb`

```ruby
after_create :create_default_stages

private

def create_default_stages
  pipeline_stages.create!(name: 'Nova oportunidade', color: '#1f93ff', position: 0, stage_type: :start)
  pipeline_stages.create!(name: 'Ganho', color: '#1f9e51', position: 1, stage_type: :won)
  pipeline_stages.create!(name: 'Perdido', color: '#e35b5b', position: 2, stage_type: :lost)
end
```

(mover `private` para o local correto do arquivo, preservando os métodos `add_members`/
`remove_members`/`push_event_data` já existentes.)

### 1.5 `app/controllers/api/v1/accounts/pipeline_stages_controller.rb`

- `#create`: no `pipeline_stage_params` (ou logo antes do `.create`), forçar
  `stage_type: :normal` — ignorar qualquer `stage_type` vindo do payload do cliente.
- `#destroy`: nenhuma mudança de código estritamente necessária (o `before_destroy` do model já
  bloqueia), mas verificar que o `rescue`/tratamento de erro do controller devolve
  `render_could_not_create_error` (ou equivalente) com a mensagem de `errors[:base]`, em vez de um
  500 genérico.
- `#reorder`: antes de persistir a nova ordem, normalizar a lista recebida:
  - mover a etapa `start` (se presente na lista) para a posição 0;
  - mover as etapas `won`/`lost` (se presentes) para as duas últimas posições, mantendo a ordem
    relativa entre elas que veio do cliente;
  - as etapas `normal` preenchem as posições intermediárias, na ordem recebida.

### 1.6 `PipelineItem` — etapa padrão na criação

Confirmar em `app/controllers/api/v1/accounts/pipeline_items_controller.rb#create` (ou onde a etapa
padrão é resolvida ao criar uma oportunidade sem `pipeline_stage_id` explícito) se já usa a primeira
etapa por posição ou se precisa ser ajustado para buscar explicitamente
`pipeline.pipeline_stages.find_by(stage_type: :start)`.

---

## 2. Frontend

### 2.1 `app/javascript/dashboard/routes/dashboard/settings/pipelines/PipelineStagesSection.vue`

No template, no bloco `v-else` (linhas 161-175), condicionar o botão de excluir:

```vue
<template v-else>
  <span class="flex-1 text-sm text-n-slate-12">{{ stage.name }}</span>
  <button
    class="text-n-slate-9 hover:text-n-slate-11 transition-colors"
    @click="startEdit(stage)"
  >
    <span class="i-woot-edit-pen size-4" />
  </button>
  <span
    v-if="stage.stage_type !== 'normal'"
    class="text-n-slate-6 cursor-not-allowed"
    :title="t('PIPELINE_MGMT.STAGE.DELETE.LOCKED')"
  >
    <span class="i-lucide-lock size-4" />
  </span>
  <button
    v-else
    class="text-n-slate-9 hover:text-n-ruby-11 transition-colors"
    @click="openDeleteModal(stage)"
  >
    <span class="i-woot-bin size-4" />
  </button>
</template>
```

Para travar a posição no drag-and-drop, usar a prop `move` do `vuedraggable` para rejeitar
movimentos que tirem uma etapa especial da posição fixa, ou simplificar exibindo o `drag-handle`
apenas para etapas `normal`:

```vue
<span
  v-if="stage.stage_type === 'normal'"
  class="drag-handle i-lucide-grip-vertical size-4 text-n-slate-9 cursor-grab"
/>
<span v-else class="size-4" />
```

(handle vazio para etapas especiais impede que sejam arrastadas, já que `vuedraggable` está
configurado com `handle=".drag-handle"`.)

### 2.2 i18n

`pipelineMgmt.json` (en):
```json
"STAGE": {
  "DELETE": {
    "LOCKED": "This stage is required and cannot be deleted"
  }
}
```

`pipelineMgmt.json` (pt_BR):
```json
"STAGE": {
  "DELETE": {
    "LOCKED": "Esta etapa é obrigatória e não pode ser excluída"
  }
}
```

---

## Verificação

1. Criar um pipeline novo em Configurações > Pipelines — deve nascer automaticamente com 3 etapas:
   "Nova oportunidade" (início), "Ganho", "Perdido".
2. Tentar excluir qualquer uma dessas 3 — botão de excluir deve estar bloqueado (cadeado) na UI; e
   uma tentativa via API direta deve retornar erro, não 500.
3. Renomear a etapa "Nova oportunidade" para outro nome — deve funcionar normalmente, sem perder o
   `stage_type: start`.
4. Criar uma etapa intermediária nova — deve nascer como `normal`, com exclusão/edição/reorder
   livres.
5. Rodar a migration de dados num ambiente com o pipeline "Funil de Vendas" já existente — conferir
   que "Nova Oportunidade" virou `start`, "Ganho" virou `won`, e uma nova etapa "Perdido" foi criada
   ao final, sem apagar nenhuma etapa intermediária ("Lead", "Qualificado", "Proposta").
6. Criar uma nova oportunidade sem especificar etapa — deve cair na etapa `start` do pipeline ativo.
7. Tentar reordenar via drag-and-drop movendo "Ganho" para o meio da lista — deve ser rejeitado ou
   normalizado de volta para a posição final.
