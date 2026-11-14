import '@/ui/base.css'

import { createPinia } from 'pinia'
import { createApp } from 'vue'

import App from './App.vue'
import { createAppRouter, followSessionEnd } from './router'

const router = createAppRouter()
createApp(App).use(createPinia()).use(router).mount('#app')
followSessionEnd(router)
