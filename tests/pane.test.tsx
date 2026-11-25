import type { On } from 'claude-code'
import { expect, test } from 'claude-code/testing'

const PANE = {
  plugin: 'agent-inbox',
  component: 'Pane',
  requestId: 'agent-inbox',
  props: {
    title: 'Inbox',
    isFocused: false,
    bodyColumns: 56,
    placement: 'dock',
    scroll: { offset: 0, bodyRows: 40 },
    view: {},
  },
} as const

const row = (over: Record<string, unknown>) =>
  JSON.stringify({
    session_id: 'abc',
    host_session_id: 'local_x',
    cwd: '/p/Demo',
    project: 'Demo',
    title: 'Demo session',
    kind: 'permission',
    summary: 'Bash: rm -rf x',
    tool: 'Bash',
    ts_ms: 1000,
    ts: '',
    entrypoint: 'claude-desktop',
    pid: 1,
    link: 'claude://claude.ai/epitaxy/local_x',
    ...over,
  })

const FILE =
  [
    row({}),
    row({ session_id: 'def', host_session_id: '', link: '', cwd: '/p/Other', project: 'Other', title: 'Other', kind: 'idle', summary: '', ts_ms: 500 }),
    row({ session_id: 'ghi', kind: 'question', tool: 'ExitPlanMode', summary: '', ts_ms: 2000 }),
    row({ session_id: 'self-id', title: 'Me', kind: 'idle' }),
    'not json',
  ].join('\n') + '\n'

const RUN = { command: 'inbox', args: '', origin: { kind: 'composer' }, presentation: { isFullscreen: true, columns: 120 } } as const

const seed = (on: On, text: string, lang = '') => {
  on('env.get', (_, e) => ({ value: e.name === 'HOME' ? '/home/u' : e.name === 'LANG' ? lang : undefined }))
  on('command.register', () => ({ value: { command: 'inbox' } }))
  on('ui.open', () => ({ value: { isPlaced: true } }))
  on('session.id', () => ({ value: 'self-id' }))
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('fs.exists', () => ({ value: text !== '' }))
  on('fs.stat', () => ({ value: { kind: 'file', size: text.length, mtimeMs: 5, isLink: false } }))
  on('fs.read', () => ({ value: text }))
}

test('lists waiting sessions by project, oldest first, own session hidden (English via LANG)', async ($, on) => {
  seed(on, FILE, 'en_US.UTF-8')
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(RUN)

  for (const surface of ['terminal', 'desktop'] as const) {
    const ui = await $.ui.mount({ ...PANE, surface })
    expect((await ui.find({ type: 'Text', text: /3 sessions waiting/ }))?.text).toBe('3 sessions waiting')
    expect(await ui.find({ key: 'go:abc' })).toBeDefined()
    expect(await ui.find({ key: 'open:abc' })).toBeDefined()
    expect(await ui.find({ key: 'go:def' })).toBeDefined()
    expect(await ui.find({ key: 'open:def' })).toBeUndefined()
    expect(await ui.find({ key: 'go:self-id' })).toBeUndefined()
    expect((await ui.find({ type: 'Text', text: /Bash: rm -rf x/ }))?.text).toBe('Bash: rm -rf x')
    expect((await ui.find({ type: 'Text', text: /plan approval/ }))?.text).toBe('Waiting for plan approval')
    expect((await ui.find({ type: 'Text', text: /Turn finished/ }))?.text).toBe('Turn finished, waiting for input')
    await ui.unmount()
  }
})

test('the language option wins over the locale', { options: { language: 'tr' } }, async ($, on) => {
  seed(on, FILE, 'en_US.UTF-8')
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(RUN)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /3 oturum bekliyor/ }))?.text).toBe('3 oturum bekliyor')
  expect((await ui.find({ type: 'Text', text: /Plan onayı/ }))?.text).toBe('Plan onayı bekliyor')
  await ui.unmount()
})

test('an empty inbox says so', async ($, on) => {
  seed(on, '', 'de_DE.UTF-8')
  await $.session.start({ cwd: '/', surface: 'desktop', isInteractive: true })
  await $.command.run(RUN)
  const ui = await $.ui.mount({ ...PANE, surface: 'desktop' })
  expect((await ui.find({ type: 'Text', text: /Nichts wartet/ }))?.text).toBe('Nichts wartet')
  await ui.unmount()
})
