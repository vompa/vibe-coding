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
  { nr: '03', slug: 'app-c', name: 'C', round: 'R01', deps: '–' },
  { nr: '04', slug: 'app-d', name: 'D', round: 'R01', deps: '03' },
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
  { sessionId: 'local_c', title: 'Slice 03 – C (R01)', cwd: 'C:\\repo', link: 'claude://claude.ai/epitaxy/local_c', isRunning: false, isArchived: false },
  { sessionId: 'local_old', title: 'Slice 03', cwd: 'C:\\elsewhere', link: 'claude://claude.ai/epitaxy/local_old', isRunning: true, isArchived: false },
]

test('the pane shows the round as a legend with groups, opens a session and starts the ready slices', async ($, on) => {
  on('command.register', () => ({ value: { command: 'slices' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('clock.now', () => ({ value: Date.UTC(2026, 9, 25, 10, 0, 0) }))
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
    result: [{ type: 'text', text: JSON.stringify(sessions) }],
    text: JSON.stringify(sessions),
  }))
  const startedSessions: { title?: string; prompt?: string; use_worktree?: boolean }[] = []
  on('tool.call', { tool: 'mcp__ccd_session__start_session' }, (_, e) => {
    startedSessions.push(e as (typeof startedSessions)[number])
    return { result: [{ type: 'text', text: 'Started.' }], text: 'Started.' }
  })
  on('session.start', (_, e) => ({ cwd: e.cwd }))

  await $.session.start({ cwd: ROOT, surface: 'desktop', isInteractive: true })
  // One listing of the slice branches per refresh, not one call per slice.
  expect(gitCalls.filter(args => args.startsWith('branch --list')).length).toBe(1)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /^25 % done$/ }))?.text).toBe('25 % done')
    expect((await ui.find({ type: 'Text', text: /R01/ }))?.text).toBe('1 / 4 · R01')
    // In progress is open by default, with the slice's step and share; the other groups are folded.
    expect((await ui.find({ type: 'Text', text: /app-c/ }))?.text).toBe('● 03 app-c')
    expect((await ui.find({ type: 'Text', text: /Green/ }))?.text).toBe('Green · 40 %')
    expect(await ui.find({ type: 'Text', text: /B ready/ })).toBeUndefined()
    expect(await ui.find({ type: 'Text', text: /other round/ })).toBeUndefined()
    shown.length = 0
    await ui.press({ key: 'open-03' })
    expect(shown).toEqual(['local_c'])
    // Unfolding a group lists its slices.
    await ui.press({ key: 'toggle-blocked' })
    expect((await ui.find({ type: 'Text', text: /app-d/ }))?.text).toBe('04 app-d')
    expect((await ui.find({ type: 'Text', text: /← 03/ }))?.text).toBe('← 03')
    await ui.press({ key: 'toggle-blocked' })
    expect(await ui.find({ type: 'Text', text: /app-d/ })).toBeUndefined()
    await ui.unmount()
  }

  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /slots free/ }))?.text).toBe('3 of 4 slots free')
  await ui.press({ key: 'start-ready' })
  expect(startedSessions.map(one => one.title)).toEqual(['Slice 02 – B ready (R01)'])
  expect(startedSessions[0]?.prompt?.startsWith('/slice 02\n')).toBe(true)
  expect(startedSessions[0]).toMatchObject({ use_worktree: false })
  await ui.press({ key: 'toggle-ready' })
  expect((await ui.find({ type: 'Text', text: /^starting$/ }))?.text).toBe('starting')
  expect(await ui.find({ type: 'Button', text: /Start/ })).toBeUndefined()
  await ui.unmount()
})
