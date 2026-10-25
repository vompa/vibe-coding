import { atom, read, update } from 'claude-code'
import type { ClientProps, ElementConstructor, EngineInterface, Register } from 'claude-code'

import type { Board, SliceRow, SliceSession, SliceState } from '../types'

const PANE = 'slice-board'
const TITLE = 'Slices'
const REFRESH_MS = 10_000
const SESSIONS_MS = 30_000
const STEPS = ['Plan', 'Red', 'Green', 'Checks', 'Commit']
const LIST_SESSIONS = 'mcp__ccd_session_mgmt__list_sessions'
const OPEN_SESSION = 'mcp__ccd_window__open_session_in'
/** Parallel builds and test suites turn each other red under load: at most this many slices in progress at once. */
const MAX_PARALLEL = 4

/** The groups of the pane in the order of the bar and the legend, with a fill for the desktop and a theme color for the terminal. */
const GROUPS: { state: SliceState; label: string; fill: string; cell: string }[] = [
  { state: 'done', label: 'Done', fill: '#34a06f', cell: 'success' },
  { state: 'active', label: 'In progress', fill: '#d97757', cell: 'claude' },
  { state: 'ready', label: 'Ready', fill: '#3b82f6', cell: 'blue' },
  { state: 'blocked', label: 'Blocked', fill: '#b9b9b9', cell: 'inactive' },
]

const board = atom({ plugin: 'slice-board', key: 'board' } as const, null)
const expanded = atom({ plugin: 'slice-board', key: 'expanded' } as const, { done: false, active: true, ready: false, blocked: false })
const opened = atom({ plugin: 'slice-board', key: 'opened' } as const, {})

type Slice = {
  nr: string
  slug: string
  name: string
  round: string
  deps: string
  goal?: string
  source?: string
  scope?: string[]
  not_building?: string[]
  acceptance?: string[]
}
type SessionEntry = { sessionId?: string; title?: string; cwd?: string; link?: string; isRunning?: boolean; isArchived?: boolean }

/** Ready slices and slices awaiting approval at the last refresh; a change is announced once. */
let announced: { ready: Set<string>; approval: Set<string> } | null = null
let sessionCache: { at: number; entries: SessionEntry[] } = { at: 0, entries: [] }

const clip = (text: string, width: number) => (text.length > width ? `${text.slice(0, Math.max(1, width - 1))}…` : text)
const samePath = (a: string, b: string) => a.replace(/\\/g, '/').replace(/\/$/, '').toLowerCase() === b.replace(/\\/g, '/').replace(/\/$/, '').toLowerCase()

async function git($: EngineInterface, cwd: string, args: string[]): Promise<string> {
  const { exitCode, stdout } = await $.process.run(['git', ...args], { cwd, timeoutMs: 15_000 })
  return exitCode === 0 ? stdout.trim() : ''
}

async function readText($: EngineInterface, path: string): Promise<string | null> {
  try {
    return (await $.fs.read(path)) as string
  } catch {
    return null
  }
}

/** Ticks per slice number from a checklist table: `| 12 web-money-pos | ☑ | ☐ | … |`. */
function checklistTicks(text: string | null): Map<string, boolean[]> {
  const ticks = new Map<string, boolean[]>()
  for (const line of (text ?? '').split(/\r?\n/)) {
    const cells = line.split('|').map(cell => cell.trim())
    const nr = /^(\d{2,})\s/.exec(cells[1] ?? '')?.[1]
    if (nr) ticks.set(nr, cells.slice(2, 2 + STEPS.length).map(cell => cell.includes('☑')))
  }
  return ticks
}

function depsOf(slice: Slice): string[] {
  return slice.deps.split(/[,\s]+/).filter(dep => /^\d+$/.test(dep))
}

/** Main checkout and the worktree path of every branch, from `git worktree list --porcelain`. */
function worktrees(porcelain: string): { main: string; byBranch: Map<string, string> } {
  const byBranch = new Map<string, string>()
  let main = ''
  let path = ''
  for (const line of porcelain.split(/\r?\n/)) {
    if (line.startsWith('worktree ')) {
      path = line.slice('worktree '.length)
      if (!main) main = path
    } else if (line.startsWith('branch refs/heads/')) {
      byBranch.set(line.slice('branch refs/heads/'.length), path)
    }
  }
  return { main, byBranch }
}

async function openRound($: EngineInterface, root: string): Promise<string | null> {
  const files = await $.fs.list(`${root}/work/rounds`).catch(() => [])
  for (const file of files.filter(entry => entry.name.endsWith('.md')).sort((a, b) => a.name.localeCompare(b.name))) {
    const text = await readText($, `${root}/work/rounds/${file.name}`)
    if (text?.split(/\r?\n/, 1)[0]?.trim() === 'Status: open') return /^R\d+/.exec(file.name)?.[0] ?? file.name
  }
  return null
}

/** The desktop app's sessions titled "Slice NN …", those working in this repository before the others; `isHere` says one works here. */
function sessionsBySlice(entries: SessionEntry[], root: string): Map<string, { session: SliceSession; isHere: boolean }> {
  const found = new Map<string, { session: SliceSession; isHere: boolean }>()
  for (const entry of entries) {
    const nr = /^Slice (\d{2,})\b/.exec(entry.title ?? '')?.[1]
    if (!nr || !entry.link || !entry.sessionId || entry.isArchived) continue
    const isHere = samePath(entry.cwd ?? '', root)
    const known = found.get(nr)
    if (!known || (isHere && !known.isHere)) {
      const session = { id: entry.sessionId, title: entry.title ?? '', link: entry.link, isRunning: entry.isRunning === true }
      found.set(nr, { session, isHere })
    }
  }
  return found
}

/** Lists the app's sessions at most every 30 s (every refresh while a start is pending), and only where the permission check allows it without asking. */
async function appSessions($: EngineInterface, now: number): Promise<SessionEntry[]> {
  if (now - sessionCache.at < SESSIONS_MS) return sessionCache.entries
  sessionCache = { at: now, entries: sessionCache.entries }
  try {
    const input = { limit: 50 }
    const { decision } = await $.tool.check({ tool: LIST_SESSIONS, input })
    if (decision !== 'allow') return sessionCache.entries
    const called = (await $.tool.call({ tool: LIST_SESSIONS, ...input })) as { text?: string; result?: unknown }
    const content = Array.isArray(called.result) ? (called.result as { text?: string }[]).find(part => typeof part.text === 'string')?.text : undefined
    const entries = JSON.parse(called.text ?? content ?? '[]') as SessionEntry[]
    sessionCache = { at: now, entries: Array.isArray(entries) ? entries : [] }
  } catch (error) {
    $.ui.log(`slice-board: sessions not listed: ${String(error)}`, { to: 'debug' })
  }
  return sessionCache.entries
}

async function collect($: EngineInterface, cwd: string): Promise<Board | null> {
  const { main: root, byBranch } = worktrees(await git($, cwd, ['worktree', 'list', '--porcelain']))
  if (!root) return null
  const slicesText = await readText($, `${root}/work/_slices.json`)
  if (!slicesText) return null
  const now = await $.clock.now()
  const conventions = (await readText($, `${root}/work/conventions.md`)) ?? ''
  const integration = /(?:Integrationsbranch|Integration branch)[^`\n]*`([^`]+)`/i.exec(conventions)?.[1] ?? 'main'
  const round = await openRound($, root)
  if (!round) return { root, round: '–', integration, rows: [], updatedAt: now, problem: 'No open round.' }

  const slices = (JSON.parse(slicesText) as Slice[]).filter(slice => slice.round === round)
  const mainTicks = checklistTicks(await readText($, `${root}/work/checklist.md`))
  const isDone = (nr: string) => (mainTicks.get(nr) ?? []).length === STEPS.length && mainTicks.get(nr)!.every(Boolean)
  const branches = new Set((await git($, root, ['branch', '--list', 'slice-*', '--format=%(refname:short)'])).split(/\r?\n/).filter(Boolean))
  const sessions = sessionsBySlice(await appSessions($, now), root)

  const rows: SliceRow[] = []
  for (const slice of slices) {
    const branch = `slice-${slice.nr}`
    const tree = byBranch.get(branch)
    const done = isDone(slice.nr)
    const hasBranch = !done && (branches.has(branch) || byBranch.has(branch))
    let ticks = mainTicks.get(slice.nr) ?? STEPS.map(() => false)
    let ahead = 0
    let hasPlan = false
    if (hasBranch) {
      if (tree) ticks = checklistTicks(await readText($, `${tree}/work/checklist.md`)).get(slice.nr) ?? ticks
      ahead = Number(await git($, root, ['rev-list', '--count', `${integration}..${branch}`])) || 0
      const plans = await $.fs.list(`${tree ?? root}/work/plans`).catch(() => [])
      hasPlan = plans.some(entry => entry.name.endsWith(`-slice-${slice.nr}.md`))
    }
    const waitingFor = depsOf(slice).filter(dep => !isDone(dep))
    // A session of this repository titled for the slice takes its slot in every pane, also before it has created its branch.
    const found = sessions.get(slice.nr)
    const isClaimed = !done && found?.isHere === true
    const state: SliceState = done ? 'done' : hasBranch || isClaimed || ticks.some(Boolean) ? 'active' : waitingFor.length ? 'blocked' : 'ready'
    const session = state === 'active' ? (found?.session ?? null) : null
    const findings = (slice.source ?? '').replace(/^R\d+\s*[–-]\s*/, '')
    rows.push({ nr: slice.nr, slug: slice.slug, name: slice.name, goal: slice.goal ?? '', findings, state, ticks, waitingFor, ahead, hasPlan, session })
  }
  return { root, round, integration, rows, updatedAt: now, problem: null }
}

/** What a slice in progress is doing, from its session and its checklist ticks. */
function phase(row: SliceRow): { label: string; color: string } {
  if (row.session?.isRunning) return { label: 'working', color: 'claude' }
  if (row.hasPlan && !row.ticks[0]) return { label: 'awaiting approval', color: 'warning' }
  if (row.ticks.every(Boolean)) return { label: 'ready to merge', color: 'success' }
  return { label: row.session ? 'idle' : 'no session', color: 'inactive' }
}

/** How far a slice is: its ticked steps, half a step more while its session works. */
function progress(row: SliceRow): number {
  const ticked = row.ticks.filter(Boolean).length
  return Math.min(1, (ticked + (row.session?.isRunning && ticked < STEPS.length ? 0.5 : 0)) / STEPS.length)
}

/** A toast once when a slice becomes ready to start or its plan starts waiting for approval; nothing on the first refresh. */
function announce($: EngineInterface, data: Board | null) {
  if (!data) return
  const ready = new Set(data.rows.filter(row => row.state === 'ready').map(row => row.nr))
  const approval = new Set(data.rows.filter(row => row.state === 'active' && phase(row).label === 'awaiting approval').map(row => row.nr))
  if (announced) {
    const newlyReady = [...ready].filter(nr => !announced!.ready.has(nr))
    if (newlyReady.length) $.ui.toast(`Ready to start: slice ${newlyReady.join(', ')}`)
    for (const nr of approval) if (!announced.approval.has(nr)) $.ui.toast(`Slice ${nr}: plan awaits your approval`)
  }
  announced = { ready, approval }
}

async function refresh($: EngineInterface, cwd: string) {
  try {
    const next = await collect($, cwd)
    announce($, next)
    await update($, board, () => next)
  } catch (error) {
    $.ui.log(`slice-board: ${String(error)}`, { to: 'debug' })
  }
}

/** Brings a session to the front: the app's window tool where it answers, else the session's `claude://` link through the system. */
async function openSession($: EngineInterface, session: SliceSession) {
  try {
    const shown = (await $.tool.call({ tool: OPEN_SESSION, session_id: session.id, target: 'focus' })) as { deny?: string; isError?: boolean }
    if (!shown.deny && !shown.isError) return
  } catch {
    // fall through to the link
  }
  for (const argv of [['explorer.exe', session.link], ['open', session.link], ['xdg-open', session.link]]) {
    const opened = await $.process.run(argv, { timeoutMs: 10_000 }).catch(() => null)
    if (opened) return
  }
  $.ui.toast(`Open "${session.title}" from the sidebar.`)
}

/**
 * Puts a request into the person's prompt box to start one session per slice; Enter makes it their message and Claude
 * starts the sessions with the session's own permission check. A start straight from the pane has no conversation
 * behind it, and the auto mode classifier refuses it.
 */
async function requestStart($: EngineInterface, round: string, rows: SliceRow[]) {
  const list = rows.map(row => `${row.nr} ${row.name}`).join('; ')
  const text =
    `Start one separate session per slice of round ${round} for: ${list}. ` +
    `Each in this repository's main checkout without an app worktree, titled "Slice NN – <name> (${round})", ` +
    `briefed with "/slice NN", the slice's goal, scope, not-building list and acceptance cases from work/_slices.json, ` +
    `the parallel rules (own branch and worktree, keep both sides on squash conflicts, never push) and work/session-hints.md.`
  const box = await $.prompt.read()
  const { isFilled } = await $.prompt.fill(box.text.trim() ? { text: `\n${text}`, mode: 'append' } : { text })
  $.ui.toast(isFilled ? 'Start request is in the prompt box: Enter sends it.' : 'The prompt box is busy: close the dialog and press Start again.')
}

export const register: Register = on => {
  let cwd = ''

  on('session.start', async ($, e, next) => {
    const started = await next(e)
    cwd = e.cwd
    await $.command.register({ name: 'slices', description: 'Show the slices of the open round in a pane' })
    await refresh($, cwd)
    if (await read($, board)) void $.ui.open({ id: PANE, title: TITLE })
    $.clock.every(REFRESH_MS, () => void refresh($, cwd))
    return started
  })

  on('command.run', { command: 'slices' }, async $ => {
    sessionCache = { at: 0, entries: sessionCache.entries }
    await refresh($, cwd || (await $.session.cwd()))
    await $.ui.open({ id: PANE, title: TITLE })
    return { text: 'Slice pane opened.' }
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const elements = $.ui.resolve(e)
    const { Box, Text, Button } = elements
    // A Client draws the name with a delayed reveal of the details; VS Code and the phone have none and fall back to a click.
    const Client = e.surface === 'desktop' || e.surface === 'terminal' ? (elements as { Client?: ElementConstructor<ClientProps> }).Client : undefined
    // Air between rows and groups on surfaces that draw in pixels; the terminal keeps one line per row.
    const air = e.surface === 'terminal' ? 0 : 1
    const data = await read($, board)
    const open = await read($, expanded)
    const details = await read($, opened)
    const width = Math.max(20, (e.props as { bodyColumns?: number }).bodyColumns ?? e.viewport?.columns ?? 60)
    if (!data) return <Text dimColor>No round here: work/_slices.json not found.</Text>
    if (data.problem) return <Text dimColor>{data.problem}</Text>

    const total = data.rows.length || 1
    const rowsOf = (state: SliceState) => data.rows.filter(row => row.state === state)
    const done = rowsOf('done')
    const ready = rowsOf('ready')
    const slots = Math.max(0, MAX_PARALLEL - rowsOf('active').length)
    const startable = ready.slice(0, slots)
    const percentOf = (count: number) => `${Math.round((count / total) * 100)} %`
    const toggle = (state: SliceState) => update($, expanded, current => ({ ...current, [state]: !current[state] }))
    const toggleDetails = (nr: string) => update($, opened, current => ({ ...current, [nr]: !current[nr] }))
    const start = (rows: SliceRow[]) => requestStart($, data.round, rows)

    /** Count and share, right-aligned in two fixed columns like the context pane's legend. */
    const columns = (count: number) => (
      <Box flexShrink={0}>
        <Box width={5} justifyContent="flex-end">
          <Text color="subtle">
            {count}
          </Text>
        </Box>
        <Box width={7} justifyContent="flex-end">
          <Text color="subtle">
            {percentOf(count)}
          </Text>
        </Box>
      </Box>
    )

    /** One slice under its group: what it is, and on the right what it waits for or does. */
    const sliceRow = (row: SliceRow) => {
      const now = phase(row)
      const step = row.ticks.every(Boolean) ? 'merge' : STEPS[row.ticks.findIndex(tick => !tick)]
      // Every ready slice can be started while a slot is free; the person picks which.
      const canStart = row.state === 'ready' && slots > 0
      const right =
        row.state === 'active' ? (
          <Box flexShrink={0} alignItems="center" gap={1}>
            <Text color="subtle">
              {step} · {Math.round(progress(row) * 100)} %
            </Text>
            {row.session && <Button key={`open-${row.nr}`} plain label={'↗'} onPress={() => openSession($, row.session!)} />}
          </Box>
        ) : row.state === 'ready' ? (
          <Box flexShrink={0}>
            {canStart && <Button key={`start-${row.nr}`} plain label={'▶'} onPress={() => start([row])} />}
          </Box>
        ) : row.state === 'blocked' ? (
          <Text color="subtle">
            {'←'} {row.waitingFor.join(', ')}
          </Text>
        ) : null
      const isOpen = details[row.nr] === true
      const isDim = row.state === 'done' || row.state === 'blocked' || (row.state === 'ready' && !canStart)
      const rightRoom = row.state === 'active' ? (step ?? '').length + 12 : row.state === 'ready' ? 10 : row.state === 'blocked' ? row.waitingFor.join(', ').length + 4 : 0
      // A button draws its label unshortened: clip the name to the room the row leaves it.
      const label = clip(`${row.nr} ${row.state === 'ready' ? row.name : row.slug}`, Math.max(8, width - 8 - rightRoom))
      const marks = STEPS.map((name, index) => `${row.ticks[index] ? '✓' : index === row.ticks.findIndex(tick => !tick) ? '▸' : '·'} ${name}`).join('  ')
      const nameOf = (nr: string) => data.rows.find(one => one.nr === nr)?.name ?? ''
      const facts =
        row.state === 'active'
          ? [marks, now.label, `${row.ahead} commit${row.ahead === 1 ? '' : 's'}`, row.findings]
          : row.state === 'blocked'
            ? [`Waits for ${row.waitingFor.map(nr => `${nr} ${nameOf(nr)}`).join(', ')}`, row.findings]
            : [row.findings]
      const lines = [
        ...(row.state !== 'ready' ? [{ text: row.name, tone: 'strong' as const }] : []),
        ...(row.goal ? [{ text: row.goal, tone: 'dim' as const }] : []),
        { text: facts.filter(Boolean).join(' · '), tone: 'subtle' as const },
      ]
      const left = (
        <Box alignItems="flex-start" gap={1}>
          {row.state === 'active' && <Text color={now.color}>{'●'}</Text>}
          {Client ? (
            <Client key={`name-${row.nr}`} module="./name.tsx" props={{ label, isDim, lines }} flexGrow={1} />
          ) : (
            <Button key={`name-${row.nr}`} plain dimColor={isDim} label={label} onPress={() => toggleDetails(row.nr)} />
          )}
        </Box>
      )
      return (
        <Box key={`row-${row.nr}`} flexDirection="column" paddingLeft={4} hover={{ backgroundColor: 'rgba(127,127,127,0.08)' }}>
          <Box justifyContent="space-between" alignItems="center" gap={1}>
            {/* minWidth 0: without it a flex item never shrinks below its text, the name pushes the buttons out of the pane. */}
            <Box flexGrow={1} flexShrink={1} minWidth={0} overflow="hidden">
              {left}
            </Box>
            {right}
          </Box>
          {/* Without a Client the details open with a click on the name: the whole name, the goal, and what the slice waits for or how far it is. */}
          {!Client && isOpen && (
            <Box flexDirection="column" paddingLeft={3} paddingBottom={air}>
              {lines.map(line => (
                <Text dimColor={line.tone === 'dim'} color={line.tone === 'subtle' ? 'subtle' : undefined}>
                  {line.text}
                </Text>
              ))}
            </Box>
          )}
        </Box>
      )
    }

    return (
      <Box flexDirection="column">
        <Box justifyContent="space-between">
          <Text>Round {data.round}</Text>
          <Text color="subtle">
            {done.length} / {data.rows.length} done
          </Text>
        </Box>
        <Box marginTop={1} marginBottom={1}>
          {GROUPS.filter(group => rowsOf(group.state).length > 0).map(group => {
            const share = rowsOf(group.state).length / total
            return (
              <Box key={`bar-${group.state}`} width={0} flexGrow={rowsOf(group.state).length} backgroundColor={group.fill} justifyContent="center" overflow="hidden">
                <Text color="#ffffff" wrap="truncate-end">
                  {share >= 0.08 ? percentOf(rowsOf(group.state).length) : ' '}
                </Text>
              </Box>
            )
          })}
        </Box>

        {/* Start above the groups, so it stays in view however long the lists get. */}
        {ready.length > 0 && (
          <Box justifyContent="space-between" alignItems="center" marginBottom={1}>
            <Text color="subtle">{slots > 0 ? `${slots} of ${MAX_PARALLEL} slots free` : `All ${MAX_PARALLEL} slots in use`}</Text>
            {startable.length > 0 && <Button key="start-ready" label={`Start ${startable.length}`} onPress={() => start(startable)} />}
          </Box>
        )}

        {GROUPS.map(group => {
          const rows = rowsOf(group.state)
          const isOpen = open[group.state] && rows.length > 0
          return (
            <Box key={`group-${group.state}`} flexDirection="column" marginTop={air} gap={air}>
              <Box justifyContent="space-between" alignItems="center">
                <Box alignItems="center" gap={1}>
                  <Text color={e.surface === 'terminal' ? group.cell : group.fill}>{'■'}</Text>
                  <Button key={`toggle-${group.state}`} plain label={`${isOpen ? '▾' : '›'} ${group.label}`} onPress={() => toggle(group.state)} />
                </Box>
                {columns(rows.length)}
              </Box>
              {isOpen && rows.map(sliceRow)}
            </Box>
          )
        })}

      </Box>
    )
  })
}
