import { describe, expect, test } from 'bun:test';
import {
  type AppAction,
  type AppState,
  initialAppState,
  keyCommand,
  reduceApp,
} from '../../../src/ui/app/state.ts';
import { agentItems } from '../../../src/ui/prompt/commands.ts';
import type { PastedImage } from '../../../src/ui/prompt/images.ts';
import {
  commandMenu,
  fileFinder,
  heldContext,
  runningShell,
} from '../../../src/ui/prompt/state.ts';
import { startingVim, type Vim } from '../../../src/ui/prompt/vim.ts';
import { after, busy, escape, plain, ready } from '../app/states.ts';

test("a monitor's message reported again takes its own place in the queue", () => {
  const from = { name: 'log', monitor: { id: 'm1' } };
  const queued = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    { type: 'queued', turnId: 't2', text: 'first', from },
    { type: 'queued', turnId: 't3', text: 'later' },
    { type: 'queued', turnId: 't2', text: 'first\nsecond', from },
  );

  expect(queued.queue).toStrictEqual([
    { turnId: 't2', text: 'first\nsecond', from },
    { turnId: 't3', text: 'later' },
  ]);
});

test('queued prompts wait in order and leave as their turns start', () => {
  const queued = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    { type: 'queued', turnId: 't2', text: 'second' },
    { type: 'queued', turnId: 't3', text: 'third' },
  );

  expect(queued.queue).toStrictEqual([
    { turnId: 't2', text: 'second' },
    { turnId: 't3', text: 'third' },
  ]);

  const next = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    { type: 'queued', turnId: 't2', text: 'second' },
    { type: 'queued', turnId: 't3', text: 'third' },
    {
      type: 'result',
      turnId: 't1',
      result: { status: 'completed', stopReason: 'end_turn' },
    },
    { type: 'prompt', turnId: 't2', text: 'second', at: 1 },
  );

  expect(next.queue).toStrictEqual([{ turnId: 't3', text: 'third' }]);
  expect(next.transcript.turn.status).toStrictEqual('working');
  expect(reduceApp(queued, { type: 'queue_withdrawn' }).queue).toStrictEqual(
    [],
  );
  // A new session starts with none.
  expect(reduceApp(queued, { type: 'cleared' }).queue).toStrictEqual([]);
});

const down = { ctrl: false, escape: false, downArrow: true };
const up = { ctrl: false, escape: false, upArrow: true };
const tab = { ctrl: false, escape: false, tab: true };
const withCommands = reduceApp(ready, {
  type: 'commands',
  commands: [
    { name: 'greet', description: 'Say hello' },
    {
      name: 'echo',
      description: '',
    },
  ],
});

const menuNames = (state: AppState, draft: string) =>
  commandMenu(state, draft)?.items.map(({ name }) => name);

test('/new and a space opens the list of agents the window can start', () => {
  const withAgents = {
    ...withCommands,
    agents: agentItems(['fake', 'mine'], []),
  };

  expect(menuNames(withAgents, '/new ')).toStrictEqual(['fake', 'mine']);
  expect(menuNames(withAgents, '/new mi')).toStrictEqual(['mine']);
  expect(commandMenu(withAgents, '/new zz')).toStrictEqual(undefined);
  expect(commandMenu(withAgents, '/new mine ')).toStrictEqual(undefined);
  // A window given no agents offers none.
  expect(commandMenu(withCommands, '/new ')).toStrictEqual(undefined);
});

test("a / opens the list of chord's commands and the agent's", () => {
  expect(withCommands.transcript.commands.length).toStrictEqual(2);
  expect(menuNames(withCommands, '/')).toStrictEqual([
    'clear',
    'config',
    'context',
    'cost',
    'echo',
    'exit',
    'greet',
    'help',
    'mcp',
    'model',
    'new',
    'resume',
    'status',
    'team',
    'theme',
    'vim',
  ]);
  expect(menuNames(withCommands, '/gr')).toStrictEqual(['greet']);
  // Nothing to show when nothing matches, or once arguments start.
  expect(commandMenu(withCommands, '/zz')).toStrictEqual(undefined);
  expect(commandMenu(withCommands, '/greet ')).toStrictEqual(undefined);
  expect(commandMenu(withCommands, '')).toStrictEqual(undefined);
  // chord's own are there before the agent has said anything.
  expect(menuNames(initialAppState, '/')).toStrictEqual([
    'clear',
    'config',
    'context',
    'cost',
    'exit',
    'help',
    'mcp',
    'model',
    'new',
    'resume',
    'status',
    'team',
    'theme',
    'vim',
  ]);
});

test('the list is put away while a permission is asked or closing', () => {
  const asked = after(
    { type: 'connected', sessionId: 'session-1' },
    {
      type: 'prompt',
      turnId: 't1',
      text: 'hi',
      at: 0,
    },
    {
      type: 'permission_requested',
      turnId: 't1',
      permission: { id: 'p1', options: [] },
    },
  );

  expect(commandMenu(asked, '/')).toStrictEqual(undefined);
  expect(commandMenu(reduceApp(ready, { type: 'closing' }), '/')).toStrictEqual(
    undefined,
  );
});

test('↑ and ↓ move the highlight round the list, an edit resets it', () => {
  const move = (state: AppState, step: 1 | -1) =>
    reduceApp(state, { type: 'menu_moved', step, count: 5, rows: 3 });

  const second = move(withCommands, 1);

  expect(commandMenu(second, '/')?.highlighted).toStrictEqual(1);
  expect(commandMenu(move(withCommands, -1), '/')?.highlighted).toStrictEqual(
    4,
  );
  // The window follows the highlight to the end.
  expect(move(move(move(second, 1), 1), 1).menu.top).toStrictEqual(2);
  // A shorter list keeps the highlight on its last item.
  expect(
    commandMenu(move(move(second, 1), 1), '/gr')?.highlighted,
  ).toStrictEqual(0);
  expect(
    reduceApp(second, { type: 'draft_edited' }).menu.highlighted,
  ).toStrictEqual(0);
  expect(reduceApp(withCommands, { type: 'draft_edited' })).toStrictEqual(
    withCommands,
  );
});

test("the list's keys are its own while it is open", () => {
  expect(keyCommand('', down, withCommands, '/')).toStrictEqual('menu_down');
  expect(keyCommand('', up, withCommands, '/')).toStrictEqual('menu_up');
  expect(keyCommand('', tab, withCommands, '/g')).toStrictEqual(
    'complete_command',
  );
  expect(keyCommand('', escape, withCommands, '/')).toStrictEqual('close_menu');
  // Shut, the arrows are history's and Esc is what it was.
  expect(keyCommand('', down, withCommands, '/greet ')).toStrictEqual(
    undefined,
  );
  expect(keyCommand('', up, withCommands, '')).toStrictEqual(undefined);
  expect(keyCommand('', tab, withCommands, '')).toStrictEqual(undefined);

  const shut = reduceApp(withCommands, { type: 'menu_dismissed' });

  expect(commandMenu(shut, '/')).toStrictEqual(undefined);
  expect(keyCommand('', up, shut, '/')).toStrictEqual(undefined);
  expect(
    commandMenu(reduceApp(shut, { type: 'draft_edited' }), '/')?.items.length,
  ).toStrictEqual(16);
});

test('Esc closes the list before it interrupts the turn', () => {
  const working = reduceApp(withCommands, {
    type: 'prompt',
    turnId: 't1',
    text: 'hi',
    at: 0,
  });

  expect(keyCommand('', escape, working, '/')).toStrictEqual('close_menu');
  expect(
    keyCommand('', escape, reduceApp(working, { type: 'menu_dismissed' }), '/'),
  ).toStrictEqual('interrupt');
});

const withFiles = reduceApp(ready, {
  type: 'files_listed',
  files: ['README.md', 'src/main.ts', 'src/ui/state.ts', 'tests/state_test.ts'],
});

const finderFiles = (state: AppState, draft: string) =>
  fileFinder(state, draft, [0, draft.length])?.files;

describe('CHD-398 finder cache invalidation', () => {
  test('a new walk replaces matching paths while the query stays unchanged', () => {
    const old = matchedIn(
      reduceApp(ready, {
        type: 'files_listed',
        files: ['old/state.ts', 'README.md'],
      }),
      'state',
      ['old/state.ts'],
    );

    expect(finderFiles(old, '@state')).toStrictEqual(['old/state.ts']);

    const refreshed = reduceApp(old, {
      type: 'files_listed',
      files: ['new/state.ts', 'README.md'],
    });

    // A new walk shows its own first files until its async match arrives.
    expect(fileFinder(refreshed, '@state', [0, 6])).toMatchObject({
      files: ['new/state.ts', 'README.md'],
      pending: true,
    });
    expect(
      reduceApp(refreshed, {
        type: 'files_matched',
        files: old.files!,
        query: 'state',
        matched: ['old/state.ts'],
      }),
    ).toBe(refreshed);

    const matched = matchedIn(refreshed, 'state', ['new/state.ts']);

    expect(finderFiles(matched, '@state')).toStrictEqual(['new/state.ts']);
    expect(fileFinder(matched, '@state', [0, 6])?.pending).toBe(false);
    expect(finderFiles(old, '@state')).toStrictEqual(['old/state.ts']);
  });

  test('empty and missing matches do not survive a new walk or query', () => {
    const before = reduceApp(ready, { type: 'files_listed', files: [] });

    expect(finderFiles(before, '@state')).toBeUndefined();

    const listed = reduceApp(before, {
      type: 'files_listed',
      files: ['state.ts', 'README.md'],
    });
    const found = matchedIn(listed, 'state', ['state.ts']);

    expect(finderFiles(found, '@state')).toStrictEqual(['state.ts']);
    // While the next query runs, the previous result stays visible.
    expect(fileFinder(found, '@missing', [0, 8])).toMatchObject({
      files: ['state.ts'],
      pending: true,
    });

    const missing = matchedIn(found, 'missing', []);

    expect(finderFiles(missing, '@missing')).toBeUndefined();
    expect(finderFiles(missing, '@')).toStrictEqual(['state.ts', 'README.md']);
    expect(
      finderFiles(matchedIn(missing, 'state', ['state.ts']), '@state'),
    ).toStrictEqual(['state.ts']);
    expect(
      finderFiles(reduceApp(found, { type: 'files_listed', files: [] }), '@'),
    ).toBeUndefined();
  });

  test('interleaved sessions keep their own paths for the same query', () => {
    const first = reduceApp(ready, {
      type: 'files_listed',
      files: ['first/state.ts'],
    });
    const second = reduceApp(ready, {
      type: 'files_listed',
      files: ['second/state.ts'],
    });

    for (let call = 0; call < 3; call++) {
      expect(finderFiles(first, '@state')).toStrictEqual(['first/state.ts']);
      expect(finderFiles(second, '@state')).toStrictEqual(['second/state.ts']);
    }
  });
});

/** `state` once the match for `query` came back with `matched`. */
const matchedIn = (state: AppState, query: string, matched: string[]) =>
  reduceApp(state, {
    type: 'files_matched',
    files: state.files!,
    query,
    matched,
  });

test('an @ opens the finder on the files, and typing narrows it once the match comes back', () => {
  expect(finderFiles(withFiles, 'see @')).toStrictEqual(withFiles.files);

  // Typed, not yet matched: the last list stays, and the finder waits.
  const typed = fileFinder(withFiles, 'see @stt', [0, 8]);

  expect(typed?.files).toStrictEqual(withFiles.files);
  expect(typed?.pending).toStrictEqual(true);
  expect(typed?.searching).toStrictEqual(false);
  expect(typed?.mention).toStrictEqual({ query: 'stt', line: 0, column: 4 });

  const narrowed = matchedIn(withFiles, 'stt', [
    'src/ui/state.ts',
    'tests/state_test.ts',
  ]);

  expect(fileFinder(narrowed, 'see @stt', [0, 8])).toMatchObject({
    files: ['src/ui/state.ts', 'tests/state_test.ts'],
    highlighted: 0,
    pending: false,
  });
  // Nothing to show when nothing matched, before the walk, or past a space.
  expect(
    fileFinder(matchedIn(withFiles, 'zzz', []), '@zzz', [0, 4]),
  ).toStrictEqual(undefined);
  expect(fileFinder(ready, '@', [0, 1])).toStrictEqual(undefined);
  expect(fileFinder(withFiles, '@README.md ', [0, 11])).toStrictEqual(
    undefined,
  );
  expect(
    fileFinder(reduceApp(withFiles, { type: 'closing' }), '@', [0, 1]),
  ).toStrictEqual(undefined);
});

test('a match that runs long says so in place of the last row; with nothing on screen, alone', () => {
  const slow = reduceApp(withFiles, { type: 'match_slow', query: 'stt' });

  expect(fileFinder(slow, '@stt', [0, 4])).toMatchObject({
    files: withFiles.files,
    pending: true,
    searching: true,
  });
  // Only its own query's: the next key's match has not run long yet.
  expect(fileFinder(slow, '@sttx', [0, 5])?.searching).toStrictEqual(false);

  // After an empty result the finder is closed, and opens with the marker.
  const empty = matchedIn(withFiles, 'zz', []);

  expect(fileFinder(empty, '@zzz', [0, 4])).toStrictEqual(undefined);
  expect(
    fileFinder(
      reduceApp(empty, { type: 'match_slow', query: 'zzz' }),
      '@zzz',
      [0, 4],
    ),
  ).toMatchObject({ files: [], searching: true });
  // Its result takes the marker away.
  expect(
    fileFinder(matchedIn(slow, 'stt', ['src/ui/state.ts']), '@stt', [0, 4]),
  ).toMatchObject({ files: ['src/ui/state.ts'], searching: false });
});

test("a result for another walk's files is dropped, and an arriving one takes the highlight to its first row", () => {
  const moved = reduceApp(withFiles, {
    type: 'finder_moved',
    step: 1,
    count: 4,
    rows: 6,
  });
  const stale = reduceApp(moved, {
    type: 'files_matched',
    files: ['another', 'walk'],
    query: 'stt',
    matched: ['another'],
  });

  expect(stale).toBe(moved);

  const arrived = matchedIn(moved, 'stt', ['src/ui/state.ts']);

  expect(arrived.finder).toStrictEqual({
    highlighted: 0,
    top: 0,
    dismissed: false,
  });
});

test("the finder's keys are its own while it is open", () => {
  expect(keyCommand('', down, withFiles, '@')).toStrictEqual('finder_down');
  expect(keyCommand('', up, withFiles, '@s')).toStrictEqual('finder_up');
  expect(keyCommand('', tab, withFiles, '@s')).toStrictEqual(
    'complete_mention',
  );
  expect(keyCommand('', escape, withFiles, '@')).toStrictEqual('close_finder');
  // The cursor decides: back before the @, the arrows are history's again.
  expect(keyCommand('', up, withFiles, 'x @s', [0, 1])).toStrictEqual(
    undefined,
  );

  const moved = reduceApp(withFiles, {
    type: 'finder_moved',
    step: 1,
    count: 4,
    rows: 3,
  });

  expect(fileFinder(moved, '@', [0, 1])?.highlighted).toStrictEqual(1);
  expect(
    reduceApp(moved, { type: 'draft_edited' }).finder.highlighted,
  ).toStrictEqual(0);

  const shut = reduceApp(withFiles, { type: 'finder_dismissed' });

  expect(fileFinder(shut, '@', [0, 1])).toStrictEqual(undefined);
  expect(keyCommand('', escape, shut, '@')).toStrictEqual(undefined);
  expect(
    fileFinder(reduceApp(shut, { type: 'draft_edited' }), '@', [0, 1])?.files
      .length,
  ).toStrictEqual(4);
});

test('Esc closes the finder before it interrupts the turn', () => {
  const working = reduceApp(withFiles, {
    type: 'prompt',
    turnId: 't1',
    text: 'hi',
    at: 0,
  });

  expect(keyCommand('', escape, working, '@')).toStrictEqual('close_finder');
  expect(
    keyCommand(
      '',
      escape,
      reduceApp(working, { type: 'finder_dismissed' }),
      '@',
    ),
  ).toStrictEqual('interrupt');
});

const shellStarted: AppAction = {
  type: 'shell_started',
  turnId: 's1',
  command: 'echo hi',
};

test('a finished run is held until a prompt takes it to the agent', () => {
  const ran = after(
    { type: 'connected', sessionId: 'session-1' },
    shellStarted,
    { type: 'shell_output', turnId: 's1', stream: 'stdout', text: 'hi\n' },
  );

  expect(runningShell(ran)).toStrictEqual('s1');
  expect(heldContext(ran)).toStrictEqual('');

  const ended = reduceApp(ran, { type: 'shell_ended', turnId: 's1', code: 0 });

  expect(runningShell(ended)).toStrictEqual(undefined);
  expect(ended.held).toStrictEqual(['s1']);
  expect(heldContext(ended)).toStrictEqual(
    '<bash-input>echo hi</bash-input>\n' +
      '<bash-stdout>hi</bash-stdout><bash-stderr></bash-stderr>',
  );

  const sent = reduceApp(ended, { type: 'context_sent', held: ['s1'] });

  expect(sent.held).toStrictEqual([]);
  // A run that ended after the prompt read what was held stays held.
  expect(
    reduceApp(ended, { type: 'context_sent', held: [] }).held,
  ).toStrictEqual(['s1']);
  expect(heldContext(sent)).toStrictEqual('');
  // A run `/clear` let go is not held for the new session.
  expect(
    reduceApp(reduceApp(ran, { type: 'cleared' }), {
      type: 'shell_ended',
      turnId: 's1',
      code: 0,
    }).held,
  ).toStrictEqual([]);
});

test('a queued prompt taken back by an interrupt holds its output again', () => {
  const ended = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'prompt', turnId: 't1', text: 'slow', at: 0 },
    shellStarted,
    { type: 'shell_ended', turnId: 's1', code: 0 },
  );
  const queued = (
    [
      { type: 'queued', turnId: 't2', text: 'text' },
      { type: 'context_sent', held: ['s1'] },
    ] satisfies AppAction[]
  ).reduce(reduceApp, ended);

  expect(queued.held).toStrictEqual([]);
  expect(queued.queue).toStrictEqual([
    { turnId: 't2', text: 'text', held: ['s1'] },
  ]);

  const later = (
    [
      { type: 'shell_started', turnId: 's2', command: 'pwd' },
      { type: 'shell_ended', turnId: 's2', code: 0 },
    ] satisfies AppAction[]
  ).reduce(reduceApp, queued);
  const withdrawn = reduceApp(later, { type: 'queue_withdrawn' });

  expect(withdrawn.queue).toStrictEqual([]);
  // Oldest first, as they ran.
  expect(withdrawn.held).toStrictEqual(['s1', 's2']);
  // Once its turn starts, the prompt has taken its output for good.
  expect(
    (
      [
        { type: 'prompt', turnId: 't2', text: 'text', at: 1 },
        { type: 'queue_withdrawn' },
      ] satisfies AppAction[]
    ).reduce(reduceApp, queued).held,
  ).toStrictEqual([]);
});

test('backspace on an empty command leaves bash mode, and only then', () => {
  const bash = reduceApp(ready, { type: 'bash_mode', on: true });
  const backspace = { ...plain, backspace: true };

  expect(bash.bash).toStrictEqual(true);
  expect(keyCommand('', backspace, bash, '')).toStrictEqual('leave_bash');
  expect(keyCommand('', backspace, bash, 'ls')).toStrictEqual(undefined);
  expect(keyCommand('', backspace, ready, '')).toStrictEqual(undefined);
  expect(reduceApp(bash, { type: 'bash_mode', on: false }).bash).toStrictEqual(
    false,
  );
});

test('bash mode opens neither the command list nor the file finder', () => {
  const bash = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'files_listed', files: ['README.md'] },
    { type: 'bash_mode', on: true },
  );

  expect(commandMenu(bash, '/')).toStrictEqual(undefined);
  expect(fileFinder(bash, 'cat @', [0, 5])).toStrictEqual(undefined);
});

test('Esc stops a running command before it interrupts the turn', () => {
  const both = reduceApp(busy, shellStarted);
  const escape = { ...plain, escape: true };

  expect(keyCommand('', escape, both, '')).toStrictEqual('stop_shell');
  expect(
    keyCommand(
      '',
      escape,
      reduceApp(both, { type: 'shell_ended', turnId: 's1', stopped: true }),
      '',
    ),
  ).toStrictEqual('interrupt');
});

function pasted(id: number): PastedImage {
  return { id, mediaType: 'image/png', data: `data-${id}`, bytes: 4 };
}

test('the agent says whether it takes images before the session is up', () => {
  expect(initialAppState.takesImages).toStrictEqual(undefined);
  expect(
    after({ type: 'prompt_capabilities', image: true }).takesImages,
  ).toStrictEqual(true);
  expect(
    after({ type: 'prompt_capabilities', image: false }).takesImages,
  ).toStrictEqual(false);
  // A new session says it again.
  expect(
    after({ type: 'prompt_capabilities', image: true }, { type: 'cleared' })
      .takesImages,
  ).toStrictEqual(undefined);
});

test('images go into the draft numbered on, and leave with a prompt', () => {
  const held = after(
    { type: 'images_added', images: [pasted(1)] },
    { type: 'images_added', images: [pasted(2), pasted(3)] },
  );

  expect(held.images.map(({ id }) => id)).toStrictEqual([1, 2, 3]);
  expect(held.imageCount).toStrictEqual(3);

  const sent = reduceApp(held, { type: 'images_sent' });

  expect(sent.images).toStrictEqual([]);
  // The numbers go on, so a recalled prompt's images never share one.
  expect(sent.imageCount).toStrictEqual(3);
  // A recalled image comes back under its number, once.
  expect(
    after(
      { type: 'images_added', images: [pasted(1)] },
      { type: 'images_added', images: [pasted(1)] },
    ).images.length,
  ).toStrictEqual(1);
});

test('a sent prompt leaves the images of a draft typed meanwhile', () => {
  const sent = after(
    { type: 'images_added', images: [pasted(1), pasted(2)] },
    { type: 'images_sent', keeping: 'and [Image #2]' },
  );

  expect(sent.images).toStrictEqual([pasted(2)]);
});

test('the draft keeps its images across /clear', () => {
  const cleared = after(
    { type: 'images_added', images: [pasted(1)] },
    { type: 'cleared' },
  );

  expect(cleared.images).toStrictEqual([pasted(1)]);
  expect(cleared.imageCount).toStrictEqual(1);
});

test('a queued prompt keeps its images, and they come back with it', () => {
  const queued = after(
    { type: 'connected', sessionId: 'session-1' },
    { type: 'prompt', turnId: 't1', text: 'hi', at: 0 },
    { type: 'images_added', images: [pasted(1), pasted(2)] },
    { type: 'queued', turnId: 't2', text: 'look at [Image #2]' },
    { type: 'images_sent' },
  );

  // Only the image its text stands for went with it.
  expect(queued.queue).toStrictEqual([
    { turnId: 't2', text: 'look at [Image #2]', images: [pasted(2)] },
  ]);
  expect(queued.images).toStrictEqual([]);
  expect(reduceApp(queued, { type: 'queue_withdrawn' }).images).toStrictEqual([
    pasted(2),
  ]);
});

test('a paste that found nothing says so until the draft is touched', () => {
  const failed = reduceApp(ready, {
    type: 'paste_failed',
    message: 'No image in the clipboard',
  });

  expect(failed.pasteFailed).toStrictEqual('No image in the clipboard');
  expect(reduceApp(failed, { type: 'draft_edited' }).pasteFailed).toStrictEqual(
    undefined,
  );
  expect(
    reduceApp(failed, { type: 'images_added', images: [pasted(1)] })
      .pasteFailed,
  ).toStrictEqual(undefined);
});

const esc = { ctrl: false, escape: true };
const normal: Vim = { ...startingVim, mode: 'normal', entered: undefined };

/** `state` with vim mode on, in `vim`'s mode. */
function withVim(state: AppState, vim: Vim = startingVim): AppState {
  const actions: AppAction[] = [
    { type: 'vim_toggled', on: true },
    { type: 'vim_changed', vim },
  ];

  return actions.reduce(reduceApp, state);
}

test('in vim mode, Esc goes to normal mode and a second Esc cancels the turn', () => {
  expect(keyCommand('', esc, withVim(busy), 'draft')).toStrictEqual(
    'vim_normal',
  );
  expect(keyCommand('', esc, withVim(busy, normal), 'draft')).toStrictEqual(
    'interrupt',
  );
  expect(keyCommand('', esc, withVim(busy, normal), '')).toStrictEqual(
    'interrupt',
  );
  // Off, Esc cancels at once, as ever.
  expect(keyCommand('', esc, busy, 'draft')).toStrictEqual('interrupt');
});

test('in vim mode, Esc still closes what is open before it changes mode', () => {
  const picking = reduceApp(withVim(ready), { type: 'model_picker_opened' });
  const helped = reduceApp(withVim(ready), { type: 'help_toggled' });

  expect(keyCommand('', esc, picking, '')).toStrictEqual('close_model_picker');
  expect(keyCommand('', esc, helped, '')).toStrictEqual('close_help');
  expect(keyCommand('', esc, withVim(ready), '/he')).toStrictEqual(
    'close_menu',
  );
});

test('Esc on a command half typed in normal mode drops it, not the turn', () => {
  const pending = withVim(busy, { ...normal, pending: ['d'] });

  expect(keyCommand('', esc, pending, 'draft')).toStrictEqual('vim_clear');
});

test("normal mode's keys are vim's, Enter sends, and typing is not", () => {
  const state = withVim(ready, normal);

  expect(keyCommand('w', plain, state, 'draft')).toStrictEqual('vim_key');
  expect(keyCommand('dw', plain, state, 'draft')).toStrictEqual('vim_key');
  expect(
    keyCommand('', { ...plain, return: true }, state, 'draft'),
  ).toStrictEqual('vim_send');
  expect(keyCommand('v', plain, state, 'draft')).toStrictEqual(undefined);
  // In insert mode they are the textarea's.
  expect(keyCommand('w', plain, withVim(ready), 'draft')).toStrictEqual(
    undefined,
  );
  // ? still opens the panel on an empty prompt.
  expect(keyCommand('?', plain, state, '')).toStrictEqual('toggle_help');
});

test('/vim turns vim mode on in insert mode, and off', () => {
  const on = reduceApp(ready, { type: 'vim_toggled', on: true });

  expect(on.vim).toStrictEqual(startingVim);
  expect(reduceApp(on, { type: 'vim_toggled', on: false }).vim).toStrictEqual(
    undefined,
  );
  // A key's change reaches nothing while vim mode is off.
  expect(reduceApp(ready, { type: 'vim_changed', vim: normal })).toStrictEqual(
    ready,
  );
});
