# Task 31 — Registrar o resultado das tasks 14, 15 e 16

Severidade: 🟢 Baixa. Achado na revisão de 2026-09-18 (auditoria da implementação das tasks 14-23).
Não é uma task de código.

## Objetivo

Das 10 tasks da leva 14-23, sete registraram uma seção `## Resultado` (ou
`## Decisão e resultado`) ao serem implementadas — o que foi feito, o que foi medido, e a
decisão tomada quando havia uma. As tasks **14, 15 e 16** são as únicas sem.

As três foram implementadas e verificadas na auditoria de 2026-09-18, mas a informação está só
no código e nesta conversa. Isso importa porque:

- a pasta `*_tasks/` é o registro de processo do projeto, e é o que a próxima sessão lê para
  entender por que uma coisa está do jeito que está;
- as três estavam marcadas como **⚠️ exige decisão de produto** no índice, e pelo menos a 16
  tomou uma decisão real que não está documentada em lugar nenhum;
- a 15 oferecia dois caminhos mutuamente exclusivos e o próprio arquivo pede: *"Escolher uma e
  anotar aqui qual foi — não fazer as duas."*

## O que registrar

**Task 14 — desempate na ordenação.** `apply_sort` (`app/finders/pipeline_item_finder.rb`) passou
a acrescentar `pipeline_items.id` como último critério nos dois ramos (coluna simples e
`assignee`), na mesma direção do critério principal. Verificado: `ORDER BY pipeline_items.position
asc, pipeline_items.id asc`, e com `PIPELINE_ITEMS_RESULTS_PER_PAGE=1` numa stage com positions
empatadas as páginas voltaram disjuntas e completas nos 4 modos de ordenação (`position`,
`created_at`, `value`, `assignee`). A "Observação relacionada" do arquivo (nada atribui `position`
na criação) continua valendo e virou a [task 24](24-fix-reorder-posicoes-cards-nao-carregados.md).

**Task 15 — arrastar voltava pro lugar.** Registrar que foi escolhida a **saída 1** (executar a
task 08 em vez do paliativo): `getFilteredSortedItemsForStage` e `compareByField` foram removidos
de `getters.js`, e `KanbanColumn.vue` passou a consumir `getItemsForStage` direto. `REORDER_ITEMS`
**não** foi alterado — não precisou, já que não há mais re-sort no cliente para desfazer o
arrasto. Vale anotar o link para a [task 08](08-desmontar-getter-global.md) como "feita junto".

**Task 16 — opção de ordem manual.** Registrar as três decisões:
1. `position` entrou como **primeira** opção de `sortMenus` (`KANBAN.SORT.OPTIONS.MANUAL`,
   traduzida em `en` e `pt_BR`);
2. o seletor de direção asc/desc é **escondido** quando a ordem manual está ativa
   (`v-if="!isManualOrder"`), e `handleSortChange` força `asc` ao entrar em `position` — ou seja,
   "manual descendente" foi descartado como estado alcançável;
3. **a preferência antiga não foi migrada** — `DEFAULT_KANBAN_BOARD_SETTINGS.sort` em
   `useUISettings.js` mudou de `{ created_at, desc }` para `{ position, asc }`, o que só afeta
   pipelines sem preferência salva. Quem já tinha `created_at/desc` gravado continua com ele e
   volta para a ordem manual pelo menu quando quiser. Essa era exatamente a pergunta em aberto
   do item 4 do "O que corrigir" da task 16, e a escolha foi a recomendada (não descartar uma
   escolha que pode ter sido deliberada).

Conferir cada afirmação acima contra o código antes de escrever — este arquivo é um registro, e
registro errado é pior que registro ausente.

## Critério de pronto

- As três tasks com seção `## Resultado` no mesmo formato das outras sete da pasta.
- Decisão de produto da 16 explícita, não implícita no código.
- Caminho escolhido na 15 explícito, com link para a task 08.
- Nenhum arquivo de código alterado por esta task.

## Resultado (2026-09-21)

Seções `## Resultado` acrescentadas em [14](14-fix-ordenacao-sem-desempate.md),
[15](15-fix-arrastar-reordenar-volta-pro-lugar.md) e
[16](16-fix-opcao-ordem-manual-no-menu.md), cada uma conferida contra o código antes de escrever
(nenhum arquivo de código alterado por esta task).

Onde o texto desta task **não bateu** com o que encontrei, e o que foi registrado no lugar:
- **Task 16 não estava "sem registro"**: já tinha o bloco "Decisões registradas (2026-09-16)" com
  as decisões dos itens 2 e 4 e o achado do fallback. O que faltava era a seção `## Resultado`;
  ela referencia o bloco existente em vez de duplicá-lo, e acrescenta os itens 1 e 3.
- **Task 15, "`REORDER_ITEMS` não foi alterado"**: impreciso. Ele não foi alterado *pela 15*, mas
  a versão atual vem da reestruturação por stage da task 05 (no HEAD gravava em `itemOrder`).
  Registrado assim.
- **Task 14, "4 modos de ordenação"**: são 5 (`position`, `created_at`, `updated_at`, `value`,
  `assignee`). Reverifiquei os 5 nas duas direções no finder real, em vez de reaproveitar a
  medição da auditoria: 10/10 combinações com páginas disjuntas e completas.

Achado à parte (não corrigido, esta task não altera código): comentários obsoletos em
`app/finders/pipeline_item_finder.rb` (cabeçalho e ramo `assignee`) citam
`getFilteredSortedItemsForStage`/`getters.js`, que foram removidos - anotado na task 15.

Com esta, as tasks 24-31 da segunda leva ficam todas com resultado registrado.
