import { frontendURL } from 'dashboard/helper/URLHelper';

const KanbanIndex = () => import('./pages/KanbanIndex.vue');

export const routes = [
  {
    path: frontendURL('accounts/:accountId/kanban'),
    name: 'kanban_index',
    component: KanbanIndex,
    meta: {
      permissions: ['administrator', 'agent'],
    },
  },
];
