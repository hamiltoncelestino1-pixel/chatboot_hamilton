# Task: Sistema de Lembretes — Religar o Sino de Notificações (Opcional)

## Objetivo

Dar mais destaque visual a uma notificação de lembrete vencido do que o indicador atual (só um
número discreto no item "Inbox" da sidebar).

**Esta task é opcional e isolada de propósito**: mexe numa peça de UX visível a **toda** a base de
usuários do dashboard (não só quem usa lembretes), então merece revisão própria em vez de ir junto
de uma PR de feature nova.

---

## Contexto (achado da pesquisa)

Existe um componente `app/javascript/dashboard/components-next/sidebar/SidebarNotificationBell.vue`
já pronto e funcional — mostra um ícone de sino com badge de contagem (`bg-n-ruby-9`, cap em "99+"),
alimentado pelo getter `notifications/getUnreadCount`, e emite um evento `openNotificationPanel` ao
ser clicado.

Confirmado por leitura direta e grep: **esse componente não está importado/renderizado em nenhum
lugar da árvore atual** (`Sidebar.vue` não o referencia). O único indicador de notificação não lida
hoje é um número no item "Inbox" da sidebar principal (`Sidebar.vue`, `menuItem` com
`getterKeys: { count: 'notifications/getUnreadCount' }`, renderizado por
`SidebarGroupHeader.vue`). Não há sinal de que a remoção do sino foi deliberada — parece órfão de
um refactor anterior (bate com `Sidebar.vue` aparecer modificado no git status do início deste
projeto).

---

## 1. Investigação prévia (fazer antes de escrever qualquer código)

Buscar `openNotificationPanel` em toda a árvore de `app/javascript/dashboard/` — é possível que já
exista um painel/dropdown consumidor parcialmente implementado que só não está conectado a nenhum
botão. Se existir, reaproveitar; se não existir, esse é o escopo desta task (seção 2).

---

## 2. Religar o componente

Em `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`, localizar a área de
topo/rodapé onde outros elementos fixos vivem (perto de `SidebarProfileMenu`/`SidebarAccountSwitcher`
— confirmar nomes exatos lendo o arquivo) e importar/renderizar `SidebarNotificationBell`:

```javascript
import SidebarNotificationBell from './SidebarNotificationBell.vue';
```

```html
<SidebarNotificationBell @open-notification-panel="handleOpenNotificationPanel" />
```

Se não existir nenhum painel consumidor pronto (confirmado na investigação da seção 1), a opção
mais simples e de menor risco é fazer `handleOpenNotificationPanel` navegar direto pra rota
`notifications_index` já existente (`router.push({ name: 'notifications_index' })`), em vez de
construir um dropdown novo — mantém o padrão "página dedicada" que já existe e evita duplicar UI de
listagem de notificações.

---

## 3. Reforço específico pra lembretes (opcional dentro do opcional)

Se quiser diferenciar visualmente um lembrete vencido (`notification_type: 'reminder_due'`) de
outras notificações no badge/sino — por exemplo, uma cor diferente quando há pelo menos uma
notificação de lembrete não lida — adicionar um getter novo em `store/modules/notifications/getters.js`:

```javascript
getHasUnreadReminders: state =>
  Object.values(state.records).some(n => n.notification_type === 'reminder_due' && !n.read_at),
```

E usar esse getter no `SidebarNotificationBell.vue` pra trocar a cor do badge condicionalmente. Não
implementar isso a menos que o produto peça explicitamente — é puramente estético.

---

## Verificação

1. O sino aparece na sidebar em todas as telas do dashboard.
2. O número do badge bate com `notifications/getUnreadCount` (mesmo valor que já aparecia no item
   "Inbox").
3. Clicar no sino navega pra `/accounts/:id/notifications` (ou abre o painel, se um já existir).
4. Confirmar que essa mudança não duplicou a contagem em nenhum lugar (o item "Inbox" da sidebar
   continua mostrando o badge dele normalmente, sem conflito).
5. Gerar uma notificação de lembrete vencido (via task 17) e confirmar que o contador do sino sobe
   em tempo real, sem precisar recarregar a página.
