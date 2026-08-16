# Task 09 — Padronizar: moeda `pt-BR`/`BRL` hardcoded no card do Kanban

Severidade: 🟢 Baixa. Achado na auditoria de otimização de CRM (2026-08-16).

## Objetivo

`app/javascript/dashboard/routes/dashboard/kanban/components/KanbanCard.vue:23-30`:

```js
const formattedValue = computed(() => {
  if (!props.item.value || Number(props.item.value) === 0) return null;
  return new Intl.NumberFormat('pt-BR', {
    style: 'currency',
    currency: 'BRL',
  }).format(props.item.value);
});
```

Locale e moeda fixos em `pt-BR`/`BRL`, sem respeitar o locale ativo do usuário
(`currentLocale`) nem uma eventual configuração de moeda por conta. Baixo risco hoje (o
produto é um white-label focado no Brasil), mas é um literal espalhado num componente em vez
de centralizado — mais difícil de mudar depois se surgir necessidade de outro locale/moeda.

## O que corrigir

Extrair a formatação para um helper compartilhado (ex. `app/javascript/dashboard/helper/`),
reutilizável por outros componentes que também formatam valores monetários. Se já existir um
helper de formatação de número/moeda em algum lugar do dashboard (procurar antes de criar um
novo — ex. `helper/numberHelper.js` ou equivalente), estender esse; senão criar um pequeno e
simples, aceitando `locale`/`currency` como parâmetros com fallback pro comportamento atual
(`pt-BR`/`BRL`), para não mudar nenhum comportamento visível agora — só preparar o terreno.

Não é necessário (nem pedido) implementar seleção de moeda por conta nesta task — é só
centralizar o literal para reduzir a inconsistência de padrão. Se o usuário quiser
configuração de moeda de verdade, isso vira uma feature nova, não faz parte desta limpeza.

## Testes

Testar manualmente: card do Kanban com valor numérico continua exibindo o valor formatado em
R$ exatamente como antes.

## Critério de pronto

- Formatação de moeda centralizada num helper, não mais um literal dentro do componente.
- Comportamento visual idêntico ao anterior (mesmo formato R$ 1.234,56).
- `pnpm eslint:fix` limpo nos arquivos tocados.
