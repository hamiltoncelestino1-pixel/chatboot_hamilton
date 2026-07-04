# Task: Sistema de Lembretes — Frontend: API Client + Store Vuex

## Objetivo

Criar a camada de dados do frontend pra lembretes: cliente de API e módulo Vuex, seguindo
exatamente os padrões já usados pelo módulo `kanban` (`app/javascript/dashboard/store/modules/kanban/`).
Esta task não cria nenhuma tela ainda — isso é feito nas tasks 20 e 21.

**Pré-requisito:** task 18 implementada (API REST disponível).

---

## 1. API Client — `app/javascript/dashboard/api/reminders.js`

Mirror de `app/javascript/dashboard/api/pipelineItems.js`:

```javascript
/* global axios */
import ApiClient from './ApiClient';

class RemindersAPI extends ApiClient {
  constructor() {
    super('reminders', { accountScoped: true });
  }

  complete(id) {
    return axios.post(`${this.url}/${id}/complete`);
  }
}

export default new RemindersAPI();
```

`ApiClient` já provê `get(params)`, `create(payload)`, `update(id, payload)`, `delete(id)`,
`show(id)` genéricos, aceitando query params via `get({ params })` — confirmar a assinatura exata
lendo `app/javascript/dashboard/api/ApiClient.js` antes de implementar (mesma classe-base usada por
`PipelinesAPI`).

---

## 2. Store — `app/javascript/dashboard/store/modules/reminders/`

Mesma estrutura de 4 arquivos do módulo `kanban`.

### `index.js`

```javascript
import { getters } from './getters';
import { actions } from './actions';
import mutations from './mutations';

const state = {
  records: {}, // { [id]: reminder }
  uiFlags: {
    isFetching: false,
    isCreating: false,
    isUpdating: false,
    isDeleting: false,
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
```

### `actions.js`

```javascript
import RemindersAPI from 'dashboard/api/reminders';

export const actions = {
  get: async ({ commit }, params = {}) => {
    commit('SET_REMINDERS_UI_FLAG', { isFetching: true });
    try {
      const { data } = await RemindersAPI.get(params);
      commit('SET_REMINDERS', data);
      return data;
    } finally {
      commit('SET_REMINDERS_UI_FLAG', { isFetching: false });
    }
  },

  create: async ({ commit }, reminderData) => {
    commit('SET_REMINDERS_UI_FLAG', { isCreating: true });
    try {
      const { data } = await RemindersAPI.create({ reminder: reminderData });
      commit('SET_REMINDER', data);
      return data;
    } finally {
      commit('SET_REMINDERS_UI_FLAG', { isCreating: false });
    }
  },

  update: async ({ commit }, { id, ...reminderData }) => {
    commit('SET_REMINDERS_UI_FLAG', { isUpdating: true });
    try {
      const { data } = await RemindersAPI.update(id, { reminder: reminderData });
      commit('SET_REMINDER', data);
      return data;
    } finally {
      commit('SET_REMINDERS_UI_FLAG', { isUpdating: false });
    }
  },

  complete: async ({ commit }, id) => {
    const { data } = await RemindersAPI.complete(id);
    commit('SET_REMINDER', data);
    return data;
  },

  delete: async ({ commit }, id) => {
    commit('SET_REMINDERS_UI_FLAG', { isDeleting: true });
    try {
      await RemindersAPI.delete(id);
      commit('DELETE_REMINDER', id);
    } finally {
      commit('SET_REMINDERS_UI_FLAG', { isDeleting: false });
    }
  },
};
```

### `mutations.js`

```javascript
const mutations = {
  SET_REMINDERS_UI_FLAG($state, data) {
    $state.uiFlags = { ...$state.uiFlags, ...data };
  },

  SET_REMINDERS($state, reminders) {
    reminders.forEach(reminder => {
      $state.records[reminder.id] = reminder;
    });
  },

  SET_REMINDER($state, reminder) {
    $state.records[reminder.id] = reminder;
  },

  DELETE_REMINDER($state, id) {
    const { [id]: _removed, ...remaining } = $state.records;
    $state.records = remaining;
  },
};

export default mutations;
```

### `getters.js`

```javascript
export const getters = {
  getUIFlags: state => state.uiFlags,

  getReminders: state =>
    Object.values(state.records).sort((a, b) => new Date(a.due_at) - new Date(b.due_at)),

  getReminderById: state => id => state.records[id],

  getRemindersByRemindable: state => ({ type, id }) =>
    Object.values(state.records)
      .filter(r => r.remindable?.type === type && r.remindable?.id === id)
      .sort((a, b) => new Date(a.due_at) - new Date(b.due_at)),
};
```

### Registrar o módulo — `app/javascript/dashboard/store/index.js`

```javascript
import reminders from './modules/reminders';
// ...
modules: {
  // ...
  reminders,
}
```

---

## Verificação

```javascript
// no console do navegador, autenticado no dashboard:
await store.dispatch('reminders/create', {
  title: 'Ligar pro cliente',
  due_at: new Date(Date.now() + 3600000).toISOString(),
});
store.getters['reminders/getReminders']; // deve conter o lembrete criado
```

1. `bundle exec vitest run app/javascript/dashboard/store/modules/specs/reminders/` (criar
   `actions.spec.js`/`mutations.spec.js`/`getters.spec.js` mirror dos specs já existentes de
   `kanban`) — tudo verde.
2. Confirmar que `reminders/get({ remindable_type: 'PipelineItem', remindable_id: 5 })` bate
   corretamente com o filtro implementado no `ReminderFinder` (task 18).
