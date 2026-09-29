# Task 02 — Fix: `useLostReasonPrompt` — modal zumbi + Promise perdida por estado singleton

Severidade: 🔴 Crítico. Achado na análise técnica de 2026-08-20 (auditoria pós-`df0251e58`).

## Objetivo

`app/javascript/dashboard/composables/useLostReasonPrompt.js:9-30`:

```js
const isOpen = ref(false);
let resolvePrompt = null;

export function useLostReasonPrompt() {
  const promptForLostReason = () => {
    isOpen.value = true;
    return new Promise(resolve => {
      resolvePrompt = resolve;
    });
  };

  const confirmLostReason = reasonId => {
    isOpen.value = false;
    resolvePrompt?.(reasonId);
    resolvePrompt = null;
  };

  const cancelLostReason = () => {
    isOpen.value = false;
    resolvePrompt?.(null);
    resolvePrompt = null;
  };

  return { isOpen, promptForLostReason, confirmLostReason, cancelLostReason };
}
```

`isOpen` e `resolvePrompt` são variáveis de **escopo de módulo** (declaradas fora de
`useLostReasonPrompt()`), não presas ao ciclo de vida de `LostReasonModal.vue` (montado uma
vez em `KanbanIndex.vue`, existe só enquanto o usuário estiver na rota do Kanban). Dois efeitos
reais:

**1. Modal "zumbi"**: usuário arrasta um card pra um estágio `lost`, `kanban/moveItem`
(`store/modules/kanban/actions.js:153-172`) faz o commit otimista e chama
`await promptForLostReason()`, deixando `isOpen = true`. Antes de responder o modal, o usuário
navega pra "Conversas" pelo sidebar — isso desmonta `KanbanIndex.vue`/`LostReasonModal.vue`,
mas como o estado é de módulo, nada é resetado. A Promise dentro de `moveItem` fica suspensa
indefinidamente. Se o usuário volta depois pro Kanban, `LostReasonModal` remonta e, como
`isOpen` continua `true`, o modal **reaparece imediatamente**, referente a um card antigo, sem
nenhuma indicação de qual card é. Escolher um motivo agora resolve a Promise antiga e o
`moveItem` suspenso retoma com dados potencialmente obsoletos.

**2. Promise perdida em chamadas concorrentes**: se um segundo `moveItem` pra um estágio
`lost` for disparado antes do primeiro terminar (dois cards movidos rapidamente),
`promptForLostReason()` sobrescreve o único `resolvePrompt` de módulo — a Promise do primeiro
card fica órfã, nunca resolve nem rejeita. Esse card fica preso no estado "movido
otimisticamente, nunca persistido nem revertido" até reload manual da página.

Não há `onUnmounted` em `LostReasonModal.vue` nem guard de reentrância em
`useLostReasonPrompt.js` para nenhum dos dois casos.

## O que corrigir

Escopar corretamente o estado do prompt — duas abordagens possíveis, escolher a mais simples
que resolva os dois efeitos:

1. **Fila de prompts pendentes**: em vez de uma única `resolvePrompt`, manter uma fila (array)
   de `{ cardId, resolve }`; `promptForLostReason` enfileira e só abre o modal se não houver
   um já aberto; ao confirmar/cancelar, resolve o item da frente da fila e abre o próximo se
   houver. Resolve o efeito 2 sem perder nenhuma Promise.
2. **Reset no unmount**: adicionar `onUnmounted` em `LostReasonModal.vue` que, se `isOpen` for
   `true` no momento do unmount, chama `cancelLostReason()` (resolve com `null`, garantindo que
   o `moveItem` suspenso faça `rollback()` em vez de ficar preso pra sempre). Resolve o efeito 1
   sozinho, mas não o 2 caso dois `moveItem` concorrentes aconteçam antes de qualquer unmount.

Recomendado implementar os dois — fila (resolve a raiz do problema de estado compartilhado) +
reset no unmount (rede de segurança para navegação no meio do prompt). Antes de escrever do
zero, procurar se existe algum outro padrão de "confirmação assíncrona desacoplada de
componente" já usado no projeto para reaproveitar a forma.

## Testes

Testar manualmente no Docker local:
- Mover um card pra `lost`, navegar pra outra rota antes de responder o modal, voltar pro
  Kanban — modal não deve reabrir sozinho referente ao card antigo (ou, se reabrir, deve ser
  claramente reconciliado/cancelado, não travado).
- Mover dois cards pra `lost` em sequência rápida (antes de responder o primeiro modal) —
  ambos devem eventualmente resolver (confirmado ou cancelado), nenhum card deve ficar preso
  no estado otimista para sempre.

## Critério de pronto

- Nenhuma Promise de `moveItem` fica pendente indefinidamente em nenhum dos dois cenários
  acima.
- Modal não reaparece "zumbi" referente a um card de uma sessão de navegação anterior.
- `pnpm eslint:fix` limpo nos arquivos tocados.
