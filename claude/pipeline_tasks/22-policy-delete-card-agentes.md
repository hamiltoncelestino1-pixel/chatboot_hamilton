# Task 22 — Policy: liberar delete de card para agentes membros do pipeline

Parte do Grupo E ([visão geral](00-visao-geral.md)). Sem dependências — isolada.

## Objetivo

Hoje só administrador pode deletar um card de pipeline. Passa a valer também para qualquer
agente que seja **membro do pipeline** daquele card (mesmo critério já usado para leitura em
`PipelinePolicy#show?`), sem exigir que o agente seja o assignee daquele card específico.

## Contexto (por que a trava está só aqui)

`app/policies/pipeline_item_policy.rb:24-26`:
```ruby
def destroy?
  @account_user.administrator?
end
```
É o único lugar da restrição — `PipelineItemsController#destroy` (linha 43-46) não faz
checagem própria além do `before_action :check_authorization` genérico
(`app/controllers/api/base_controller.rb:14-18`, que chama `authorize(PipelineItem)`). O
frontend (`KanbanCardDetail.vue:573-580`) já renderiza o botão de deletar para qualquer agente,
sem guard de role — hoje um agente não-admin vê o botão, clica, e só é bloqueado pelo 401 que
vem do backend. Não precisa de nenhuma mudança de frontend nesta task.

## Mudança

```ruby
def destroy?
  @account_user.administrator? || Current.user.assigned_pipelines.include?(record.pipeline)
end
```

Reaproveita `User#assigned_pipelines` (`app/models/user.rb:142-144`) — já usado por
`PipelinePolicy#show?` (`app/policies/pipeline_policy.rb:12-14`) com a mesma semântica: admin
enxerga todos os pipelines da conta, agente só os pipelines onde é `pipeline_member`.
`record.pipeline` já existe via `delegate :pipeline, to: :pipeline_stage`
(`app/models/pipeline_item.rb:75`) — não precisa de query extra.

**Não mexer** em `PipelinePolicy#destroy?` (deletar o *pipeline inteiro*, não um card) — isso
continua restrito a administrador, não foi pedido.

## Enterprise

Conferir (skill `sincronizar-enterprise`) se existe `enterprise/app/policies/enterprise/pipeline_item_policy.rb`
ou equivalente antes de considerar a task concluída.

## Testes

`spec/policies/pipeline_item_policy_spec.rb` (estender se existir, criar se não) — `destroy?`
retorna `true` para admin, `true` para agente membro do pipeline do card, `false` para agente
não-membro.

## Critério de pronto

- Agente membro do pipeline consegue deletar card via API (`DELETE
  /api/v1/accounts/:id/pipeline_items/:item_id`) sem ser admin.
- Agente sem vínculo com o pipeline continua bloqueado (401).
- `bundle exec rubocop -a` limpo.
