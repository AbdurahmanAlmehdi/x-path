/** Hands [text] to the browser as a file called [name] to save. */
export function saveText(name: string, text: string, type = 'text/plain') {
  const url = URL.createObjectURL(new Blob([text], { type }))
  const link = document.createElement('a')
  link.href = url
  link.download = name
  link.click()
  // The download has its own reference to the blob once it starts.
  setTimeout(() => URL.revokeObjectURL(url), 0)
}
