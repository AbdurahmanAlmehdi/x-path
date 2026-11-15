import { defineConfigWithVueTs, vueTsConfigs } from '@vue/eslint-config-typescript'
import pluginVue from 'eslint-plugin-vue'

export default defineConfigWithVueTs(
  {
    name: 'xp_web/ignores',
    ignores: ['dist/**', 'coverage/**', 'playwright-report/**', 'test-results/**', 'src/api/schema.d.ts'],
  },
  pluginVue.configs['flat/recommended'],
  vueTsConfigs.recommended,
  {
    name: 'xp_web/rules',
    rules: {
      'vue/multi-word-component-names': 'off',
      'vue/max-attributes-per-line': 'off',
      'vue/singleline-html-element-content-newline': 'off',
      'vue/html-self-closing': 'off',
    },
  },
)
