import { createI18n } from 'vue-i18n';
import i18nMessages from 'dashboard/i18n';

// The dashboard's single vue-i18n instance. It lives here (not inline in
// entrypoints/dashboard.js) so code that runs outside a component's setup - a Vuex action
// raising a toast, for one - can translate through `i18n.global.t(...)` instead of hardcoding a
// language. Same instance the app installs, so it follows `$root.$i18n.locale` changes.
export default createI18n({
  legacy: false, // https://github.com/intlify/vue-i18n/issues/1902
  locale: 'en',
  messages: i18nMessages,
});
