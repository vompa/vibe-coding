import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Board, SliceRow, SliceSession, SliceState } from '../types'

const PANE = 'slice-board'
const TITLE = 'Slices'
const REFRESH_MS = 10_000
const SESSIONS_MS = 30_000
const STEPS = ['Plan', 'Red', 'Green', 'Checks', 'Commit']
const LIST_SESSIONS = 'mcp__ccd_session_mgmt__list_sessions'
const OPEN_SESSION = 'mcp__ccd_window__open_session_in'
const START_SESSION = 'mcp__ccd_session__start_session'
/** Parallel builds and test suites turn each other red under load: at most this many slices in progress at once. */
const MAX_PARALLEL = 4
/** How long a slice started from the pane shows "starting" while its session is not listed yet. */
const STARTING_MS = 5 * 60_000

/** The groups of the pane in the order of the bar and the legend, with a fill for the desktop and a theme color for the terminal. */
const GROUPS: { state: SliceState; label: string; fill: string; cell: string }[] = [
  { state: 'done', label: 'Done', fill: '#34a06f', cell: 'success' },
  { state: 'active', label: 'In progress', fill: '#d97757', cell: 'claude' },
  { state: 'ready', label: 'Ready', fill: '#3b82f6', cell: 'blue' },
  { state: 'blocked', label: 'Blocked', fill: '#b9b9b9', cell: 'inactive' },
]

const board = atom({ plugin: 'slice-board', key: 'board' } as const, null)
const expanded = atom({ plugin: 'slice-board', key: 'expanded' } as const, { done: false, active: true, ready: false, blocked: false })

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

/** Slices started from the pane, by number, with the time of the press. */
const starting = new Map<string, number>()
/** Ready slices and slices awaiting approval at the last refresh; a change is announced once. */
let announced: { ready: Set<string>; approval: Set<string> } | null = null
let sessionCache: { at: number; entries: SessionEntry[] } = { at: 0, entries: [] }

const clip = (text: string, width: number) => (text.length > width ? `${text.slice(0, Math.max(1, width - 1))}…` : text)
const numbered = (items: string[] | undefined) => (items ?? []).map((item, index) => `(${index + 1}) ${item}`).join(' ') || '–'
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
  if (now - sessionCache.at < (starting.size ? REFRESH_MS : SESSIONS_MS)) return sessionCache.entries
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
    const session = state === 'active' || starting.has(slice.nr) ? (found?.session ?? null) : null
    const startedAt = starting.get(slice.nr)
    if (startedAt !== undefined && (session || state !== 'ready' || now - startedAt > STARTING_MS)) starting.delete(slice.nr)
    rows.push({ nr: slice.nr, slug: slice.slug, name: slice.name, state, ticks, waitingFor, ahead, hasPlan, session, isStarting: starting.has(slice.nr) })
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

/** The start prompt of a slice session: the slice from work/_slices.json, the parallel rules, and work/session-hints.md when the repository has one. */
function startPrompt(slice: Slice, round: string, hints: string | null): { prompt: string; background: string } {
  const background =
    `Round ${round} of this repository runs slice by slice (work/_slices.json, work/checklist.md, work/rounds/). ` +
    `This session takes slice ${slice.nr} "${slice.name}" (${slice.source ?? slice.nr}); other slices run in parallel sessions, each in its own worktree.`
  const prompt = [
    `/slice ${slice.nr}`,
    '',
    `Slice ${slice.nr} "${slice.slug}": ${slice.goal ?? slice.name}`,
    `Scope: ${numbered(slice.scope)}`,
    `Not building: ${numbered(slice.not_building)}`,
    `Acceptance: ${numbered(slice.acceptance)}`,
    '',
    'Work it exactly as .claude/commands/slice.md says, plan approval first. Other slices run in parallel sessions: touch only your own branch',
    `slice-${slice.nr} and its worktree, never push; when you squash onto the integration branch, conflicts in work/checklist.md, the round record`,
    'and the documents that change with a change are expected, and every tick and entry of both sides stays. End with the three lines of section 4.',
    ...(hints ? ['', hints.trim()] : []),
  ].join('\n')
  return { prompt, background }
}

/** Starts one session per slice in the repository's main checkout; the press on the pane's button is the person's request. */
async function startSlices($: EngineInterface, root: string, round: string, numbers: string[]) {
  const slices = JSON.parse((await readText($, `${root}/work/_slices.json`)) ?? '[]') as Slice[]
  const hints = await readText($, `${root}/work/session-hints.md`)
  for (const nr of numbers) {
    const slice = slices.find(one => one.nr === nr && one.round === round)
    if (!slice || starting.has(nr)) continue
    const { prompt, background } = startPrompt(slice, round, hints)
    try {
      const started = (await $.tool.call({
        tool: START_SESSION,
        initiation: 'user_asked',
        title: clip(`Slice ${nr} – ${slice.name} (${round})`, 59),
        name: `slice-${nr}`,
        context: 'fresh',
        use_worktree: false,
        cwd: root,
        prompt,
        background,
      })) as { deny?: string; isError?: boolean; text?: string }
      if (started.deny || started.isError) {
        $.ui.toast(`Slice ${nr} not started: ${clip(started.deny ?? started.text ?? 'refused', 80)}`)
        continue
      }
      starting.set(nr, await $.clock.now())
    } catch (error) {
      $.ui.toast(`Slice ${nr} not started: ${clip(String(error), 80)}`)
    }
  }
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
    // Air between rows and groups on surfaces that draw in pixels; the terminal keeps one line per row.
    const air = e.surface === 'terminal' ? 0 : 1
    const data = await read($, board)
    const open = await read($, expanded)
    if (!data) return <Text dimColor>No round here: work/_slices.json not found.</Text>
    if (data.problem) return <Text dimColor>{data.problem}</Text>

    const total = data.rows.length || 1
    const rowsOf = (state: SliceState) => data.rows.filter(row => row.state === state)
    const done = rowsOf('done')
    const ready = rowsOf('ready')
    const slots = Math.max(0, MAX_PARALLEL - rowsOf('active').length - ready.filter(row => row.isStarting).length)
    const startable = ready.filter(row => !row.isStarting).slice(0, slots)
    const percentOf = (count: number) => `${Math.round((count / total) * 100)} %`
    const toggle = (state: SliceState) => update($, expanded, current => ({ ...current, [state]: !current[state] }))
    const start = (numbers: string[]) => startSlices($, data.root, data.round, numbers).then(() => refresh($, cwd))

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
      const canStart = row.state === 'ready' && !row.isStarting && slots > 0
      const left =
        row.state === 'active' ? (
          <Text wrap="truncate-end">
            <Text color={now.color}>{'●'} </Text>
            <Text color="subtle">{row.nr} </Text>
            {row.slug}
          </Text>
        ) : (
          <Text wrap="truncate-end" dimColor={row.state === 'done' || row.state === 'blocked' || (row.state === 'ready' && !canStart && !row.isStarting)}>
            <Text color="subtle">{row.nr} </Text>
            {row.state === 'ready' ? row.name : row.slug}
          </Text>
        )
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
            {row.isStarting ? (
              <Text color="claude">starting</Text>
            ) : canStart ? (
              <Button key={`start-${row.nr}`} plain label={'▶'} onPress={() => start([row.nr])} />
            ) : null}
          </Box>
        ) : row.state === 'blocked' ? (
          <Text color="subtle">
            {'←'} {row.waitingFor.join(', ')}
          </Text>
        ) : null
      return (
        <Box key={`row-${row.nr}`} justifyContent="space-between" alignItems="center" paddingLeft={4} gap={1}>
          {/* minWidth 0: without it a flex item never shrinks below its text, the name pushes the buttons out of the pane. */}
          <Box flexGrow={1} flexShrink={1} minWidth={0} overflow="hidden">
            {left}
          </Box>
          {right}
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

        {ready.length > 0 && (
          <Box justifyContent="space-between" alignItems="center" marginTop={1}>
            <Text color="subtle">{slots > 0 ? `${slots} of ${MAX_PARALLEL} slots free` : `All ${MAX_PARALLEL} slots in use`}</Text>
            {startable.length > 0 && <Button key="start-ready" label={`Start ${startable.length}`} onPress={() => start(startable.map(row => row.nr))} />}
          </Box>
        )}
      </Box>
    )
  })
}
