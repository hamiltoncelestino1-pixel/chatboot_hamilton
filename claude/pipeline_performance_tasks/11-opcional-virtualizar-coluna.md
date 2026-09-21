# Task 11 — (Opcional) Virtualizar a lista de cards da coluna

Severidade: 🟢 Baixa. Achado na análise de performance de 2026-09-15.
Depende da task 08. **Só executar se ainda houver travamento depois de 01-10.**

**Status: não aplicada em 2026-09-16.** Tasks 01-10 implementadas e validadas. Não foi feita
porque o critério de pronto exige medir travamento real (nº de nós, tempo de frame) antes de
decidir, e a sessão que chegou até aqui não tinha acesso a profiler de CPU/DevTools de
performance para produzir esse número - só automação de browser sem esse instrumento. Sem a
medição, implementar viraria exatamente o que o documento pede pra evitar: trocar um problema
medido por um risco não medido (virtualização + `vuedraggable` é frágil). Se o travamento for
observado em produção com colunas de muitas páginas acumuladas, medir primeiro com Vue DevTools/
Performance do navegador antes de retomar esta task.

## Objetivo

`KanbanCard.vue` renderiza ~40 nós de DOM por card (avatar, `router-link`, etiquetas,
atributos customizados, badges, dois `v-tooltip`, datas), e `KanbanColumn.vue:98-117` monta
todos de uma vez.

Com a paginação da task 03 (25 por página) isso deixa de ser um problema no primeiro carregamento
— mas um agente que rola muito numa coluna grande acumula páginas, e aí o número de nós volta a
crescer sem teto.

O projeto já usa virtualização na lista de conversas: `Virtualizer` de `virtua/vue`
(`virtua ^0.48.6` no `package.json:100`), em `ConversationList.vue:69-81`:

```vue
<Virtualizer ref="virtualListRef" v-slot="{ item }" :data="conversationList" class="...">
  <ConversationItem :source="item" ... />
</Virtualizer>
```

## Por que é opcional e por último

**Virtualização + drag-and-drop é uma combinação notoriamente frágil.** A coluna usa
`vuedraggable` (`KanbanColumn.vue:98`) com `v-model="localItems"`, e o `vuedraggable` precisa
dos nós reais no DOM para calcular alvos de drop. Virtualizar significa que o alvo pode não
existir enquanto se arrasta — arrastar para uma posição fora da janela virtual, ou de uma
coluna para outra, é exatamente onde esse tipo de integração quebra.

O ganho de 01-10 é provavelmente suficiente:

- as tasks 01-03 tiram o gargalo de carregamento;
- a task 08 tira a re-renderização global (que é o que faz o DOM grande doer);
- a paginação limita o DOM inicial a 25 cards por coluna.

Fazer esta task preventivamente troca um problema medido por um risco não medido. **Medir
antes.**

## O que fazer (se for necessário)

1. **Medir primeiro**: com 01-10 aplicadas, rolar uma coluna até acumular várias páginas e
   perfilar no DevTools. Só seguir se houver travamento reproduzível, e registrar o número
   (tempo de frame, nº de nós) na task antes de mexer.
2. Antes de virtualizar, considerar alternativas mais baratas:
   - teto de páginas acumuladas por coluna (descartar as primeiras ao carregar as últimas);
   - `v-once`/`v-memo` no conteúdo estático do card;
   - reduzir nós do `KanbanCard` (os dois `v-tooltip` e o bloco de datas são candidatos).
3. Se virtualizar mesmo assim: envolver a lista com `Virtualizer`, e resolver a integração com
   `vuedraggable` — ou trocar a estratégia de drag (`sortablejs` direto sobre o container
   virtualizado), ou desligar a virtualização enquanto um arrasto está ativo.

## Testes

Se implementada, o roteiro de arrasto é o crítico e tem que ser exaustivo:

1. Arrastar dentro da coluna, para uma posição visível e para uma fora da janela virtual.
2. Arrastar de uma coluna para outra, e para uma coluna que precisa de scroll horizontal.
3. Arrastar para uma coluna vazia.
4. Arrastar durante o carregamento de uma página nova (soltar enquanto o spinner está ativo).
5. Reload depois de cada cenário, confirmando que a ordem persistida é a que ficou na tela.
6. Reordenar stages (o `draggable` externo de `KanbanBoard.vue:46-65`) com colunas
   virtualizadas.

## Critério de pronto

- Ganho medido e registrado (antes/depois), não presumido.
- Todos os 6 cenários de arrasto acima funcionando.
- Se a integração com `vuedraggable` não fechar de forma limpa: **não entregar** — voltar para
  as alternativas do item 2 e documentar aqui por que a virtualização foi descartada.
