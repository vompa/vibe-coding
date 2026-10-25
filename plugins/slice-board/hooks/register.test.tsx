import { expect, test } from 'claude-code/testing'

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

/** Stands for the engine: the repository above on disk and in git, the app's sessions as given. */
async function startBoard($: Board$, on: BoardOn, appSessions: typeof sessions, now = Date.UTC(2026, 9, 25, 10, 0, 0)) {
  on('command.register', () => ({ value: { command: 'slices' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('clock.now', () => ({ value: now }))
  on('clock.every', () => ({ value: undefined }))
  on('ui.log', () => ({ value: undefined }))
  on('ui.toast', () => ({ value: undefined }))
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
  return { gitCalls, shown, filled, box }
}

test('the pane shows the round as a legend with groups, opens a session and starts the ready slices', async ($, on) => {
  const { gitCalls, shown, filled, box } = await startBoard($, on, sessions)
  // One listing of the slice branches per refresh, not one call per slice.
  expect(gitCalls.filter(args => args.startsWith('branch --list')).length).toBe(1)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /^Round R01$/ }))?.text).toBe('Round R01')
    expect((await ui.find({ type: 'Text', text: /done$/ }))?.text).toBe('1 / 4 done')
    // The bar is one line high and carries each group's share inside its segment.
    expect((await ui.find({ type: 'Text', text: /^25 %$/ }))?.text).toBe('25 %')
    // In progress is open by default, with the slice's step and share; the other groups are folded.
    expect((await ui.find({ type: 'Text', text: /app-c/, in: 'name-03' }))?.text).toBe('03 app-c')
    expect((await ui.find({ type: 'Text', text: /Green ·/ }))?.text).toBe('Green · 40 %')
    expect(await ui.find({ type: 'Text', text: /B ready/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /other round/ })).toBeUndefined()
    shown.length = 0
    await ui.press({ key: 'open-03' })
    expect(shown).toEqual(['local_c'])
    // Unfolding a group lists its slices.
    await ui.press({ key: 'toggle-blocked' })
    expect((await ui.find({ type: 'Text', text: /app-d/, in: 'name-04' }))?.text).toBe('04 app-d')
    expect((await ui.find({ type: 'Text', text: /← 03/ }))?.text).toBe('← 03')
    await ui.pointer({ type: 'enter', x: 1, y: 0, in: 'name-04' })
    await ui.advance(700)
    expect((await ui.find({ type: 'Text', text: /^D follows C\.$/, in: 'name-04' }))?.text).toBe('D follows C.')
    expect((await ui.find({ type: 'Text', text: /^Waits for/, in: 'name-04' }))?.text).toBe('Waits for 03 C in the app · W7')
    await ui.pointer({ type: 'leave', x: 1, y: 0, in: 'name-04' })
    await ui.press({ key: 'toggle-blocked' })
    expect(await ui.find({ key: 'name-04' })).toBeUndefined()
    await ui.unmount()
  }

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /slots free/ }))?.text).toBe('3 of 4 slots free')
  // Start writes a request into the prompt box instead of starting sessions itself; Enter makes it the person's message.
  await ui.press({ key: 'start-ready' })
  expect(filled).toHaveLength(1)
  expect(box.text).toMatch(/^Start one separate session per slice of round R01 for: 02 B ready\. /)
  expect(box.text).toContain('work/session-hints.md')
  // A draft the person typed stays; the request comes after it.
  box.text = 'my draft'
  await ui.press({ key: 'toggle-ready' })
  await ui.press({ key: 'start-02' })
  expect(filled[1]?.mode).toBe('append')
  expect(box.text.startsWith('my draft\nStart one separate session')).toBe(true)
  await ui.unmount()
})

test('details appear after the pointer rests on a name, go when it leaves, and stay after a click', async ($, on) => {
  await startBoard($, on, sessions, Date.UTC(2026, 9, 25, 13, 0, 0))
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
    // Details appear after the pointer rests on the name for a moment, not at once, and go when it leaves.
    await ui.pointer({ type: 'enter', x: 1, y: 0, in: 'name-03' })
    await ui.advance(300)
    expect(await ui.find({ type: 'Text', text: /^Messages of C/, in: 'name-03' })).toBeUndefined()
    await ui.advance(400)
    expect((await ui.find({ type: 'Text', text: /^Messages of C/, in: 'name-03' }))?.text).toBe('Messages of C are announced.')
    expect((await ui.find({ type: 'Text', text: /^✓ Plan/, in: 'name-03' }))?.text).toBe('✓ Plan  ✓ Red  ▸ Green  · Checks  · Commit · idle · 2 commits · W5, W9')
    await ui.pointer({ type: 'leave', x: 1, y: 0, in: 'name-03' })
    expect(await ui.find({ type: 'Text', text: /^Messages of C/, in: 'name-03' })).toBeUndefined()
    // A click keeps them open after the pointer leaves; a second click closes them.
    await ui.pointer({ type: 'down', x: 1, y: 0, button: 'left', in: 'name-03' })
    await ui.pointer({ type: 'leave', x: 1, y: 0, in: 'name-03' })
    expect((await ui.find({ type: 'Text', text: /^Messages of C/, in: 'name-03' }))?.text).toBe('Messages of C are announced.')
    await ui.pointer({ type: 'down', x: 1, y: 0, button: 'left', in: 'name-03' })
    expect(await ui.find({ type: 'Text', text: /^Messages of C/, in: 'name-03' })).toBeUndefined()
  await ui.unmount()
})

test('a slice whose session runs in this repository takes a slot in every pane, before its branch exists', async ($, on) => {
  const started = { sessionId: 'local_b', title: 'Slice 02 – B ready (R01)', cwd: ROOT, link: 'claude://claude.ai/epitaxy/local_b', isRunning: true, isArchived: false }
  // A later time: the plugin keeps its listing of the app's sessions for 30 s, also across tests.
  await startBoard($, on, [...sessions, started], Date.UTC(2026, 9, 25, 11, 0, 0))
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /web-b/, in: 'name-02' }))?.text).toBe('02 web-b')
  expect(await ui.find({ type: 'Text', text: /slots free/ })).toBeUndefined()
  expect(await ui.find({ type: 'Button', text: /Start/ })).toBeUndefined()
  await ui.unmount()
})

test('without a Client (VS Code) a click on the name opens and closes the details', async ($, on) => {
  await startBoard($, on, sessions, Date.UTC(2026, 9, 25, 12, 0, 0))
  const ui = await $.ui.mount({ ...PANE, surface: 'vscode' })
  expect((await ui.find({ type: 'Button', text: /app-c/ }))?.text).toBe('03 app-c')
  expect(await ui.find({ type: 'Text', text: /^Messages of C/ })).toBeUndefined()
  await ui.press({ key: 'name-03' })
  expect((await ui.find({ type: 'Text', text: /^Messages of C/ }))?.text).toBe('Messages of C are announced.')
  await ui.press({ key: 'name-03' })
  expect(await ui.find({ type: 'Text', text: /^Messages of C/ })).toBeUndefined()
  await ui.unmount()
})
