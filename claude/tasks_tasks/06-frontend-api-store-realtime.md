# Task 06 — Frontend: API client + store Vuex + handlers de tempo real

Parte do Grupo B ([visão geral](00-visao-geral.md)). Depende da [02](02-policy-controller-swagger.md)
e da [05](05-tempo-real-actioncable.md).

## Objetivo

Base de dados do frontend para tarefas — sem nenhuma UI ainda (tasks 07-10 consomem isso).

## 1. API client — `app/javascript/dashboard/api/tasks.js`

Mirror de `app/javascript/dashboard/api/pipelineItems.js` (filtros `getByContact`/
`getByConversation`) + a rota `complete`:

```js
/* global axios */
import ApiClient from './ApiClient';

class TasksAPI extends ApiClient {
  constructor() {
    super('tasks', { accountScoped: true });
  }

  getByContact(contactId) {
    return axios.get(this.url, { params: { contact_id: contactId } });
  }

  getByConversation(conversationId) {
    return axios.get(this.url, { params: { conversation_id: conversationId } });
  }

  getByPipelineItem(pipelineItemId) {
    return axios.get(this.url, { params: { pipeline_item_id: pipelineItemId } });
  }

  complete(taskId) {
    return axios.patch(`${this.url}/${taskId}/complete`);
  }
}

export default new TasksAPI();
```

## 2. Store Vuex — `app/javascript/dashboard/store/modules/tasks/`

Um único state compartilhado pelos 3 pontos de entrada (`items` indexado por id, igual ao
`kanban` module — `store/modules/kanban/getters.js:101-107` mostra o padrão de filtrar um state
único por FK, em vez de 3 states separados por contexto).

`index.js`:
```js
import * as types from '../../mutation-types';
import { actions } from './actions';
import { getters } from './getters';
import { mutations } from './mutations';

const state = { items: {}, uiFlags: { isFetching: false, isCreating: false } };

export default { namespaced: true, state, getters, actions, mutations };
```

`getters.js`:
```js
export const getters = {
  getUIFlags: $state => $state.uiFlags,
  getTasksForContact: $state => contactId =>
    Object.values($state.items).filter(t => t.contact_id === contactId),
  getTasksForConversation: $state => conversationId =>
    Object.values($state.items).filter(t => t.conversation_id === conversationId),
  getTasksForPipelineItem: $state => pipelineItemId =>
    Object.values($state.items).filter(t => t.pipeline_item_id === pipelineItemId),
};
```

`actions.js` — cada `fetchFor*` bate no endpoint filtrado e faz `SET_TASK_DATA` por item
(mesmo padrão de `kanban/fetchItemsForContact`, `store/modules/kanban/actions.js:210-220`):
```js
import TasksAPI from '../../../api/tasks';

export const actions = {
  fetchForContact: async ({ commit }, contactId) => {
    const { data } = await TasksAPI.getByContact(contactId);
    data.payload.forEach(task => commit('SET_TASK_DATA', task));
    return data.payload;
  },

  fetchForConversation: async ({ commit }, conversationId) => {
    const { data } = await TasksAPI.getByConversation(conversationId);
    data.payload.forEach(task => commit('SET_TASK_DATA', task));
    return data.payload;
  },

  fetchForPipelineItem: async ({ commit }, pipelineItemId) => {
    const { data } = await TasksAPI.getByPipelineItem(pipelineItemId);
    data.payload.forEach(task => commit('SET_TASK_DATA', task));
    return data.payload;
  },

  create: async ({ commit }, taskParams) => {
    const { data } = await TasksAPI.create(taskParams);
    commit('SET_TASK_DATA', data);
    return data;
  },

  update: async ({ commit }, { id, ...taskParams }) => {
    const { data } = await TasksAPI.update(id, taskParams);
    commit('SET_TASK_DATA', data);
    return data;
  },

  complete: async ({ commit }, id) => {
    const { data } = await TasksAPI.complete(id);
    commit('SET_TASK_DATA', data);
    return data;
  },

  delete: async ({ commit }, id) => {
    await TasksAPI.delete(id);
    commit('REMOVE_TASK', id);
  },

  // ActionCable push (task 05): task.created/updated/completed.
  applyRealtimeTask: ({ commit }, data) => {
    commit('SET_TASK_DATA', data);
  },

  applyRealtimeTaskDeleted: ({ commit }, data) => {
    commit('REMOVE_TASK', data.task.id);
  },
};
```

`mutations.js`:
```js
export const mutations = {
  SET_TASK_DATA($state, task) {
    $state.items = { ...$state.items, [task.id]: task };
  },
  REMOVE_TASK($state, id) {
    const { [id]: _removed, ...rest } = $state.items;
    $state.items = rest;
  },
};
```

Registrar o módulo em `app/javascript/dashboard/store/modules/index.js` (ler o arquivo, é só
mais uma entrada no objeto exportado, mesmo padrão de `kanban`/`contactNotes`).

## 3. Handlers de tempo real — `app/javascript/dashboard/helper/actionCable.js`

Adicionar ao `this.events` do constructor (ao lado de `pipeline_item.*`, linha ~38-39):
```js
'task.created': this.onTaskChanged,
'task.updated': this.onTaskChanged,
'task.completed': this.onTaskChanged,
'task.deleted': this.onTaskDeleted,
```

E os métodos (ao lado de `onPipelineItemChanged`, linha ~204-206):
```js
onTaskChanged = data => {
  this.app.$store.dispatch('tasks/applyRealtimeTask', data);
};

onTaskDeleted = data => {
  this.app.$store.dispatch('tasks/applyRealtimeTaskDeleted', data);
};
```

## Testes

Só se pedirem (Vitest, arquivo `store/modules/specs/tasks/actions.spec.js` ao lado do módulo,
seguindo o padrão local de specs deste projeto — não `__tests__/`).

## Critério de pronto

- No console do navegador (`pnpm dev`), `store.dispatch('tasks/fetchForContact', <id>)`
  retorna array e popula `store.state.tasks.items`.
- Criar uma tarefa via API (curl) com o servidor local rodando dispara o evento ActionCable e
  `store.state.tasks.items` atualiza sem reload, em outra aba logada na mesma conta.
