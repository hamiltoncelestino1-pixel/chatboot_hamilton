export const mutations = {
  SET_TASK_DATA($state, task) {
    $state.items = {
      ...$state.items,
      [task.id]: { ...($state.items[task.id] || {}), ...task },
    };
  },
  REMOVE_TASK($state, id) {
    const { [id]: _removed, ...rest } = $state.items;
    $state.items = rest;
  },
};
