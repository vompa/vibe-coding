import { expect, test, type Plugin } from 'claude-code/testing'

const ROOT = '/repo'
const PANE = {
  plugin: 'slice-board',
  component: 'Pane',
  requestId: 'slice-board',
  props: { title: 'Slices', isFocused: false, bodyColumns: 60, placement: 'dock', scroll: { offset: 0, bodyRows: 40 }, view: {} },
} as const

const slices = [
  { nr: '01', slug: 'web-a', name: 'A', round: 'R01', deps: '–' },
  { nr: '02', slug: 'web-b', name: 'B ready', round: 'R01', deps: '01' },
  { nr: '03', slug: 'app-c', name: 'C in the app', round: 'R01', deps: '–', goal: 'Messages of C are announced.', source: 'R01 – W5, W9' },
  { nr: '04', slug: 'app-d', name: 'D', round: 'R01', deps: '03', goal: 'D follows C.', source: 'R01 – W7' },
  { nr: '09', slug: 'old', name: 'other round', round: 'R00', deps: '–' },
]
const files: Record<string, string> = {
  [`${ROOT}/work/_slices.json`]: JSON.stringify(slices),
  [`${ROOT}/work/conventions.md`]: '- Integrationsbranch: `dev` im Hauptordner',
  [`${ROOT}/work/rounds/R01-ui.md`]: 'Status: open\n\n# Round',
  [`${ROOT}/work/checklist.md`]: [
    '| Slice | Plan | Tests red | Green | Checks | Commit |',
    '| 01 web-a | ☑ | ☑ | ☑ | ☑ | ☑ |',
    '| 02 web-b | ☐ | ☐ | ☐ | ☐ | ☐ |',
    '| 03 app-c | ☐ | ☐ | ☐ | ☐ | ☐ |',
    '| 04 app-d | ☐ | ☐ | ☐ | ☐ | ☐ |',
  ].join('\n'),
  [`${ROOT}/wt/slice-03/work/checklist.md`]: '| 03 app-c | ☑ | ☑ | ☐ | ☐ | ☐ |',
}
const porcelain = `worktree ${ROOT}\nHEAD 1\nbranch refs/heads/dev\n\nworktree ${ROOT}/wt/slice-03\nHEAD 2\nbranch refs/heads/slice-03\n`
const sessions = [
  // A session elsewhere first: the one working in this repository wins.
  { sessionId: 'local_old', title: 'Slice 03', cwd: 'C:\\elsewhere', link: 'claude://claude.ai/epitaxy/local_old', isRunning: true, isArchived: false },
  { sessionId: 'local_c', title: 'Slice 03 – C (R01)', cwd: ROOT, link: 'claude://claude.ai/epitaxy/local_c', isRunning: false, isArchived: false },
]

type BoardBody = Extract<Parameters<typeof test>[1], (...args: never[]) => unknown>
type Board$ = Parameters<BoardBody>[0]
type BoardOn = Parameters<BoardBody>[1]

/** Submits a prompt as the person typing it does; the kit's event type also lists fields only the engine sets. */
const submit = ($: Board$, text: string) => $.prompt.submit({ text } as Parameters<Board$['prompt']['submit']>[0])

/** Stands for the engine: the repository above on disk and in git, the app's sessions as given. */
async function startBoard($: Board$, on: BoardOn, appSessions: typeof sessions, now = Date.UTC(2026, 9, 25, 10, 0, 0), show = true, toasts: string[] = []) {
  on('command.register', () => ({ value: { command: 'slices' } }))
  const opened: string[] = []
  on('ui.open', (_, e) => {
    opened.push((e as { id: string }).id)
    return { value: { isPlaced: true } }
  })
  on('ui.close', () => ({ value: undefined }))
  on('prompt.submit', (_, e) => ({ text: e.text }))
  on('clock.now', () => ({ value: now }))
  // The pauses are held and recorded: an answer at once would run the next refresh at once, and so on.
  const pauses: number[] = []
  const held: (() => void)[] = []
  on('clock.after', (_, e) => {
    pauses.push(e.ms)
    return new Promise(resolve => held.push(() => resolve({ value: undefined })))
  })
  /** Ends the pause that is held and waits for the next one: one full tick of the refresh. */
  const tick = async () => {
    const before = held.length
    held[before - 1]?.()
    for (let waited = 0; held.length === before && waited < 200; waited++) await new Promise(resolve => setTimeout(resolve, 5))
  }
  on('ui.log', () => ({ value: undefined }))
  on('ui.toast', (_, e) => {
    toasts.push((e as { message?: string; text?: string }).message ?? (e as { text?: string }).text ?? '')
    return { value: undefined }
  })
  // The engine makes paths absolute for the host (`C:\repo\…` on Windows): compare them without drive and separators.
  const plain = (path: string | undefined) => (path ?? '').replace(/\\/g, '/').replace(/^[A-Za-z]:/, '')
  on('fs.read', (_, e) => {
    const text = files[plain(e.path)]
    if (text === undefined) throw new Error(`ENOENT ${e.path}`)
    return { value: text }
  })
  on('fs.list', (_, e) => {
    const names: Record<string, string[]> = {
      [`${ROOT}/work/rounds`]: ['R01-ui.md'],
      [`${ROOT}/wt/slice-03/work/plans`]: ['2026-10-25-slice-03.md'],
    }
    return { value: (names[plain(e.path)] ?? []).map(name => ({ name, kind: 'file', size: 1, mtimeMs: 0, isLink: false })) }
  })
  const gitCalls: string[] = []
  on('process.run', (_, e) => {
    const args = e.argv.slice(1).join(' ')
    gitCalls.push(args)
    const stdout = args.startsWith('worktree list') ? porcelain : args.startsWith('branch --list') ? 'slice-03\n' : args === 'rev-list --count dev..slice-03' ? '2\n' : ''
    return { value: { exitCode: 0, stdout, stderr: '', isStdoutTruncated: false, isStderrTruncated: false } }
  })
  on('tool.check', () => ({ decision: 'allow' }))
  const shown: string[] = []
  on('tool.call', { tool: 'mcp__ccd_window__open_session_in' }, (_, e) => {
    shown.push(String((e as { session_id?: string }).session_id))
    return { result: [{ type: 'text', text: 'Focused.' }], text: 'Focused.' }
  })
  on('tool.call', { tool: 'mcp__ccd_session_mgmt__list_sessions' }, () => ({
    result: [{ type: 'text', text: JSON.stringify(appSessions) }],
    text: JSON.stringify(appSessions),
  }))
  // The prompt box: what the person has typed, and what the pane writes into it.
  const box = { text: '' }
  on('prompt.read', () => ({ value: { text: box.text, cursor: box.text.length } }))
  const filled: { text: string; mode?: string }[] = []
  on('prompt.fill', (_, e) => {
    filled.push({ text: e.text, mode: e.mode })
    box.text = e.mode === 'append' ? box.text + e.text : e.text
    return { isFilled: true }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: ROOT, surface: 'desktop', isInteractive: true })
  if (show) await submit($, '/slices')
  return { gitCalls, shown, filled, box, opened, pauses, tick }
}

test('the pane shows the round as a legend with groups, opens a session and starts the ready slices', async ($, on) => {
  const { gitCalls, shown } = await startBoard($, on, sessions)
  // One listing of the slice branches per refresh, not one call per slice.
  expect(gitCalls.filter(args => args.startsWith('branch --list')).length).toBe(1)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /^Round R01$/ }))?.text).toBe('Round R01')
    expect((await ui.find({ type: 'Text', text: /done$/ }))?.text).toBe('1 / 4 done')
    // The bar is one line high and carries each group's share inside its segment.
    expect((await ui.find({ type: 'Text', text: /^25 %$/ }))?.text).toBe('25 %')
    // In progress is open by default, with the slice's step and share; the other groups are folded.
    expect((await ui.find({ type: 'Text', text: /app-c$/ }))?.text).toBe('● 03 app-c')
    expect((await ui.find({ type: 'Text', text: /Green ·/ }))?.text).toBe('Green · 40 %')
    expect(await ui.find({ type: 'Text', text: /B ready/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /other round/ })).toBeUndefined()
    shown.length = 0
    await ui.press({ key: 'open-03' })
    expect(shown).toEqual(['local_c'])
    // Unfolding a group lists its slices.
    await ui.press({ key: 'toggle-blocked' })
    expect((await ui.find({ type: 'Text', text: /app-d$/ }))?.text).toBe('04 app-d')
    expect((await ui.find({ type: 'Text', text: /← 03/ }))?.text).toBe('← 03')
    await ui.press({ key: 'toggle-blocked' })
    expect(await ui.find({ type: 'Text', text: /app-d$/ })).toBeUndefined()
    await ui.unmount()
  }

})

test('a finished slice unfolds its report, and a slice the loop left behind stands above the groups', async ($, on) => {
  files[`${ROOT}/.slice-loop/slice-01.report.json`] = JSON.stringify({
    title: 'A done', summary: 'A is built.', started: '2026-11-01T14:44:00Z', ended: '2026-11-01T17:02:00Z',
    position: 1, total: 4, commit: '55fba4b6', files: 36, checks: 7, manual: ['1. Scan a code'],
  })
  files[`${ROOT}/.slice-loop/events.jsonl`] = [
    '{"type":"slice_left","slice":"02","reason":"old reason"}',
    '{"type":"slice_planning","slice":"02"}',
    '{"type":"slice_left","slice":"03","reason":"check red"}',
    'half a lin',
  ].join('\n')
  await startBoard($, on, sessions, Date.UTC(2026, 9, 25, 17, 0, 0))
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /check red/ }))?.text).toBe('! 03: check red')
  expect(await ui.find({ type: 'Text', text: /old reason/ })).toBeUndefined()
  await ui.press({ key: 'toggle-done' })
  expect(await ui.find({ type: 'Text', text: /A is built/ })).toBeUndefined()
  await ui.press({ key: 'report-01' })
  expect((await ui.find({ type: 'Text', text: /A is built/ }))?.text).toBe('A is built.')
  expect((await ui.find({ type: 'Text', text: /2 h 18 min$/ }))?.text).toMatch(/^Start \d\d:44 · End \d\d:02 · 2 h 18 min$/)
  expect((await ui.find({ type: 'Text', text: /^Slice 1 of 4/ }))?.text).toBe('Slice 1 of 4 · 36 files · 7 checks green · 55fba4b6')
  expect((await ui.find({ type: 'Text', text: /Scan a code/ }))?.text).toBe('1. Scan a code')
  await ui.unmount()
  delete files[`${ROOT}/.slice-loop/slice-01.report.json`]
  delete files[`${ROOT}/.slice-loop/events.jsonl`]
})

// The person closing the pane: neither the test's `$` nor its hooks may raise `ui.close`, a plugin's `$` may.
// An inline plugin shares no variables with the test, so a prompt tells it when.
const CLOSE_PROMPT = 'close the pane'
const closer = {
  name: 'closer',
  register: on => {
    on('prompt.submit', async ($, e, next) => {
      if (e.text === 'close the pane') await $.ui.close({ id: 'slice-board' })
      return next(e)
    })
  },
} satisfies Plugin

test('a closed pane runs no git and still announces what the loop did', { plugins: [closer] }, async ($, on) => {
  const events = ['{"type":"slice_started","slice":"01"}']
  files[`${ROOT}/.slice-loop/events.jsonl`] = events.join('\n')
  const toasts: string[] = []
  const { gitCalls, tick } = await startBoard($, on, sessions, Date.UTC(2026, 9, 25, 18, 0, 0), true, toasts)
  // The first read is the starting point: what happened before is on the pane, not in a toast.
  expect(toasts).toEqual([])
  await submit($, CLOSE_PROMPT)
  const callsWhenClosed = gitCalls.length
  files[`${ROOT}/.slice-loop/events.jsonl`] = [
    ...events,
    '{"type":"slice_merged","slice":"01","position":"1","total":"4"}',
    '{"type":"slice_parked","slice":"02","reason":"NEEDS-DECISION: Which rate?","question":"yes"}',
    '{"type":"slice_left","slice":"03","reason":"check red"}',
    '{"type":"loop_stopped","reason":"uncommitted changes"}',
  ].join('\n')
  await tick()
  expect(gitCalls.length).toBe(callsWhenClosed)
  expect(toasts).toEqual(['Slice 01 done (1 of 4): /slices shows the report', 'Slice 02 asks: Which rate?', 'Slice 03 left behind: check red', 'The slice loop stopped: uncommitted changes'])
  // Told once, and the watch goes on.
  await tick()
  expect(toasts).toHaveLength(4)
  delete files[`${ROOT}/.slice-loop/events.jsonl`]
})

test('Start writes a request into the prompt box, after any draft the person typed', async ($, on) => {
  const { filled, box } = await startBoard($, on, sessions, Date.UTC(2026, 9, 25, 16, 0, 0))
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /slots free/ }))?.text).toBe('1 of 2 slots free')
  // Start writes a request into the prompt box instead of starting sessions itself; Enter makes it the person's message.
  await ui.press({ key: 'start-ready' })
  expect(filled).toHaveLength(1)
  expect(box.text).toMatch(/^Start one separate session per slice of round R01 for: 02 B ready\. /)
  expect(box.text).toContain('work/session-hints.md')
  // Parallel sessions run on their own (auto: the plan's assumptions, no approval round) and end with SLICE-READY;
  // the merge queue in the main checkout does the squash.
  expect(box.text).toContain('"/slice NN parallel auto"')
  expect(box.text).toContain('SLICE-READY: NN')
  expect(box.text).toContain('slice_loop.py --merge')
  // A draft the person typed stays; the request comes after it.
  box.text = 'my draft'
  await ui.press({ key: 'toggle-ready' })
  await ui.press({ key: 'start-02' })
  expect(filled[1]?.mode).toBe('append')
  expect(box.text.startsWith('my draft\nStart one separate session')).toBe(true)
  await ui.unmount()
})

test('a slice whose session runs in this repository takes a slot in every pane, before its branch exists', async ($, on) => {
  const started = { sessionId: 'local_b', title: 'Slice 02 – B ready (R01)', cwd: ROOT, link: 'claude://claude.ai/epitaxy/local_b', isRunning: true, isArchived: false }
  // A later time: the plugin keeps its listing of the app's sessions for 30 s, also across tests.
  await startBoard($, on, [...sessions, started], Date.UTC(2026, 9, 25, 11, 0, 0))
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /web-b$/ }))?.text).toBe('● 02 web-b')
  expect(await ui.find({ type: 'Text', text: /slots free/ })).toBeUndefined()
  expect(await ui.find({ type: 'Button', text: /Start/ })).toBeUndefined()
  await ui.unmount()
})

test('the next refresh comes after 10 s, and VS Code shows the rows as text', async ($, on) => {
  const { pauses } = await startBoard($, on, sessions, Date.UTC(2026, 9, 25, 12, 0, 0))
  expect(pauses).toEqual([10_000])
  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect((await ui.find({ type: 'Text', text: /done/ }))?.text).toBe('1 / 4 done')
  expect((await ui.find({ type: 'Text', text: /app-c$/ }))?.text).toBe('● 03 app-c')
  await ui.unmount()
})

test('the pane opens only in the chat that runs the round: /slice, /slice status, /slice close, /vibe-coding, /slices', async ($, on) => {
  const { opened, gitCalls } = await startBoard($, on, sessions, Date.UTC(2026, 9, 25, 15, 0, 0), false)
  // A session in the repository, a slice session among them, gets no pane and runs no git until asked.
  expect(opened).toEqual([])
  expect(gitCalls).toEqual([])
  await submit($, '/slice 12')
  await submit($, 'fix the tests')
  expect(opened).toEqual([])
  await submit($, '/slice status')
  expect(opened).toEqual(['slice-board'])
  expect(gitCalls.some(args => args.startsWith('worktree list'))).toBe(true)
})
