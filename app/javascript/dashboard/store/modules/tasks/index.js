import { actions } from './actions';
import { getters } from './getters';
import { mutations } from './mutations';

const state = { items: {}, uiFlags: { isFetching: false, isCreating: false } };

export default { namespaced: true, state, getters, actions, mutations };
