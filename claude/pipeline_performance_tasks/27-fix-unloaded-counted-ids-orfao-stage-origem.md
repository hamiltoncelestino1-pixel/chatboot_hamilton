# Task 27 — Fix: `unloadedCountedIds` fica órfão na stage de origem

Severidade: 🟢 Baixa. Achado na revisão de 2026-09-18 (auditoria da implementação das tasks 14-23).

## Objetivo

A [task 18](18-fix-contador-coluna-dessincroniza-tempo-real.md) foi bem resolvida — o
bookkeeping idempotente por id (`unloadedCountedIds` + `SET_UNLOADED_ITEM_COUNTED`) mata tanto a
inflação por update repetido quanto a corrida POST/WS. Esta task é sobre o gap que ela deixou
documentado, que **agora ficou barato de fechar**.

`app/javascript/dashboard/store/modules/kanban/actions.js`, no comentário de
`applyRealtimePipelineItem`:

> Known, accepted gap: if this is actually an update that moved an unloaded item OUT of another
> stage, that source stage's count isn't decremented - the event payload
> (`PipelineItem#push_event_data`) doesn't carry the previous stage id, only the current one, so
> there's nothing to diff against.

A justificativa era válida **antes** da task 18. Agora não é mais: `unloadedCountedIds` é
exatamente o diff que faltava. O handler sabe, para cada stage carregada, quais ids não
carregados ela está contando — se o id chega num evento apontando para outra stage, a origem
pode ser deduzida localmente.

Sequência do problema hoje:

1. Card X está na página 3 da stage A. Um update chega → `!existingItem` →
   `SET_UNLOADED_ITEM_COUNTED { stageId: A, itemId: X, counted: true }` → `A.count + 1`,
   `X ∈ A.unloadedCountedIds`.
2. Outro update move X para a stage B → `SET_UNLOADED_ITEM_COUNTED { stageId: B, ... }` →
   `B.count + 1`, `X ∈ B.unloadedCountedIds`.
3. **A continua com `count` inflado e com X em `unloadedCountedIds`.**

Consequências: badge da stage A alto até o próximo fetch de página 1, e `hasMore`
(`ids.length < count`) pode ficar `true` indevidamente, provocando um request de página vazia. Se
X voltar para A depois, ele não é recontado (já está na lista), o que pelo menos mantém a coisa
auto-consistente em vez de somar duas vezes.

Impacto baixo: o valor se corrige sozinho em qualquer refetch de página 1 (troca de pipeline,
mudança de filtro/ordenação, reload). Vale corrigir pelo custo baixo e porque o comentário
atualmente descreve uma limitação que não existe mais.

## O que corrigir

1. Em `applyRealtimePipelineItem`, no ramo `!existingItem`: antes de contabilizar na stage de
   destino, limpar o id de qualquer **outra** stage que o tenha em `unloadedCountedIds`
   (decrementando o `count` dela). Uma mutation nova, ou um parâmetro a mais em
   `SET_UNLOADED_ITEM_COUNTED` — o importante é ser uma única operação sobre o estado, não um
   loop de commits no action.
2. Conferir o caso simétrico: `DELETE_ITEM` e `REMOVE_STAGE_ITEM` também não limpam
   `unloadedCountedIds` hoje. Para `DELETE_ITEM` o card normalmente está carregado (só o próprio
   agente apaga, e a partir do board), então é teórico — mas se o mesmo helper de limpeza puder ser
   reusado ali, é de graça.
3. **Atualizar o comentário** de `applyRealtimePipelineItem` para refletir o que passou a ser
   tratado e o que continua sendo gap aceito (se sobrar algum). O comentário atual é bom e
   detalhado — mantê-lo verdadeiro é parte da task.

## Testes

Duas sessões no mesmo board (A e B), coluna com mais de uma página:

1. Em B, mover um card que em A está numa página ainda **não carregada**, de uma stage para
   outra. Em A: o badge da stage de origem **não** pode subir nem ficar inflado, e o da stage de
   destino sobe 1.
2. Repetir o movimento várias vezes (ida e volta entre duas stages) e conferir que os dois badges
   sempre batem com o banco.
3. Comparar com o total real no banco depois de cada passo — o teste é o número, não a impressão.
4. Rodar uma macro em lote que mova muitos cards não carregados e conferir que nenhum badge
   derivou.
5. Trocar de pipeline e voltar: os badges já estavam certos antes do refetch (prova que não era só
   o auto-heal do `meta.count` mascarando).
6. `pnpm test` — specs do módulo kanban passando.

## Critério de pronto

- Um card não carregado que muda de stage não deixa contagem órfã na origem.
- Nenhum badge deriva após uma sequência de movimentações em lote.
- Comentário de `applyRealtimePipelineItem` atualizado e verdadeiro.
- `pnpm eslint` limpo.

## Resultado (2026-09-19)

**A premissa da task só cobria metade do problema.** "`unloadedCountedIds` é exatamente o diff que
faltava" vale para um card que já teve um push contado na origem. No caso real - o **primeiro** push
que o board vê para um card é a própria mudança de stage - a origem nunca rastreou o id, então só
limpar `unloadedCountedIds` não muda nada. Medi antes de corrigir: com 52 cards em A (25 carregados),
mover um card não carregado de A para B pelo backend deixou A em 52 com o banco em 51.

O que foi feito:
- `mutations.js`: helper `releaseUnloadedCount`, chamado por `SET_UNLOADED_ITEM_COUNTED` (uma única
  operação sobre o estado, sem loop de commits no action) e por `DELETE_ITEM` (item 2 da task).
  Devolve o +1 de toda stage que ainda rastreia o id, e - quando o push informa - também da stage
  anterior, mesmo sem rastreio (a `count` dela veio do `meta.count` do servidor e inclui o card).
- **Backend, fora do que a task previa:** `ActionCableListener#pipeline_item_updated` agora envia
  `previous_pipeline_stage_id` no payload, tirado do `changed_attributes` que o evento
  `PIPELINE_ITEM_UPDATED` já carregava (é o único dispatcher desse evento). Sem mudar o model.
- `actions.js`: repassa `item.previous_pipeline_stage_id` como `previousStageId`, **só com a coluna
  sem filtro**. Com filtro ativo, se o card contava na stage anterior depende de como ele casava
  *antes* da mudança, e o payload não diz - então só o caminho rastreado se aplica. Comentário de
  `applyRealtimePipelineItem` reescrito com o que passou a ser tratado e os gaps que sobram.
- Specs existentes ajustadas ao payload novo (`action_cable_listener_spec.rb`, `actions.spec.js`);
  nenhum spec novo (regra do AGENTS.md).

Validação com dois lados de verdade (board aberto + `rails runner` movendo cards, push real do
ActionCable), comparando o badge com o banco a cada passo, **sem refetch**:
- A→B de um card não carregado: A 52→51, B 0→1 (banco: 51/1). Antes: A ficava 52.
- Ida e volta A→B→A→B→A: termina A=52, B=0, igual ao banco.
- Lote de 10 cards não carregados A→B, depois 5 deles B→coluna 7823: A=42, B=5, 7823=5 (banco: 42/5/5).
- Com "exibir apenas minhas" ligado, mover um card sem responsável: nenhum badge muda (correto - o
  card nem entrava na contagem filtrada).
- Mover para stage de perda sem motivo falha no backend (validação existente), não é regressão.
Dados de teste (52 cards no pipeline 2309, que estava vazio) removidos.

`pnpm eslint`: 0 erros. `pnpm vitest` (kanban): 23/23. `rspec` do listener: 14/14. Rubocop limpo
nos 2 arquivos Ruby (LF preservado).

**Gaps que sobram (aceitos, curam no próximo fetch da página 1):** (a) com filtro ativo, card
não rastreado que sai de uma stage deixa a origem alta; (b) `pipeline_item.created` de um card que
já saiu da stage antes de o cliente ver não traz stage anterior. Além disso, um push de *update*
puro (sem mudar de stage) para um card não carregado ainda soma +1 na própria stage, o que já era
o comportamento da task 18 e não foi alterado aqui.
