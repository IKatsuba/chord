import { expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { keybindingsFile, loadKeybindings } from '../../../src/settings.ts';
import {
  ACTIONS,
  bound,
  DEFAULT_KEYMAP,
  hintKey,
  keybindingsNotice,
  type Keymap,
  keysOf,
  keystrokeOf,
  layoutKeys,
  parseKeystroke,
  parseSequence,
  readKeybindings,
  sequenceHint,
  sequencePanel,
} from '../../../src/ui/shortcuts/bindings.ts';
import {
  shortcutLine,
  SHORTCUTS,
  shortcuts,
} from '../../../src/ui/shortcuts/keys.ts';
import {
  textareaKeys,
  textareaTakes,
  typedTakenBack,
} from '../../../src/ui/prompt/prompt.ts';
import {
  type AppState,
  initialAppState,
  keyAnswer,
  keyCommand,
  liveChords,
  pendingBindings,
  reduceApp,
  resumeRefusal,
} from '../../../src/ui/app/state.ts';
import type { KeyPress } from '../../../src/ui/shortcuts/state.ts';
import { indicator } from '../../../src/ui/transcript/scroll.ts';
import {
  LEADER_GAP,
  leaderLine,
  leaderWidth,
  STATUS_SEPARATOR,
  statusLine,
  workingLine,
} from '../../../src/ui/status/status.ts';
import { columnCount, inColumns } from '../../../src/ui/shortcuts/keys.ts';
import { shellView } from '../../../src/ui/prompt/bash.ts';
import { emptySearch } from '../../../src/ui/prompt/search.ts';

/** A keybindings file of `blocks`, read. */
function read(...blocks: unknown[]) {
  return readKeybindings(JSON.stringify({ bindings: blocks }));
}

function keys(text: string) {
  const parsed = parseSequence(text);

  assert('keys' in parsed, `${text} does not parse`);

  return parsed.keys;
}

test("a keystroke reads Claude Code's spellings", () => {
  expect(parseKeystroke('ctrl+shift+p')).toStrictEqual({
    keystroke: { key: 'p', ctrl: true, alt: false, shift: true, cmd: false },
  });
  // Names are read whatever their case, and every alias means its key.
  expect(parseKeystroke('Control+K')).toStrictEqual(parseKeystroke('ctrl+k'));
  expect(parseKeystroke('meta+p')).toStrictEqual(parseKeystroke('alt+p'));
  expect(parseKeystroke('option+p')).toStrictEqual(parseKeystroke('alt+p'));
  expect(parseKeystroke('command+k')).toStrictEqual(parseKeystroke('cmd+k'));
  expect(parseKeystroke('esc')).toStrictEqual(parseKeystroke('escape'));
  expect(parseKeystroke('return')).toStrictEqual(parseKeystroke('enter'));
  expect(parseKeystroke('ctrl++')).toStrictEqual({
    keystroke: { key: '+', ctrl: true, alt: false, shift: false, cmd: false },
  });
});

test('a keystroke that is no key says why', () => {
  expect(parseKeystroke('ctl+k')).toStrictEqual({
    problem: '"ctl" is not a modifier',
  });
  expect(parseKeystroke('ctrl+foo')).toStrictEqual({
    problem: '"foo" is not a key',
  });
  expect(parseKeystroke('wheelup')).toStrictEqual({
    problem: 'the wheel always scrolls the transcript and cannot be bound',
  });
  expect(parseSequence('  ')).toStrictEqual({ problem: 'no key' });
});

test('a chord is its keystrokes in order, named back as written', () => {
  const chord = keys('ctrl+x  ctrl+e');

  expect(chord.length).toStrictEqual(2);
  expect(sequenceHint(chord)).toStrictEqual('ctrl+x ctrl+e');
  expect(sequencePanel(chord)).toStrictEqual('ctrl + x ctrl + e');
  expect(sequencePanel(keys('shift+up'))).toStrictEqual('shift + ↑');
  expect(sequenceHint(keys('escape'))).toStrictEqual('esc');
});

test('a key press reads as the keystroke the file names', () => {
  const press = (input: string, key: Partial<KeyPress>) =>
    keystrokeOf(input, { ctrl: false, escape: false, ...key });

  expect(press('g', { ctrl: true })).toStrictEqual(keys('ctrl+g')[0]);
  expect(press('', { tab: true, shift: true })).toStrictEqual(
    keys('shift+tab')[0],
  );
  expect(press('', { return: true, meta: true })).toStrictEqual(
    keys('alt+enter')[0],
  );
  expect(press('G', { shift: true })).toStrictEqual(keys('shift+g')[0]);
  expect(press(' ', {})).toStrictEqual(keys('space')[0]);
  // `?` is shift+/ on most keyboards; the character carries the shift.
  expect(press('?', { shift: true })).toStrictEqual(keys('?')[0]);
  expect(press('', { escape: true, meta: true })).toStrictEqual(
    keys('escape')[0],
  );
  expect(press('k', { super: true })).toStrictEqual(keys('cmd+k')[0]);
  // ctrl+j arrives as the line feed byte, which Ink reports as text.
  expect(press('\n', {})).toStrictEqual(keys('ctrl+j')[0]);
  expect(press('', {})).toStrictEqual(undefined);
});

test('with no file, every action has the keys it had before files', () => {
  expect(readKeybindings('{"bindings": []}').keymap).toStrictEqual(
    DEFAULT_KEYMAP,
  );

  for (const [action, spec] of Object.entries(ACTIONS)) {
    expect(
      keysOf(DEFAULT_KEYMAP, action as keyof typeof ACTIONS).map(sequenceHint),
    ).toStrictEqual(spec.keys.map((key) => sequenceHint(keys(key))));
  }

  // The shortcuts panel is the table it was, line for line.
  expect(shortcuts()).toStrictEqual([...SHORTCUTS]);
  expect(shortcuts(DEFAULT_KEYMAP).map(shortcutLine)).toStrictEqual([
    ...SHORTCUTS.map(shortcutLine),
  ]);
  expect(textareaKeys(DEFAULT_KEYMAP)).toStrictEqual({});
});

test('a binding replaces what its key did in its context, and null takes it away', () => {
  const { keymap, problems } = read({
    context: 'Chat',
    bindings: { enter: null, 'ctrl+s': 'chat:submit', 'ctrl+g': null },
  });

  expect(problems).toStrictEqual([]);
  expect(bound(keymap, 'chat:submit', keys('ctrl+s'))).toBeTruthy();
  expect(!bound(keymap, 'chat:submit', keys('enter'))).toBeTruthy();
  expect(keysOf(keymap, 'chat:externalEditor')).toStrictEqual([]);
  // The textarea sends on Enter no more, and chord sends on ctrl+s.
  expect(textareaKeys(keymap)).toStrictEqual({ Enter: false });

  // A key taken from one action in its own context goes to the new one.
  const moved = read({
    context: 'Chat',
    bindings: { 'ctrl+g': 'chat:imagePaste' },
  });

  expect(moved.problems).toStrictEqual([]);
  expect(bound(moved.keymap, 'chat:imagePaste', keys('ctrl+g'))).toBeTruthy();
  expect(bound(moved.keymap, 'chat:imagePaste', keys('ctrl+v'))).toBeTruthy();
  expect(keysOf(moved.keymap, 'chat:externalEditor')).toStrictEqual([]);
});

test('a key a Global action holds is a conflict, and the rest still applies', () => {
  const { keymap, problems } = read({
    context: 'Chat',
    bindings: { 'ctrl+o': 'chat:externalEditor', 'ctrl+s': 'chat:submit' },
  });

  expect(problems).toStrictEqual([
    'ctrl+o already bound to app:toggleTranscript, not to chat:externalEditor',
  ]);
  expect(bound(keymap, 'app:toggleTranscript', keys('ctrl+o'))).toBeTruthy();
  expect(!bound(keymap, 'chat:externalEditor', keys('ctrl+o'))).toBeTruthy();
  expect(bound(keymap, 'chat:submit', keys('ctrl+s'))).toBeTruthy();
});

test('a key the transcript scrolls on is a conflict in any context', () => {
  const { keymap, problems } = read({
    context: 'Chat',
    bindings: { pageup: 'chat:submit', 'ctrl+s': 'chat:submit' },
  });

  expect(problems).toStrictEqual([
    'pageup already bound to scroll:pageUp, not to chat:submit',
  ]);
  expect(!bound(keymap, 'chat:submit', keys('pageup'))).toBeTruthy();
  expect(bound(keymap, 'chat:submit', keys('ctrl+s'))).toBeTruthy();
  expect(
    keyCommand('', press({ pageUp: true }), ready(keymap), 'hi'),
  ).toStrictEqual('scroll_page_up');
});

test('one key bound twice in a context keeps the first', () => {
  const { keymap, problems } = read(
    { context: 'Chat', bindings: { 'ctrl+s': 'chat:submit' } },
    { context: 'Chat', bindings: { 'Control+S': 'chat:imagePaste' } },
  );

  expect(problems).toStrictEqual([
    'ctrl+s is bound twice in Chat; chat:submit kept',
  ]);
  expect(bound(keymap, 'chat:submit', keys('ctrl+s'))).toBeTruthy();
  expect(!bound(keymap, 'chat:imagePaste', keys('ctrl+s'))).toBeTruthy();
});

test('a key that starts a chord another action has is a conflict', () => {
  const { keymap, problems } = read({
    context: 'Chat',
    bindings: {
      'ctrl+k ctrl+e': 'chat:externalEditor',
      'ctrl+k': 'chat:imagePaste',
    },
  });

  expect(problems).toStrictEqual([
    'ctrl+k overlaps ctrl+k ctrl+e (chat:externalEditor), not bound to chat:imagePaste',
  ]);
  expect(
    bound(keymap, 'chat:externalEditor', keys('ctrl+k ctrl+e')),
  ).toBeTruthy();
});

test('what chord cannot take is named and left out', () => {
  const { keymap, problems } = read(
    { context: 'Transcript', bindings: { k: 'scroll:lineUp' } },
    { bindings: {} },
    { context: 'Chat', bindings: [] },
    {
      context: 'Global',
      bindings: {
        'ctrl+t': 'app:toggleTodos',
        'ctrl+c': 'app:toggleTranscript',
        'ctl+o': 'app:toggleTranscript',
        'ctrl+e': 'chat:externalEditor',
        'ctrl+y': 7,
        'ctrl+r': 'history:search',
      },
    },
  );

  expect(problems).toStrictEqual([
    'unknown context "Transcript", ignored',
    'a block with no "context", ignored',
    'Chat: "bindings" is not an object, ignored',
    'unknown action "app:toggleTodos", ignored',
    'ctrl+c cannot be rebound, ignored',
    '"ctl+o": "ctl" is not a modifier, ignored',
    'chat:externalEditor belongs in Chat, not Global; ignored',
    'ctrl+y: the action is not a name or null, ignored',
  ]);
  expect(keymap).toStrictEqual(DEFAULT_KEYMAP);
});

test('a file that is not a keybindings file counts for nothing', () => {
  expect(readKeybindings('{').keymap).toStrictEqual(DEFAULT_KEYMAP);
  expect(
    readKeybindings('{').problems[0]?.startsWith('not valid JSON'),
  ).toBeTruthy();
  expect(readKeybindings('[]')).toStrictEqual({
    keymap: DEFAULT_KEYMAP,
    problems: ['has no "bindings" list; the file is ignored'],
  });
});

test('the status line says how many problems, then the first', () => {
  expect(keybindingsNotice('keybindings.json', [])).toStrictEqual(undefined);
  expect(keybindingsNotice('keybindings.json', ['one'])).toStrictEqual(
    'keybindings.json: one',
  );
  expect(
    keybindingsNotice('keybindings.json', ['one', 'two', 'three']),
  ).toStrictEqual('keybindings.json: 3 problems · one');
});

test("the keybindings file is chord's, beside its settings", async () => {
  expect(keybindingsFile('/config')).toStrictEqual(
    join('/config', 'chord', 'keybindings.json'),
  );
  expect(keybindingsFile(undefined)).toStrictEqual(undefined);

  const dir = await mkdtemp(join(tmpdir(), 'chord-keys-'));

  try {
    const file = join(dir, 'keybindings.json');

    expect(await loadKeybindings(file)).toStrictEqual({
      keymap: DEFAULT_KEYMAP,
      problems: [],
    });

    await writeFile(
      file,
      JSON.stringify({
        bindings: [
          { context: 'Nope', bindings: {} },
          {
            context: 'Chat',
            bindings: { 'ctrl+s': 'chat:submit' },
          },
        ],
      }),
    );

    const { keymap, problems } = await loadKeybindings(file);

    expect(problems).toStrictEqual([
      {
        file,
        message: 'unknown context "Nope", ignored',
      },
    ]);
    expect(bound(keymap, 'chat:submit', keys('ctrl+s'))).toBeTruthy();
  } finally {
    await rm(dir, { recursive: true });
  }
});

/** The window, ready, on `keymap`. */
function ready(keymap: Keymap): AppState {
  return reduceApp(
    { ...initialAppState, keys: keymap },
    { type: 'connected', sessionId: 'session-1' },
  );
}

const press = (key: Partial<KeyPress> = {}): KeyPress => ({
  ctrl: false,
  escape: false,
  ...key,
});

test('keys follow the file: send, newline, history and the editor', () => {
  const { keymap } = read({
    context: 'Chat',
    bindings: {
      enter: 'chat:newline',
      'ctrl+s': 'chat:submit',
      'ctrl+p': 'history:previous',
      'ctrl+g': null,
      'ctrl+e': 'chat:externalEditor',
    },
  });
  const state = ready(keymap);

  expect(keyCommand('s', press({ ctrl: true }), state, 'hi')).toStrictEqual(
    'submit',
  );
  expect(keyCommand('', press({ return: true }), state, 'hi')).toStrictEqual(
    'newline',
  );
  expect(keyCommand('p', press({ ctrl: true }), state, '')).toStrictEqual(
    'history_older',
  );
  expect(keyCommand('e', press({ ctrl: true }), state, '')).toStrictEqual(
    'open_editor',
  );
  expect(keyCommand('g', press({ ctrl: true }), state, '')).toStrictEqual(
    undefined,
  );
  // The textarea's own keys stay its own: no command for them.
  expect(
    keyCommand('', press({ return: true, shift: true }), state, 'hi'),
  ).toStrictEqual(undefined);
  expect(keyCommand('', press({ upArrow: true }), state, '')).toStrictEqual(
    undefined,
  );
  expect(textareaKeys(keymap)).toStrictEqual({ Enter: false, 'Ctrl+E': false });
});

test('a chord waits for its next key, and a wrong one drops it', () => {
  const { keymap } = read({
    context: 'Chat',
    bindings: { 'ctrl+x ctrl+e': 'chat:externalEditor' },
  });
  const state = ready(keymap);
  const ctrlX = keys('ctrl+x');

  expect(keyCommand('x', press({ ctrl: true }), state, '')).toStrictEqual(
    'key_pending',
  );

  const waiting = reduceApp(state, { type: 'keys_pending', keys: ctrlX });

  expect(keyCommand('e', press({ ctrl: true }), waiting, '')).toStrictEqual(
    'open_editor',
  );
  expect(keyCommand('z', press(), waiting, '')).toStrictEqual('key_dropped');
  expect(
    reduceApp(waiting, { type: 'keys_pending' }).pendingKeys,
  ).toStrictEqual(undefined);
});

test('a chord is waited for only where its context is on screen', () => {
  const { keymap, problems } = read({
    context: 'Help',
    bindings: { 'ctrl+k ctrl+e': 'help:dismiss' },
  });
  const state = ready(keymap);
  const ctrlK = press({ ctrl: true });

  expect(problems).toStrictEqual([]);
  expect(keyCommand('k', ctrlK, state, '')).toStrictEqual(undefined);

  const helped = reduceApp(state, { type: 'help_toggled' });

  expect(keyCommand('k', ctrlK, helped, '')).toStrictEqual('key_pending');
  expect(
    keyCommand(
      'e',
      ctrlK,
      reduceApp(helped, { type: 'keys_pending', keys: keys('ctrl+k') }),
      '',
    ),
  ).toStrictEqual('close_help');
});

test("a chord's first key is not the box's editing key too", () => {
  const { keymap } = read({
    context: 'Chat',
    bindings: { 'ctrl+k ctrl+e': 'chat:externalEditor' },
  });

  expect(
    keyCommand('k', press({ ctrl: true }), ready(keymap), 'abcd', [0, 0]),
  ).toStrictEqual('key_pending');

  const chords = liveChords(ready(keymap), 'abcd', [0, 0]);

  // The textarea would cut the line on ctrl+k before the box let go.
  expect(textareaKeys(keymap, chords)).toStrictEqual({ 'Ctrl+K': false });
  // Its own ctrl+e, which only finishes the chord here, still moves.
  expect(!('Ctrl+E' in textareaKeys(keymap, chords))).toBeTruthy();
});

test("a list's chord holds the box's key only while the list is open", () => {
  const { keymap, problems } = read({
    context: 'Autocomplete',
    bindings: { 'ctrl+k ctrl+e': 'autocomplete:dismiss' },
  });
  const state = ready(keymap);
  const ctrlK = press({ ctrl: true });

  expect(problems).toStrictEqual([]);
  expect(keyCommand('k', ctrlK, state, '/mod', [0, 0])).toStrictEqual(
    'key_pending',
  );
  expect(textareaKeys(keymap, liveChords(state, '/mod', [0, 0]))).toStrictEqual(
    {
      'Ctrl+K': false,
    },
  );
  expect(
    keyCommand(
      'e',
      ctrlK,
      reduceApp(state, { type: 'keys_pending', keys: keys('ctrl+k') }),
      '/mod',
      [0, 0],
    ),
  ).toStrictEqual('close_menu');
  // No list on a plain draft: ctrl+k is the box's line cut.
  expect(keyCommand('k', ctrlK, state, 'abcd', [0, 0])).toStrictEqual(
    undefined,
  );
  expect(textareaKeys(keymap, liveChords(state, 'abcd', [0, 0]))).toStrictEqual(
    {},
  );
});

test('a chord whose action the search line stops is not waited for', () => {
  const { keymap } = read({
    context: 'Chat',
    bindings: { 'ctrl+k ctrl+e': 'chat:externalEditor' },
  });
  const searching = reduceApp(ready(keymap), {
    type: 'searched',
    search: emptySearch,
  });

  // The sessions' chords are the window's, and wait wherever they are.
  const own = (state: AppState) =>
    liveChords(state, '').filter(([first]) => first?.key === 'k');

  expect(own(searching)).toStrictEqual([]);
  expect(keyCommand('k', press({ ctrl: true }), searching, '')).toStrictEqual(
    undefined,
  );
  expect(keyCommand('a', press(), searching, '')).toStrictEqual(undefined);
  expect(own(ready(keymap))).toStrictEqual([keys('ctrl+k ctrl+e')]);
});

test('the line feed ctrl+j sends is taken back unless it breaks the line', () => {
  const lf = press();
  const unbound = read({ context: 'Chat', bindings: { 'ctrl+j': null } });
  const sends = read({
    context: 'Chat',
    bindings: { 'ctrl+j': 'chat:submit' },
  });

  expect(!typedTakenBack('\n', lf, DEFAULT_KEYMAP, false)).toBeTruthy();
  expect(typedTakenBack('\n', lf, unbound.keymap, false)).toBeTruthy();
  expect(keyCommand('\n', lf, ready(unbound.keymap), 'hi')).toStrictEqual(
    undefined,
  );
  expect(typedTakenBack('\n', lf, sends.keymap, true)).toBeTruthy();
  expect(keyCommand('\n', lf, ready(sends.keymap), 'hi')).toStrictEqual(
    'submit',
  );
  // A letter is taken back only when it was one of chord's keys.
  expect(typedTakenBack('?', press(), DEFAULT_KEYMAP, true)).toBeTruthy();
  expect(!typedTakenBack('a', press(), DEFAULT_KEYMAP, false)).toBeTruthy();
});

test('the search line types what a binding gives a letter', () => {
  const { keymap } = read({
    context: 'HistorySearch',
    bindings: { x: 'historySearch:accept' },
  });
  const searching = reduceApp(ready(keymap), {
    type: 'searched',
    search: emptySearch,
  });

  expect(keyCommand('x', press(), searching, '')).toStrictEqual(undefined);
});

/** Every letter of the Russian alphabet, both cases. */
const CYRILLIC = [
  ...Array.from({ length: 32 }, (_, i) => String.fromCharCode(0x430 + i)),
  'ё',
].flatMap((letter) => [letter, letter.toUpperCase()]);

test("a Russian layout's character reads as the US key in its place", () => {
  expect(layoutKeys('ч')).toStrictEqual(['x']);
  expect(layoutKeys('Ч')).toStrictEqual(['X']);
  expect(layoutKeys('р')).toStrictEqual(['h']);
  expect(layoutKeys('ж')).toStrictEqual([';']);
  expect(layoutKeys('Ж')).toStrictEqual([':']);
  expect(layoutKeys('б')).toStrictEqual([',']);
  expect(layoutKeys('№')).toStrictEqual(['#']);
  // Russian – PC has ё on the backquote key, Apple's Russian on backslash.
  expect(layoutKeys('ё')).toStrictEqual(['`', '\\']);
  expect(layoutKeys('Ё')).toStrictEqual(['~', '|']);

  for (const letter of CYRILLIC) {
    expect(layoutKeys(letter).length > 0, letter).toStrictEqual(true);
  }

  // What a US layout types itself is never read as another key: `,` is
  // where `?` is on Russian – PC, and is also a US comma.
  for (const character of ['x', 'X', ',', '.', '?', '/', ';', '"', '1']) {
    expect(layoutKeys(character), character).toStrictEqual([]);
  }

  expect(layoutKeys('чс')).toStrictEqual([]);
  expect(layoutKeys('')).toStrictEqual([]);
});

test('ctrl and a Cyrillic letter is ctrl and the US letter in its place', () => {
  const state = ready(DEFAULT_KEYMAP);
  const waiting = reduceApp(state, {
    type: 'keys_pending',
    keys: keys('ctrl+x'),
  });

  expect(keyCommand('ч', press({ ctrl: true }), state, '')).toStrictEqual(
    'key_pending',
  );
  expect(keyAnswer('ч', press({ ctrl: true }), state, '').input).toStrictEqual(
    'x',
  );
  // The control byte is what most terminals send for it; it stays ctrl+x.
  expect(keyCommand('x', press({ ctrl: true }), state, '')).toStrictEqual(
    'key_pending',
  );
  expect(keyCommand('с', press(), waiting, '')).toStrictEqual('new_session');
  expect(keyCommand('т', press({ ctrl: true }), waiting, '')).toStrictEqual(
    'next_session',
  );
  expect(keyCommand('л', press(), waiting, '')).toStrictEqual('close_session');
  expect(keyCommand('o', press(), waiting, '')).toStrictEqual('key_dropped');
  expect(keyCommand('щ', press(), waiting, '')).toStrictEqual('key_dropped');
  expect(keyCommand('к', press({ ctrl: true }), state, '')).toStrictEqual(
    'search_history',
  );

  // alt and a Cyrillic letter the same way, where alt is bound.
  const alt = read({
    context: 'Chat',
    bindings: { 'alt+g': 'chat:externalEditor' },
  });

  expect(
    keyCommand('п', press({ meta: true }), ready(alt.keymap), ''),
  ).toStrictEqual('open_editor');
});

test('a Cyrillic key bound in the file is its own, not the US key in its place', () => {
  const { keymap } = read({
    context: 'Global',
    bindings: {
      // Cyrillic с, where `ctrl+x c` is a new session.
      'ctrl+x с': 'session:attention',
      'ctrl+x z': 'session:close',
    },
  });
  const waiting = reduceApp(ready(keymap), {
    type: 'keys_pending',
    keys: keys('ctrl+x'),
  });

  expect(keyCommand('с', press(), waiting, '')).toStrictEqual('attend_session');
  expect(keyCommand('c', press(), waiting, '')).toStrictEqual('new_session');
  // The file's own US keys are found through a Russian layout too.
  expect(keyCommand('я', press(), waiting, '')).toStrictEqual('close_session');
  expect(keyAnswer('с', press(), waiting, '').input).toStrictEqual('с');
});

test('a press is its own key, then the base-layout key, then the table', () => {
  const ctrl = (base?: string) =>
    press({ ctrl: true, ...(base === undefined ? {} : { base }) });
  const own = read({
    context: 'Chat',
    bindings: { 'ctrl+ч': 'chat:externalEditor' },
  });
  // A layout of the person's own that puts ч where a US layout has b, which
  // the Russian table cannot know.
  const elsewhere = read({
    context: 'Chat',
    bindings: { 'ctrl+b': 'chat:externalEditor' },
  });
  const state = ready(DEFAULT_KEYMAP);

  // A key bound as it is pressed is its own, whatever its base key.
  expect(keyAnswer('ч', ctrl('x'), ready(own.keymap), '')).toStrictEqual({
    command: 'open_editor',
    input: 'ч',
  });
  // The base-layout key comes before the table's guess.
  expect(keyAnswer('ч', ctrl('b'), ready(elsewhere.keymap), '')).toStrictEqual({
    command: 'open_editor',
    input: 'b',
  });
  // With no base key, or one bound to nothing, the table answers.
  expect(keyAnswer('ч', ctrl(), state, '')).toStrictEqual({
    command: 'key_pending',
    input: 'x',
  });
  expect(keyAnswer('ч', ctrl('q'), state, '')).toStrictEqual({
    command: 'key_pending',
    input: 'x',
  });
  // A layout the table has no row for is reached through its base key alone.
  expect(keyAnswer('χ', ctrl('x'), state, '')).toStrictEqual({
    command: 'key_pending',
    input: 'x',
  });
  expect(keyAnswer('χ', ctrl(), state, '')).toStrictEqual({
    command: undefined,
    input: 'χ',
  });
  expect(keyCommand('ρ', ctrl('r'), state, '')).toStrictEqual('search_history');
});

test("the key of ? on another layout is ?'s, on an empty prompt only", () => {
  // Russian – PC's comma, with shift on the key where US has ?.
  const comma = press({ shift: true, base: '?' });
  const state = ready(DEFAULT_KEYMAP);

  expect(keyAnswer(',', comma, state, '')).toStrictEqual({
    command: 'toggle_help',
    input: '?',
  });
  // Past a draft ? is text, and so the comma stays the press's own.
  expect(keyAnswer(',', comma, state, 'ч')).toStrictEqual({
    command: undefined,
    input: ',',
  });
  // With no base key the table never guesses at punctuation.
  expect(keyAnswer(',', press({ shift: true }), state, '')).toStrictEqual({
    command: undefined,
    input: ',',
  });

  // The comma bound as it is pressed is its own, whatever its base key.
  const own = read({ context: 'Chat', bindings: { ',': 'help:toggle' } });
  const rebound = ready(own.keymap);

  expect(keyCommand(',', comma, rebound, '')).toStrictEqual('toggle_help');
  expect(keyAnswer(',', comma, rebound, '').input).toStrictEqual(',');
});

test('Cyrillic typed in the prompt stays as typed', () => {
  const states = {
    ready: ready(DEFAULT_KEYMAP),
    vim: reduceApp(ready(DEFAULT_KEYMAP), { type: 'vim_toggled', on: true }),
  };

  for (const [name, state] of Object.entries(states)) {
    for (const draft of ['', 'привет']) {
      for (const letter of CYRILLIC) {
        expect(
          keyCommand(letter, press(), state, draft),
          `${letter} in ${name} on "${draft}"`,
        ).toStrictEqual(undefined);
        expect(
          !typedTakenBack(letter, press(), DEFAULT_KEYMAP, false),
        ).toBeTruthy();
      }
    }
  }
});

test('hints name the bound key, and say none when nothing is bound', () => {
  const { keymap } = read(
    { context: 'Chat', bindings: { escape: null, 'ctrl+q': 'chat:cancel' } },
    { context: 'Scroll', bindings: { end: null, 'shift+end': null } },
  );
  const turn = { status: 'working', turnId: 't1', since: 0 } as const;

  expect(hintKey(keymap, 'chat:cancel')).toStrictEqual('ctrl+q');
  expect(hintKey(keymap, 'scroll:bottom')).toStrictEqual(undefined);
  expect(workingLine(turn, 1000, false, 'ctrl+q')?.detail).toStrictEqual(
    '1s · ctrl+q to interrupt',
  );
  expect(workingLine(turn, 1000, false, undefined)?.detail).toStrictEqual('1s');
  expect(
    shellView(
      { command: 'sleep 9', stdout: '', stderr: '', running: true } as never,
      false,
      'ctrl+q',
    ).note?.text,
  ).toStrictEqual('Running… (ctrl+q to stop)');

  const scrolled = { top: 0, content: 50, view: 10, following: false };
  const line = indicator(scrolled as never, 80, undefined)
    .map(({ text }) => text)
    .join('');

  expect(!line.includes('to jump'), line).toBeTruthy();
  expect(
    statusLine({ mode: 'plan', cycleKey: null }, 80).left.map(
      (part) => part.text,
    ),
  ).toStrictEqual(['⏸ plan mode on']);
  expect(
    statusLine({ mode: 'plan', cycleKey: 'ctrl+t' }, 80).left.map(
      (part) => part.text,
    ),
  ).toStrictEqual(['⏸ plan mode on', '(ctrl+t to cycle)']);

  const busy = reduceApp(ready(keymap), {
    type: 'prompt',
    turnId: 't1',
    text: 'hi',
    at: 0,
  });

  expect(resumeRefusal(busy)).toStrictEqual(
    'A turn is running. Wait for it to end, or press Ctrl+q to interrupt it, then /resume.',
  );
});

test('the panel names rebound keys, and drops a line with none', () => {
  const { keymap } = read(
    {
      context: 'Chat',
      bindings: { 'ctrl+g': null, 'ctrl+e': 'chat:externalEditor' },
    },
    { context: 'Chat', bindings: { 'ctrl+v': null } },
  );
  const lines = shortcuts(keymap).map(shortcutLine);

  expect(
    lines.includes('ctrl + e to edit in $EDITOR'),
    lines.join('\n'),
  ).toBeTruthy();
  expect(
    !lines.some((line) => line.includes('to paste an image')),
  ).toBeTruthy();
  expect(lines.includes('enter to send')).toBeTruthy();
});

test('the scroll line names the wheel after the page keys, and alone with none', () => {
  const lines = (bindings: Record<string, string | null>) =>
    shortcuts(read({ context: 'Scroll', bindings }).keymap).map(shortcutLine);

  expect(
    shortcuts().map(shortcutLine).includes('pgup pgdn or wheel to scroll'),
  ).toBeTruthy();
  expect(
    lines({
      pageup: null,
      'shift+pageup': null,
      'ctrl+b': 'scroll:pageUp',
    }).includes('ctrl + b pgdn shift + pgdn or wheel to scroll'),
  ).toBeTruthy();
  expect(
    lines({
      pageup: null,
      'shift+pageup': null,
      pagedown: null,
      'shift+pagedown': null,
    }).includes('wheel to scroll'),
  ).toBeTruthy();
});

test('the backslash newline names the key that sends', () => {
  const lines = (...bindings: Record<string, string | null>[]) =>
    shortcuts(
      read(...bindings.map((map) => ({ context: 'Chat', bindings: map })))
        .keymap,
    ).map(shortcutLine);

  expect(lines().includes('\\ + enter for a newline')).toBeTruthy();
  expect(
    lines({ enter: null, 'ctrl+s': 'chat:submit' }).includes(
      '\\ + ctrl + s for a newline',
    ),
  ).toBeTruthy();
  // Two keys send; the line names the first, not both after one backslash.
  expect(
    lines({ 'ctrl+s': 'chat:submit' }).includes('\\ + enter for a newline'),
  ).toBeTruthy();
  expect(
    !lines({ enter: null }).some(
      (line) => line.includes('for a newline') && line.startsWith('\\'),
    ),
  ).toBeTruthy();
});

/** `state` with `held` pressed and the next key waited for. */
function holding(state: AppState, held: string): AppState {
  return reduceApp(state, { type: 'keys_pending', keys: keys(held) });
}

/** The leader line for `state` at `width`, as one string. */
function leader(state: AppState, width: number): string {
  const view = leaderLine(
    state.pendingKeys!,
    pendingBindings(state, ''),
    width,
  );

  return (
    view.held +
    LEADER_GAP +
    view.items
      .map(({ keys, words }) => (words === '' ? keys : `${keys} ${words}`))
      .join(STATUS_SEPARATOR)
  );
}

test("the leader's keys go to a session, over a permission and a form", () => {
  const ctrl = press({ ctrl: true });
  const leaderHeld = holding(ready(DEFAULT_KEYMAP), 'ctrl+x');

  expect(keyCommand('x', ctrl, ready(DEFAULT_KEYMAP), '')).toStrictEqual(
    'key_pending',
  );
  expect(keyCommand('c', press(), leaderHeld, '')).toStrictEqual('new_session');
  expect(keyCommand('n', press(), leaderHeld, '')).toStrictEqual(
    'next_session',
  );
  expect(keyCommand('n', ctrl, leaderHeld, '')).toStrictEqual('next_session');
  expect(keyCommand('p', press(), leaderHeld, '')).toStrictEqual(
    'previous_session',
  );
  expect(keyCommand('p', ctrl, leaderHeld, '')).toStrictEqual(
    'previous_session',
  );
  expect(keyCommand('7', press(), leaderHeld, '')).toStrictEqual(
    'goto_session_7',
  );
  expect(keyCommand('a', press(), leaderHeld, '')).toStrictEqual(
    'attend_session',
  );
  expect(keyCommand('', press({ escape: true }), leaderHeld, '')).toStrictEqual(
    'key_dropped',
  );

  const prompt = { type: 'prompt', turnId: 't1', text: 'hi', at: 0 } as const;
  const asked = reduceApp(reduceApp(ready(DEFAULT_KEYMAP), prompt), {
    type: 'permission_requested',
    turnId: 't1',
    permission: { id: 'p1', options: [] },
  });
  const form = reduceApp(reduceApp(ready(DEFAULT_KEYMAP), prompt), {
    type: 'elicitation_requested',
    turnId: 't1',
    elicitation: { id: 'e1', mode: 'form', message: 'Go?', schema: {} },
  });

  for (const state of [asked, form]) {
    expect(keyCommand('x', ctrl, state, '')).toStrictEqual('key_pending');
    expect(
      keyCommand('2', press(), holding(state, 'ctrl+x'), ''),
    ).toStrictEqual('goto_session_2');
  }
});

test('a session action is rebound and unbound through the file', () => {
  const { keymap, problems } = read({
    context: 'Global',
    bindings: { 'ctrl+x t': 'session:new', 'ctrl+x c': null },
  });
  const held = holding(ready(keymap), 'ctrl+x');

  expect(problems).toStrictEqual([]);
  expect(keyCommand('t', press(), held, '')).toStrictEqual('new_session');
  expect(keyCommand('c', press(), held, '')).toStrictEqual('key_dropped');
});

test('the leader line names every key that can follow, as wide as it fits', () => {
  const held = holding(ready(DEFAULT_KEYMAP), 'ctrl+x');

  expect(leader(held, 116)).toStrictEqual(
    'ctrl+x …  c new · n next · p previous · 1–9 go to · w list · a the one that waits · k close · esc never mind',
  );
  // Short words first, then items dropped from the end, never cut through.
  expect(leader(held, 76)).toStrictEqual(
    'ctrl+x …  c new · n p next prev · 1–9 · w list · a waits · k close',
  );
  expect(leader(held, 56)).toStrictEqual(
    'ctrl+x …  c new · n p next prev · 1–9 · w list · a waits',
  );
  expect(leader(held, 47)).toStrictEqual(
    'ctrl+x …  c new · n p next prev · 1–9 · w list',
  );
  expect(leader(held, 40)).toStrictEqual(
    'ctrl+x …  c new · n p next prev · 1–9',
  );
  expect(leader(held, 31)).toStrictEqual('ctrl+x …  c new · n p next prev');
  expect(leader(held, 20)).toStrictEqual('ctrl+x …  c new');
});

test('the leader line follows the keybindings file', () => {
  const { keymap } = read({
    context: 'Global',
    bindings: {
      'ctrl+x t': 'session:new',
      'ctrl+x c': null,
      'ctrl+x 9': null,
    },
  });

  expect(leader(holding(ready(keymap), 'ctrl+x'), 130)).toStrictEqual(
    'ctrl+x …  t new · n next · p previous · 1 2 3 4 5 6 7 8 go to · w list · a the one that waits · k close · esc never mind',
  );
});

test("a person's own chord shows its next key on the leader line", () => {
  const { keymap } = read({
    context: 'Chat',
    bindings: { 'ctrl+k ctrl+e': 'chat:externalEditor' },
  });
  const held = holding(ready(keymap), 'ctrl+k');

  expect(leader(held, 116)).toStrictEqual(
    'ctrl+k …  ctrl+e edit in $EDITOR · esc never mind',
  );
  expect(
    leaderWidth(
      leaderLine(held.pendingKeys!, pendingBindings(held, ''), 116),
    ) <= 116,
  ).toBeTruthy();
});

test('the panel still fits 80x24: one sessions line, one quit line', () => {
  const lines = shortcuts().map(shortcutLine);
  const columns = inColumns(lines, columnCount(lines, 80));

  expect(lines.includes('ctrl + x then a key for sessions')).toBeTruthy();
  expect(lines.includes('ctrl + d or ctrl + c twice to quit')).toBeTruthy();
  expect(!lines.includes('ctrl + d to quit')).toBeTruthy();
  expect(columns.length).toStrictEqual(2);
  // 20 rows with CHD-243's line for x, still under the prompt at 24 rows.
  expect(Math.max(...columns.map((column) => column.length))).toStrictEqual(20);
});

test('a session action bound off the leader gets a panel line of its own', () => {
  const { keymap, problems } = read({
    context: 'Global',
    bindings: { 'ctrl+n': 'session:next' },
  });
  const lines = shortcuts(keymap).map(shortcutLine);

  expect(problems).toStrictEqual([]);
  expect(lines.includes('ctrl + x then a key for sessions')).toBeTruthy();
  expect(lines.includes('ctrl + n for the next session')).toBeTruthy();

  const off = read({
    context: 'Global',
    bindings: Object.fromEntries(
      keysOf(DEFAULT_KEYMAP, 'session:new')
        .concat(keysOf(DEFAULT_KEYMAP, 'session:next'))
        .concat(keysOf(DEFAULT_KEYMAP, 'session:previous'))
        .concat(keysOf(DEFAULT_KEYMAP, 'session:list'))
        .concat(keysOf(DEFAULT_KEYMAP, 'session:attention'))
        .concat(keysOf(DEFAULT_KEYMAP, 'session:close'))
        .concat([...'123456789'].map((n) => keys(`ctrl+x ${n}`)))
        .map((sequence) => [sequenceHint(sequence), null]),
    ),
  });

  expect(off.problems).toStrictEqual([]);
  expect(
    !shortcuts(off.keymap)
      .map(shortcutLine)
      .some((line) => line.includes('sessions')),
  ).toBeTruthy();
});

test('the textarea takes its own keys and typed text, and no other key', () => {
  const key = { ctrl: false, escape: false };
  const off = textareaKeys(DEFAULT_KEYMAP);

  expect(textareaTakes('a', key, off)).toBeTruthy();
  expect(textareaTakes('', { ...key, backspace: true }, off)).toBeTruthy();
  expect(textareaTakes('w', { ...key, ctrl: true }, off)).toBeTruthy();
  // OpenTUI's own keys that the box never had are the window's.
  expect(!textareaTakes('d', { ...key, ctrl: true }, off)).toBeTruthy();
  expect(!textareaTakes('', { ...key, home: true }, off)).toBeTruthy();
  expect(!textareaTakes('', { ...key, tab: true }, off)).toBeTruthy();
  // One a binding moved elsewhere is turned off.
  expect(
    !textareaTakes(
      'k',
      { ...key, ctrl: true },
      textareaKeys(
        read({ context: 'Chat', bindings: { 'ctrl+k': 'chat:externalEditor' } })
          .keymap,
      ),
    ),
  ).toBeTruthy();
});
