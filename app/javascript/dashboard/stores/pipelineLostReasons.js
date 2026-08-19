import PipelineLostReasonsAPI from 'dashboard/api/pipelineLostReasons';
import { createStore } from 'dashboard/store/storeFactory';

export const usePipelineLostReasonsStore = createStore({
  name: 'PipelineLostReason',
  type: 'pinia',
  API: PipelineLostReasonsAPI,
  getters: {
    getRecords: state =>
      [...state.records].sort((a, b) => a.title.localeCompare(b.title)),
  },
});
