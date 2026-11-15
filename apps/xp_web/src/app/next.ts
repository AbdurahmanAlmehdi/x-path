/** Where the app goes after sign-in when `next` is missing or refused. */
export const home = '/'

/**
 * The path a `?next=` asks to return to after sign-in, if it is a path on
 * this origin: it starts with one `/`, has no backslash, no control
 * character, and resolves to the page's own origin. Anything else
 * (`//evil.example`, `https://…`, `/\evil.example`, `javascript:…`) is
 * ignored, so a crafted link cannot send a signed-in person elsewhere.
 */
export function safeNext(next: unknown, origin = window.location.origin): string {
  if (typeof next !== 'string') return home
  if (!next.startsWith('/') || next.startsWith('//')) return home
  if (/[\\\u0000-\u001f\u007f]/.test(next)) return home
  let url: URL
  try {
    url = new URL(next, origin)
  } catch {
    return home
  }
  if (url.origin !== origin || url.pathname.startsWith('/sign-in')) return home
  return `${url.pathname}${url.search}${url.hash}`
}
