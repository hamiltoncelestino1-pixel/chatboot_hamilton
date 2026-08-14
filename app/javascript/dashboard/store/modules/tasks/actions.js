import TasksAPI from '../../../api/tasks';

export const actions = {
  fetchForContact: async ({ commit }, contactId) => {
    const { data } = await TasksAPI.getByContact(contactId);
    data.forEach(task => commit('SET_TASK_DATA', task));
    return data;
  },

  fetchForConversation: async ({ commit }, conversationId) => {
    const { data } = await TasksAPI.getByConversation(conversationId);
    data.forEach(task => commit('SET_TASK_DATA', task));
    return data;
  },

  fetchForPipelineItem: async ({ commit }, pipelineItemId) => {
    const { data } = await TasksAPI.getByPipelineItem(pipelineItemId);
    data.forEach(task => commit('SET_TASK_DATA', task));
    return data;
  },

  create: async ({ commit }, taskParams) => {
    const { data } = await TasksAPI.create({ task: taskParams });
    commit('SET_TASK_DATA', data);
    return data;
  },

  update: async ({ commit }, { id, ...taskParams }) => {
    const { data } = await TasksAPI.update(id, { task: taskParams });
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
