import { onBeforeUnmount, onMounted } from 'vue'

/**
 * Follows the engine's events with each of [follows] (a store's `follow`) while the
 * component is mounted.
 */
export function useFollowing(...follows: Array<() => () => void>) {
  let stops: Array<() => void> = []
  onMounted(() => {
    stops = follows.map((follow) => follow())
  })
  onBeforeUnmount(() => stops.forEach((stop) => stop()))
}
