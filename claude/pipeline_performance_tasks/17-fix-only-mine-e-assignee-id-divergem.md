# Task 17 — Fix: `only_mine` + `assignee_id` divergem entre servidor e cliente

Severidade: 🟠 Alta. Achado na revisão de 2026-09-16 (auditoria da implementação das tasks 01-07).

## Objetivo

O servidor trata "somente meus" como **exclusivo** (early return, ignora o filtro de
responsável), e o cliente trata como **cumulativo** (aplica os dois em AND).

`app/finders/pipeline_item_finder.rb:51-58`:

```ruby
# showOnlyMine wins over an explicit assignee_id, same precedence as the client (getters.js:70-77).
def filter_by_assignee(items)
  return items.where(pipeline_items: { assignee_id: current_user.id }) if ActiveModel::Type::Boolean.new.cast(params[:only_mine])
  return items if params[:assignee_id].blank?
  return items.where(pipeline_items: { assignee_id: nil }) if params[:assignee_id] == 'unassigned'

  items.where(pipeline_items: { assignee_id: params[:assignee_id] })
end
```

O comentário da linha 51 afirma que essa é a mesma precedência do cliente. **Não é.** O cliente
aplica os dois filtros em sequência, sem early return —
`app/javascript/dashboard/store/modules/kanban/getters.js:31-45`:

```js
if ($state.showOnlyMine && currentUserId && item.assignee?.id !== currentUserId) {
  return false;
}
if (assigneeId === 'unassigned' && item.assignee) return false;
if (assigneeId && assigneeId !== 'unassigned' && item.assignee?.id !== assigneeId) {
  return false;
}
```

E a versão anterior (pré-task 03, no `getFilteredSortedItemsForStage` original) fazia o mesmo:
dois `.filter()` encadeados.

**É alcançável pela UI.** `KanbanFilterBar.vue` não desabilita o `<select>` de responsável
quando "Somente meus" está marcado — são dois controles independentes (`:checked="showOnlyMine"`
na linha 119, `@change="onAssigneeChange"` na linha 151). Marcar "Somente meus" **e** escolher
outro agente produz:

- comportamento antigo / `itemMatchesActiveFilters`: nenhum card (interseção vazia);
- servidor hoje: os cards do usuário logado.

Além da divergência com o comportamento que estava em produção, o servidor e o
`itemMatchesActiveFilters` **discordam entre si dentro da mesma sessão**: um card que chega por
ActionCable é avaliado pelo predicado do cliente (AND), enquanto a lista veio do servidor
(exclusivo). Isso significa card entrando e saindo da coluna de forma inconsistente com o que a
listagem trouxe.

## O que corrigir

1. Decidir a semântica — é decisão de produto, não só de código:
   - **AND (recomendado)**: alinha o servidor ao comportamento que já está em produção e ao
     predicado do cliente. "Somente meus" + outro agente = nenhum card, que é literalmente o que
     os dois filtros pedem. Fix: tirar o early return e encadear as duas condições.
   - **Exclusivo**: mantém o servidor como está, alinha o cliente, e aí a UI **precisa** deixar
     isso óbvio — desabilitar o select de responsável enquanto "Somente meus" estiver marcado,
     senão o agente vê um filtro selecionado que não tem efeito.
2. Aplicar a decisão nos **três** lugares que precisam concordar: `PipelineItemFinder#filter_by_assignee`,
   `itemMatchesActiveFilters` (`getters.js:31-45`) e a UI do `KanbanFilterBar`.
3. Corrigir o comentário da linha 51 do finder — hoje ele documenta um fato falso, o que é pior
   que não ter comentário.
4. Aproveitar e conferir o mesmo tipo de divergência no resto do finder enquanto estiver ali: os
   outros filtros foram conferidos nesta auditoria e batem, exceto o de valor (task 20).

## Testes

Com pelo menos 2 agentes com cards na mesma coluna:

1. Só "Somente meus" → cards do usuário logado. (Já funciona; é a baseline.)
2. Só responsável = outro agente → cards daquele agente.
3. **"Somente meus" + responsável = outro agente** → o resultado tem que ser o mesmo nos dois
   caminhos: o que o servidor devolve na listagem e o que `itemMatchesActiveFilters` decide para
   um push de ActionCable. Testar os dois: carregar a coluna, e depois mexer num card em outra
   sessão e ver se ele entra/sai da coluna de forma coerente com a lista.
4. "Somente meus" + responsável = `unassigned` → mesmo cuidado.
5. Se a decisão for "exclusivo": confirmar que o select fica visivelmente desabilitado.
6. Conferir que o badge da coluna (`meta.count`) bate com o número de cards efetivamente
   listados em cada combinação.

## Critério de pronto

- Servidor, `itemMatchesActiveFilters` e UI concordam sobre o que a combinação significa.
- Comentário do finder descreve o comportamento real.
- Decisão de produto (AND ou exclusivo) registrada neste arquivo.
- `bundle exec rubocop -a` e `pnpm eslint` limpos.

## Decisão e resultado (2026-09-17)

**AND**, a opção recomendada pelo próprio documento — alinha o servidor ao que já estava em
produção (`itemMatchesActiveFilters`) e evita reescrever a UI.

Só o finder precisou mudar: `itemMatchesActiveFilters` (`getters.js:22-56`) já encadeava as
duas condições sem early return, e `KanbanFilterBar.vue` já mantém os dois controles
independentes (nunca desabilitou o select de responsável) — ambos já implementavam AND. O bug
estava isolado em `PipelineItemFinder#filter_by_assignee`, que tinha o único early return
exclusivo dos três lugares.

Verificado no Docker local com 2 agentes (John, admin; teste, agente) e 5 cards (2 de cada +
1 sem responsável), rodando `PipelineItemFinder` direto:

| Combinação | Resultado | `meta_count` |
|---|---|---|
| `only_mine=true` | 2 cards do John | 2 |
| `assignee_id=teste` | 2 cards do teste | 2 |
| `only_mine=true` + `assignee_id=teste` | **vazio** (AND, contraditório) | 0 |
| `only_mine=true` + `assignee_id=unassigned` | **vazio** (AND, contraditório) | 0 |
| `only_mine=true` + `assignee_id=john` (mesma pessoa) | 2 cards do John | 2 |

`meta_count` (o que vira o badge da coluna) bateu com a listagem em todos os casos.
