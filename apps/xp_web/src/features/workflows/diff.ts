/** Where a line of a diff is: in both texts, only in the new one, or only in the old one. */
export type DiffKind = 'same' | 'added' | 'removed'

/** One line of a diff of two texts, without its line break. */
export interface DiffLine {
  kind: DiffKind
  text: string
}

/**
 * The lines of [before] and [after], each once: what both have, what
 * [after] added and what it removed, in order (a longest common
 * subsequence of the lines, removals before additions), as `xp_api`'s
 * `diffLines` the Mac app shows.
 */
export function diffLines(before: string, after: string): DiffLine[] {
  const a = linesOf(before)
  const b = linesOf(after)
  // common[i][j]: the longest common subsequence of a[i..] and b[j..].
  const common = Array.from({ length: a.length + 1 }, () => new Array<number>(b.length + 1).fill(0))
  for (let i = a.length - 1; i >= 0; i--) {
    for (let j = b.length - 1; j >= 0; j--) {
      common[i]![j] =
        a[i] === b[j] ? common[i + 1]![j + 1]! + 1 : Math.max(common[i + 1]![j]!, common[i]![j + 1]!)
    }
  }
  const out: DiffLine[] = []
  let i = 0
  let j = 0
  while (i < a.length || j < b.length) {
    if (i < a.length && j < b.length && a[i] === b[j]) {
      out.push({ kind: 'same', text: a[i]! })
      i++
      j++
    } else if (j === b.length || (i < a.length && common[i + 1]![j]! >= common[i]![j + 1]!)) {
      out.push({ kind: 'removed', text: a[i++]! })
    } else {
      out.push({ kind: 'added', text: b[j++]! })
    }
  }
  return out
}

function linesOf(text: string): string[] {
  if (text === '') return []
  const all = text.split('\n')
  return text.endsWith('\n') ? all.slice(0, -1) : all
}
