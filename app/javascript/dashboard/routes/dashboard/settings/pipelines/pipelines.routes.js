import { frontendURL } from '../../../../helper/URLHelper';
import SettingsWrapper from '../SettingsWrapper.vue';
import Index from './Index.vue';
import PipelineDetail from './PipelineDetail.vue';

export default {
  routes: [
    {
      path: frontendURL('accounts/:accountId/settings/pipelines'),
      component: SettingsWrapper,
      children: [
        {
          path: '',
          name: 'pipelines_wrapper',
          meta: { permissions: ['administrator'] },
          redirect: to => ({ name: 'pipelines_list', params: to.params }),
        },
        {
          path: 'list',
          name: 'pipelines_list',
          meta: { permissions: ['administrator'] },
          component: Index,
        },
        {
          path: ':pipelineId',
          name: 'pipelines_show',
          meta: { permissions: ['administrator'] },
          component: PipelineDetail,
        },
      ],
    },
  ],
};
