# Task 30 — Fix: `inject` sem valor default em `KanbanCard.vue`

Severidade: 🟢 Baixa. Achado na revisão de 2026-09-18 (auditoria da implementação das tasks 14-23).

## Objetivo

A [task 09](09-atributos-customizados-fora-do-card.md) foi resolvida com `provide`/`inject`, que
é o padrão certo e já usado no projeto (`ConversationList.vue` faz o mesmo com
`contextMenuElementTarget`/`toggleContextMenu`). Só que o `inject` do lado do card não tem
default:

`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCard.vue`:

```js
const visibleCardAttributeDefinitions = inject(
  'kanbanCardAttributeDefinitions'
);
// ...
const visibleAttributes = computed(() =>
  visibleCardAttributeDefinitions.value
    .map(attr => ({ ... }))
```

Se a injeção não for encontrada, `inject` devolve `undefined`, o Vue emite um warning e
`visibleCardAttributeDefinitions.value` estoura com `TypeError: Cannot read properties of
undefined`. Como o acesso está dentro de um `computed` usado no template, o erro derruba a
renderização do card.

**Hoje não acontece**: `KanbanCard` só é instanciado por `KanbanColumn`, que só é instanciado por
`KanbanBoard`, que é quem faz o `provide` (confirmado por busca no projeto — não há nenhum outro
uso de `KanbanCard`). O problema é latente: o card é um componente de apresentação óbvio para
reusar num modal, num painel lateral, num preview de macro, e quem fizer isso vai receber um erro
de runtime cuja causa não está no arquivo que ele está editando.

## O que corrigir

Dar um default vazio ao `inject`, de forma que o card degrade para "sem atributos customizados"
em vez de quebrar:

```js
const visibleCardAttributeDefinitions = inject(
  'kanbanCardAttributeDefinitions',
  computed(() => [])
);
```

O default precisa ser um ref/computed (não um array puro), porque o consumidor faz `.value`.
Conferir se `computed` já está importado no arquivo — está (`import { computed, inject } from 'vue'`).

Vale também um comentário curto de uma linha dizendo que o valor normalmente vem de
`KanbanBoard.vue` e que o default existe só para uso fora do board — senão o próximo leitor
pode achar que o board às vezes não provê e ir procurar o caso.

## Testes

1. Board normal: os atributos customizados marcados como `display_on_card` continuam aparecendo
   nos cards, iguais a antes (é o comportamento que a task 09 entregou, não pode regredir).
2. Card sem nenhum atributo preenchido continua sem a seção.
3. Montar um `KanbanCard` fora do board (um spec Vitest com `shallowMount`, ou temporariamente em
   qualquer tela, só para validar): renderiza sem erro e sem a seção de atributos, em vez de
   estourar.
4. Console do navegador sem warning de injeção não encontrada no uso normal.

## Critério de pronto

- `KanbanCard` renderiza fora do `KanbanBoard` sem erro de runtime.
- Comportamento dentro do board inalterado.
- `pnpm eslint` limpo.

## Resultado (2026-09-20)

`KanbanCard.vue`: o `inject` agora tem default, no formato de **factory** (`inject(key, () =>
computed(() => []), true)`) em vez do `computed(() => [])` direto que a task sugeria. Diferença: com
o valor direto, o `computed` seria criado em toda instância de card mesmo com o `provide` presente
(o board tem centenas); com a factory ele só é construído quando nada foi provido. O comentário
acima do `inject` diz que o valor normal vem do `KanbanBoard.vue` e que o default é só para uso fora
do board.

Validação:
- **Fora do board (item 3):** spec Vitest temporário (apagado depois) montando `KanbanCard` sem
  `provide`. Sem o default: `TypeError: Cannot read properties of undefined (reading 'value')`
  (reproduzido revertendo a mudança por um instante). Com o default: renderiza, sem seção de
  atributos.
- **Com `provide`:** o mesmo spec, com dois atributos definidos: mostra o atributo preenchido com o
  label, e omite o vazio (filtro do `visibleAttributes` intacto).
- **Board real (itens 1 e 2):** dois cards semeados no pipeline 2309 - o com `custom_attributes`
  mostra "Instagram: @teste30" e "Faturamento Mensal: 5000"; o sem atributos não tem a seção.
  Cards removidos depois.
- **Console (item 4):** `read_console_messages` não devolveu nada, mas só captura o que acontece
  depois de ligado, então **não** prova ausência de warning no carregamento. O que sustenta o item
  é que o board provê a chave em `KanbanBoard.vue:24` e o card só existe dentro dele.
- `pnpm eslint`: 0 erros. `pnpm vitest` (kanban): 23/23. Nenhum spec novo ficou no repositório.

Observação de ambiente: nesta sessão o Rails levou ~35s para responder a primeira requisição
depois da noite parada (Docker Desktop), e o painel do navegador travou/escondeu duas vezes; nada
disso tem relação com a mudança.
