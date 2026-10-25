import { atom, read, update } from 'claude-code'
import type { ElementConstructor, EngineInterface, Register, SvgProps } from 'claude-code'

import type { Board, SliceRow, SliceSession, SliceState } from '../types'

const PANE = 'slice-board'
const TITLE = 'Slices'
const REFRESH_MS = 10_000
const SESSIONS_MS = 30_000
const STEPS = ['Plan', 'Red', 'Green', 'Checks', 'Commit']
const LIST_SESSIONS = 'mcp__ccd_session_mgmt__list_sessions'
const START_SESSION = 'mcp__ccd_session__start_session'
/** Parallel builds and test suites turn each other red under load: at most this many slices in progress at once. */
const MAX_PARALLEL = 4
/** How long a slice started from the pane shows "starting" while its session is not listed yet. */
const STARTING_MS = 5 * 60_000
const board = atom({ plugin: 'slice-board', key: 'board' } as const, null)

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

/** Slices started from the pane, by number, with the time of the press. */
const starting = new Map<string, number>()
/** Ready slices and slices awaiting approval at the last refresh; a change is announced once. */
let announced: { ready: Set<string>; approval: Set<string> } | null = null

const numbered = (items: string[] | undefined) => (items ?? []).map((item, index) => `(${index + 1}) ${item}`).join(' ') || '–'

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
    const title = clip(`Slice ${nr} – ${slice.name} (${round})`, 59)
    try {
      const started = (await $.tool.call({
        tool: START_SESSION,
        initiation: 'user_asked',
        title,
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
type SessionEntry = { sessionId?: string; title?: string; cwd?: string; link?: string; isRunning?: boolean; isArchived?: boolean }

const OPEN_SESSION = 'mcp__ccd_window__open_session_in'

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

const samePath = (a: string, b: string) => a.replace(/\\/g, '/').replace(/\/$/, '').toLowerCase() === b.replace(/\\/g, '/').replace(/\/$/, '').toLowerCase()

/** The desktop app's sessions titled "Slice NN …", newest first, those working in this repository before the others. */
function sessionsBySlice(entries: SessionEntry[], root: string): Map<string, SliceSession> {
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
  return new Map([...found].map(([nr, { session }]) => [nr, session]))
}

let sessionCache: { at: number; entries: SessionEntry[] } = { at: 0, entries: [] }

/** Lists the app's sessions at most every 30 s, and only where the permission check allows it without asking. */
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
  const sessions = sessionsBySlice(await appSessions($, now), root)

  const rows: SliceRow[] = []
  for (const slice of slices) {
    const branch = `slice-${slice.nr}`
    const tree = byBranch.get(branch)
    const done = isDone(slice.nr)
    const hasBranch = !done && (byBranch.has(branch) || (await git($, root, ['branch', '--list', branch])) !== '')
    let ticks = mainTicks.get(slice.nr) ?? STEPS.map(() => false)
    let ahead = 0
    let lastCommit = ''
    let hasPlan = false
    if (hasBranch) {
      if (tree) ticks = checklistTicks(await readText($, `${tree}/work/checklist.md`)).get(slice.nr) ?? ticks
      ahead = Number(await git($, root, ['rev-list', '--count', `${integration}..${branch}`])) || 0
      lastCommit = ahead > 0 ? await git($, root, ['log', '-1', '--format=%s', branch]) : ''
      const plans = await $.fs.list(`${tree ?? root}/work/plans`).catch(() => [])
      hasPlan = plans.some(entry => entry.name.endsWith(`-slice-${slice.nr}.md`))
    }
    const waitingFor = depsOf(slice).filter(dep => !isDone(dep))
    const state: SliceState = done ? 'done' : hasBranch || ticks.some(Boolean) ? 'active' : waitingFor.length ? 'blocked' : 'ready'
    const session = state === 'active' || starting.has(slice.nr) ? (sessions.get(slice.nr) ?? null) : null
    const startedAt = starting.get(slice.nr)
    if (startedAt !== undefined && (session || state !== 'ready' || now - startedAt > STARTING_MS)) starting.delete(slice.nr)
    const isStarting = starting.has(slice.nr)
    rows.push({ nr: slice.nr, slug: slice.slug, name: slice.name, state, ticks, waitingFor, ahead, lastCommit, hasPlan, session, isStarting })
  }
  return { root, round, integration, rows, updatedAt: now, problem: null }
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

const clip = (text: string, width: number) => (text.length > width ? `${text.slice(0, Math.max(1, width - 1))}…` : text)

/** What the slice is doing now, from its session and its checklist ticks. */
function phase(row: SliceRow): { label: string; color: string } {
  if (row.session?.isRunning) return { label: 'working', color: 'claude' }
  if (row.hasPlan && !row.ticks[0]) return { label: 'awaiting approval', color: 'warning' }
  const next = row.ticks.findIndex(tick => !tick)
  if (next < 0) return { label: 'ready to merge', color: 'success' }
  return { label: row.session ? 'idle' : 'no session', color: 'inactive' }
}

/** Muted fills that read on light and dark backgrounds alike. */
const COLOR = { done: '#3f9b6e', active: '#d97757', waiting: '#c9962f', track: 'rgba(127,127,127,0.22)' }

/** How far a slice is: its ticked steps, half a step more while its session works. */
function progress(row: SliceRow): number {
  const ticked = row.ticks.filter(Boolean).length
  return Math.min(1, (ticked + (row.session?.isRunning && ticked < STEPS.length ? 0.5 : 0)) / STEPS.length)
}

/** A rounded bar that stretches to the width it is given; parts are fractions of the whole, drawn one after another. */
function barSvg(parts: { value: number; color: string }[], height: number): string {
  let x = 0
  const rects = parts
    .map(part => {
      const w = Math.max(0, Math.min(1000 - x, part.value * 1000))
      const rect = w > 0 ? `<rect x="${x.toFixed(1)}" y="0" width="${w.toFixed(1)}" height="${height}" fill="${part.color}"/>` : ''
      x += w
      return rect
    })
    .join('')
  return (
    `<svg xmlns="http://www.w3.org/2000/svg" width="100%" height="${height}" viewBox="0 0 1000 ${height}" preserveAspectRatio="none">` +
    `<clipPath id="r"><rect width="1000" height="${height}" rx="${height / 2}" ry="${height / 2}"/></clipPath>` +
    `<g clip-path="url(#r)"><rect width="1000" height="${height}" fill="${COLOR.track}"/>${rects}</g></svg>`
  )
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
    const Svg = e.surface === 'terminal' ? undefined : (elements as unknown as { Svg?: ElementConstructor<SvgProps> }).Svg
    const data = await read($, board)
    const width = Math.max(20, (e.props as { bodyColumns?: number }).bodyColumns ?? e.viewport?.columns ?? 60)
    if (!data) return <Text dimColor>No round here: work/_slices.json not found.</Text>
    if (data.problem) return <Text dimColor>{data.problem}</Text>

    const group = (state: SliceState) => data.rows.filter(row => row.state === state)
    const active = group('active')
    const ready = group('ready')
    const blocked = group('blocked')
    const done = group('done')
    const total = data.rows.length || 1
    const activeShare = active.reduce((sum, row) => sum + progress(row), 0) / total
    const doneShare = done.length / total
    const percent = Math.round((doneShare + activeShare) * 100)
    const slots = Math.max(0, MAX_PARALLEL - active.length - ready.filter(row => row.isStarting).length)
    const startable = ready.filter(row => !row.isStarting).slice(0, slots)
    const starting = ready.filter(row => row.isStarting)
    const isWide = width >= 44

    /** A bar: SVG where the surface draws one (stretching, or `px` wide), else a row of cells. */
    const bar = (parts: { value: number; color: string; cell: string }[], height: number, cells: number, px?: number) =>
      Svg ? (
        <Svg alt={`${Math.round(parts.reduce((sum, part) => sum + part.value, 0) * 100)} percent`} source={barSvg(parts, height)} width={px} height={height} />
      ) : (
        <Text>
          {parts.map(part => (
            <Text color={part.cell}>{'\u2501'.repeat(Math.round(part.value * cells))}</Text>
          ))}
          <Text color="inactive">{'\u2501'.repeat(Math.max(0, cells - parts.reduce((sum, part) => sum + Math.round(part.value * cells), 0)))}</Text>
        </Text>
      )

    return (
      <Box flexDirection="column">
        <Box justifyContent="space-between">
          <Text>Slices {data.round}</Text>
          <Text color="subtle">
            {done.length}/{data.rows.length} · {percent} %
          </Text>
        </Box>
        {bar(
          [
            { value: doneShare, color: COLOR.done, cell: 'success' },
            { value: activeShare, color: COLOR.active, cell: 'claude' },
          ],
          6,
          width,
        )}

        {active.map(row => {
          const now = phase(row)
          const value = progress(row)
          const fill = now.color === 'claude' ? COLOR.active : now.color === 'warning' ? COLOR.waiting : COLOR.done
          const step = row.ticks.every(Boolean) ? 'merge' : now.color === 'warning' ? 'approve' : STEPS[row.ticks.findIndex(tick => !tick)]
          const right = isWide ? `${step} ${Math.round(value * 100)} %` : `${Math.round(value * 100)} %`
          return (
            <Box key={`slice-${row.nr}`} justifyContent="space-between" alignItems="center">
              <Text>
                <Text color={now.color}>{'\u25cf'} </Text>
                <Text color="subtle">{row.nr} </Text>
                {clip(row.slug, Math.max(4, width - right.length - (isWide ? 22 : 12)))}
              </Text>
              <Box alignItems="center" gap={1}>
                {isWide && bar([{ value, color: fill, cell: now.color }], 4, 6, 48)}
                <Text color="subtle">{right}</Text>
                {row.session && <Button key={`open-${row.nr}`} plain label={'\u2197'} onPress={() => openSession($, row.session!)} />}
              </Box>
            </Box>
          )
        })}

        {(ready.length > 0 || blocked.length > 0) && (
          <Box justifyContent="space-between" alignItems="center">
            <Text dimColor>
              {clip(
                [
                  ready.length > starting.length ? `ready ${ready.filter(row => !row.isStarting).map(row => row.nr).join(' ')}` : '',
                  starting.length ? `starting ${starting.map(row => row.nr).join(' ')}` : '',
                  blocked.length ? `${blocked.length} blocked` : '',
                ]
                  .filter(Boolean)
                  .join(' · '),
                Math.max(8, width - (startable.length ? 12 : 0)),
              )}
            </Text>
            {startable.length > 0 && (
              <Button
                key="start-ready"
                plain
                label={`\u25b6 Start ${startable.length}`}
                onPress={() => startSlices($, data.root, data.round, startable.map(row => row.nr)).then(() => refresh($, cwd))}
              />
            )}
          </Box>
        )}
      </Box>
    )
  })
}
