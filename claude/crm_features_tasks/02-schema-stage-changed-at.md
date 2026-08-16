# Task 02 — Schema: coluna `stage_changed_at` em `pipeline_items`

Feature 3 (parte 1 de 2). Base de dados também consumida pela task 04 (feature 5).

## Objetivo

`PipelineItem` não tem hoje nenhuma coluna que sirva de proxy confiável para "há quanto
tempo o card está no estágio atual" — `updated_at` muda em qualquer edição (título, notas,
custom attributes), não só em mudança de estágio, então não serve para isso. Criar a coluna
dedicada.

## O que criar

1. Migration:
   ```ruby
   add_column :pipeline_items, :stage_changed_at, :datetime
   add_column :pipeline_items, :stale_alert_sent_at, :datetime
   ```
   `stale_alert_sent_at` já entra nesta migration (mesmo papel de `reminder_sent_at` em
   `Task` — evita a task 03 notificar o mesmo card repetidamente), mesmo que o job que a usa
   só seja implementado na task 03, para não precisar de uma segunda migration depois.
2. Migration de dados (data migration, mesmo padrão de
   `claude/pipeline_tasks/02-migracao-mesclagem-duplicados.md` se aplicável — conferir se
   esta migration precisa rodar em `up`/`down` com backfill ou se pode ser parte da mesma
   migration de schema): popular `stage_changed_at` com `created_at` para todos os registros
   existentes (aproximação razoável — não sabemos quando cada card mudou de estágio pela
   última vez antes desta feature existir).
3. `app/models/pipeline_item.rb` — callback novo:
   ```ruby
   before_save :touch_stage_changed_at, if: :pipeline_stage_id_changed?

   def touch_stage_changed_at
     self.stage_changed_at = Time.zone.now
   end
   ```
   E inicializar em `stage_changed_at` no momento da criação do card (garantir que todo card
   novo já nasce com o valor setado, não só em mudanças subsequentes — conferir se
   `pipeline_stage_id_changed?` já é `true` na criação, que é o comportamento padrão do
   Rails para um novo registro com atributo presente; se sim, o callback acima já cobre a
   criação também, sem precisar de lógica duplicada).

## Riscos

- Confirmar que o callback dispara **só** quando `pipeline_stage_id` muda de fato, não em
  qualquer `update!` do card — testar explicitamente editando outros campos (título, notas)
  e confirmando que `stage_changed_at` **não** muda.
- Esta task não implementa nenhum job/notificação ainda — é só schema + callback. As tasks
  03 e 04 consomem essa coluna depois.

## Testes

Testar manualmente no Docker local (ou via `rails console`): criar um card, mover de
estágio, confirmar que `stage_changed_at` atualiza; editar só o título, confirmar que
`stage_changed_at` **não** muda.

## Critério de pronto

- Migration aplicada e revertível (`rails db:rollback` funciona).
- `stage_changed_at` reflete corretamente só mudanças de estágio.
- Registros existentes populados com `created_at` como aproximação inicial.
- `bundle exec rubocop -a` limpo nos arquivos tocados.
