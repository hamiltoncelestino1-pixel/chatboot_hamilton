# Task 02 — N+1 de `label_list` e de `avatar_url` na serialização de cada card

Severidade: 🔴 Crítico. Achado na análise de performance de 2026-09-15.

## Objetivo

`app/views/api/v1/models/_pipeline_item.json.jbuilder` dispara **duas** cadeias de query por
card renderizado:

```ruby
json.contact do
  # ...
  json.avatar_url resource.contact.avatar_url        # linha 19
end
# ...
json.label_list resource.label_list                  # linha 36
```

**Labels.** `PipelineItem` inclui `Labelable` (`app/models/pipeline_item.rb:46`), que é
`acts_as_taggable_on :labels` (`app/models/concerns/labelable.rb:5`). `label_list` lê a
associação de taggings e, para cada tagging, a `tag` — sem eager load são 1-2 queries por card.

**Avatar.** `resource.contact.avatar_url` cai em `Avatarable#avatar_url`
(`app/models/concerns/avatarable.rb:15-19`):

```ruby
def avatar_url
  return url_for(avatar.representation(resize_to_fill: [250, nil])) if avatar.attached? && avatar.representable?
  ''
end
```

`avatar.attached?` carrega o `ActiveStorage::Attachment`, `representable?` carrega o `Blob`, e
`url_for(representation)` pode ainda gerar/consultar o registro de variante. Sem eager load
são 2-3 queries por card, e a conta pode incluir `INSERT`.

Os três scopes do `PipelineItemsController` incluem as associações "óbvias" e nenhuma das duas
acima:

```ruby
.includes(:contact, :conversation, :assignee, :team, :pipeline_lost_reason, pipeline_stage: :pipeline)
# flat_pipeline_items_scope:99, fetch_item:111, pipeline_items_scope:118
```

O projeto já resolve os dois no caminho das conversas —
`app/finders/conversation_finder.rb:202`:

```ruby
@conversations.includes(
  :taggings, :inbox, { assignee: { avatar_attachment: [:blob] } }, { contact: { avatar_attachment: [:blob] } }, :team, :contact_inbox
)
```

e em `app/controllers/api/v1/accounts/contacts_controller.rb:135`
(`includes_hash = { avatar_attachment: [:blob] }`). Os pipelines nunca receberam esse
tratamento.

## O que corrigir

Acrescentar o eager load das duas cadeias aos três scopes do `PipelineItemsController`
(`flat_pipeline_items_scope:95-104`, `fetch_item:106-113`, `pipeline_items_scope:115-120`).

Para o avatar, copiar o padrão existente: `contact: { avatar_attachment: :blob }` — cuidado
para não perder o `:contact` simples que já está lá (vira a forma com hash).

Para as labels, **não copiar às cegas** o `:taggings` de `conversation_finder.rb:202`:
`label_list` ainda precisa da `tag` de cada tagging, então `includes(:taggings)` sozinho pode
deixar um N+1 residual em `tags`. Testar com o log de query qual forma realmente zera
(`:labels`, que o `acts_as_taggable_on` define, ou `{ taggings: :tag }`) e usar essa. Se ficar
comprovado que o caminho das conversas tem o mesmo N+1 residual, **não** corrigir aqui — anotar
como achado separado, é outro domínio e outro escopo.

Nota: `resource.assignee` e `resource.team` são renderizados pelos partials
`api/v1/models/agent` e `api/v1/models/team` (linhas 22 e 27). Conferir no log de query se
esses partials também tocam avatar (`thumbnail`) — se tocarem, o `assignee:
{ avatar_attachment: [:blob] }` do `conversation_finder` se aplica igual e entra nesta mesma
task.

## Testes

Docker local, com alguns milhares de cards semeados e cards que tenham label **e** contato com
avatar anexado (um card sem nenhum dos dois não reproduz):

1. Log de query ligado, abrir o board e contar as queries de
   `GET /pipelines/:id/pipeline_items`. Critério: número de queries **constante**, não
   proporcional ao número de cards. Medir antes e depois, e registrar os dois números.
2. Conferir que as etiquetas continuam aparecendo no card (`KanbanCard.vue:137-145`) e que o
   avatar do contato continua carregando (`KanbanCard.vue:99-104`).
3. Testar também os dois caminhos que **não** são o board e usam os mesmos scopes: painel de
   Oportunidades na conversa (`ConversationOpportunities.vue`) e no contato
   (`ContactOpportunities.vue`), e o `show` de um card (`KanbanCardDetail.vue`).

## Critério de pronto

- Número de queries de `GET /pipelines/:id/pipeline_items` constante em relação ao número de
  cards, comprovado por log de query (não por inspeção do código).
- Etiquetas e avatar continuam idênticos na resposta JSON e na tela.
- Os três scopes tratados, não só o do board — senão o painel de Oportunidades fica com o N+1.
- Nenhuma extensão correspondente em `enterprise/` (confirmar com a skill
  `sincronizar-enterprise`).
- `bundle exec rubocop -a` limpo (atenção ao `Layout/LineLength Max: 150` — os `includes`
  ficam longos).
