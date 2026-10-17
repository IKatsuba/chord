import { expect, test } from 'bun:test';
import type { PermissionOption } from '@agentclientprotocol/sdk';
import type { PermissionWait } from '../../../src/session/transcript/types.ts';
import {
  askedPermission,
  choicesFor,
  hiddenRows,
  inputLines,
  locationsShown,
  permissionOutcome,
  requestRows,
  requestStep,
  requestView,
  requestRule,
  saveChoices,
} from '../../../src/ui/dialogs/permission.ts';

const allow: PermissionOption = {
  optionId: 'allow',
  name: 'Allow',
  kind: 'allow_once',
};
const always: PermissionOption = {
  optionId: 'always',
  name: 'Always allow',
  kind: 'allow_always',
};
const deny: PermissionOption = {
  optionId: 'deny',
  name: 'Deny',
  kind: 'reject_once',
};
const write: PermissionWait = {
  id: 'p1',
  toolCallId: 'write-1',
  title: 'Write notes.txt',
  options: [allow, always, deny],
};

test('the oldest request is the one on screen', () => {
  const second: PermissionWait = { id: 'p2', options: [allow] };

  expect(
    askedPermission({
      status: 'awaiting_permission',
      turnId: 't',
      since: 0,
      permissions: [write, second],
    }),
  ).toStrictEqual(write);
  expect(
    askedPermission({ status: 'working', turnId: 't', since: 0 }),
  ).toStrictEqual(undefined);
  expect(askedPermission({ status: 'idle' })).toStrictEqual(undefined);
});

test("the choices are the agent's options, numbered in its order", () => {
  expect(choicesFor(write)).toStrictEqual([
    { key: 'allow', label: '1. Allow', value: 'allow' },
    { key: 'always', label: '2. Always allow', value: 'always' },
    { key: 'deny', label: '3. Deny', value: 'deny' },
  ]);
  // Only what the agent offers: one option is one choice.
  expect(choicesFor({ id: 'p', options: [deny] })).toStrictEqual([
    { key: 'deny', label: '1. Deny', value: 'deny' },
  ]);
});

test('a location the title already names gets no line of its own', () => {
  const at = (title: string | undefined, ...paths: string[]) =>
    locationsShown({
      ...write,
      ...(title === undefined ? {} : { title }),
      locations: paths.map((path) => ({ path })),
    });

  expect(at('Write notes.txt', 'notes.txt')).toStrictEqual([]);
  expect(at('Edit file', 'src/a.ts')).toStrictEqual(['src/a.ts']);
  expect(at('Move a.ts', 'a.ts', 'b.ts')).toStrictEqual(['b.ts']);
  expect(at(undefined, 'a.ts')).toStrictEqual(['a.ts']);
});

test('an answer reads as allowed or rejected, naming an allow option', () => {
  const answered = (option?: PermissionOption) =>
    permissionOutcome({
      kind: 'permission',
      turnId: 't',
      title: 'Write notes.txt',
      ...(option === undefined ? {} : { option }),
    });

  expect(answered(allow)).toStrictEqual({
    text: 'Allowed Write notes.txt · Allow',
    allowed: true,
  });
  expect(answered(always)).toStrictEqual({
    text: 'Allowed Write notes.txt · Always allow',
    allowed: true,
  });
  // "Rejected · Deny" would say it twice.
  expect(answered(deny)).toStrictEqual({
    text: 'Rejected Write notes.txt',
    allowed: false,
  });
  // Esc picks no option.
  expect(answered()).toStrictEqual({
    text: 'Rejected Write notes.txt',
    allowed: false,
  });
  expect(
    permissionOutcome({ kind: 'permission', turnId: 't' }).text,
  ).toStrictEqual('Rejected the tool call');
});

test('raw input is one key: value per line, strings unquoted', () => {
  expect(
    inputLines({
      ...write,
      title: 'mcp__chord__monitor',
      rawInput: {
        command: 'tail -f dev.log | grep -E "ERROR|WARN"',
        description: 'dev server errors',
        timeout_ms: 600000,
        follow: true,
        last: null,
      },
    }),
  ).toStrictEqual([
    'command: tail -f dev.log | grep -E "ERROR|WARN"',
    'description: dev server errors',
    'timeout_ms: 600000',
    'follow: true',
    'last: null',
  ]);
});

test('nested raw input is compact JSON', () => {
  expect(
    inputLines({
      ...write,
      rawInput: { paths: ['a.ts', 'b.ts'], env: { CI: '1' } },
    }),
  ).toStrictEqual(['paths: ["a.ts","b.ts"]', 'env: {"CI":"1"}']);
});

test('raw input that is not an object is one line', () => {
  expect(inputLines({ ...write, rawInput: 'ls -la' })).toStrictEqual([
    'ls -la',
  ]);
  expect(inputLines({ ...write, rawInput: [1, 2] })).toStrictEqual(['[1,2]']);
});

test('a request with no raw input shows none', () => {
  expect(inputLines(write)).toStrictEqual([]);
  expect(inputLines({ ...write, rawInput: {} })).toStrictEqual([]);
});

test("a save box's choices name the file each writes, in a column of their own", () => {
  const wait: PermissionWait = {
    id: 'p',
    options: [
      {
        optionId: 'project',
        name: 'Yes, for this project',
        kind: 'allow_once',
      },
      {
        optionId: 'user',
        name: 'Yes, for every project',
        kind: 'allow_always',
      },
      {
        optionId: 'change',
        name: 'No, tell claude what to change',
        kind: 'reject_once',
      },
    ],
    save: {
      question: 'Save team bugfix?',
      files: {
        project: '.chord/teams/bugfix.md',
        user: '~/.config/chord/teams/bugfix.md',
      },
      escape: 'tell claude what to change',
    },
  };

  expect(saveChoices(wait).map((choice) => choice.label)).toStrictEqual([
    '1. Yes, for this project   .chord/teams/bugfix.md',
    '2. Yes, for every project  ~/.config/chord/teams/bugfix.md',
    '3. No, tell claude what to change',
  ]);
});

test("a request's rows: the title's first pinned, its others, the locations and the arguments after, each wrapped", () => {
  const { pinned, rows } = requestRows(
    {
      id: 'p',
      options: [],
      title: 'Write a file whose title runs on',
      locations: [{ path: 'docs/a.md' }],
      rawInput: { content: 'one two three four\n\nfive', mode: 'overwrite' },
    },
    16,
  );

  expect(pinned).toStrictEqual('Write a file');
  expect(rows).toStrictEqual([
    { text: 'whose title runs', kind: 'title' },
    { text: 'on', kind: 'title' },
    { text: 'docs/a.md', kind: 'location' },
    // Two cells in, so in 14.
    { text: 'content: one', kind: 'input' },
    { text: 'two three four', kind: 'input' },
    { text: '', kind: 'input' },
    { text: 'five', kind: 'input' },
    { text: 'mode:', kind: 'input' },
    { text: 'overwrite', kind: 'input' },
  ]);
});

test('a request counts the rows out of view above and below', () => {
  expect(hiddenRows(40, 0, 5)).toStrictEqual({ above: 0, below: 35 });
  expect(hiddenRows(40, 12, 4)).toStrictEqual({ above: 12, below: 24 });
  expect(hiddenRows(40, 35, 5)).toStrictEqual({ above: 35, below: 0 });
  expect(hiddenRows(40, 39, 0)).toStrictEqual({ above: 39, below: 1 });
});

test("a request's rule says how much, which way and the key, to the box's width", () => {
  expect(requestRule('↓', 37, 'pagedown', 48)).toStrictEqual(
    '── ↓ 37 lines below · pagedown to scroll ───────',
  );
  expect(requestRule('↑', 1, 'pageup', 40)).toStrictEqual(
    '── ↑ 1 line above · pageup to scroll ───',
  );
  // Too narrow for the key, the count stays; unbound, there is none to name.
  expect(requestRule('↓', 37, 'pagedown', 24)).toStrictEqual(
    '── ↓ 37 lines below ────',
  );
  expect(requestRule('↓', 2, undefined, 24)).toStrictEqual(
    '── ↓ 2 lines below ─────',
  );
});

test('a room of six over 42 rows: the top view, views between the rules, the end view', () => {
  expect(requestView(42, 6, 0)).toStrictEqual({
    top: 0,
    shown: 5,
    above: false,
    below: true,
  });
  expect(requestView(42, 6, 5)).toStrictEqual({
    top: 5,
    shown: 4,
    above: true,
    below: true,
  });
  expect(requestView(42, 6, 37)).toStrictEqual({
    top: 37,
    shown: 5,
    above: true,
    below: false,
  });
  // Past the end view, as the wheel can leave it, is the end view.
  expect(requestView(42, 6, 38).top).toStrictEqual(37);
  expect(requestView(5, 6, 3)).toStrictEqual({
    top: 0,
    shown: 5,
    above: false,
    below: false,
  });
});

/** The rows each view shows, paging from `from` with `step` to the far end. */
function pages(
  total: number,
  room: number,
  step: 'page_down' | 'page_up',
  from: number,
): number[][] {
  const seen: number[][] = [];

  for (let top = from, last = -1; top !== last;) {
    const view = requestView(total, room, top);

    seen.push(Array.from({ length: view.shown }, (_, row) => view.top + row));

    last = top;
    top = requestStep(step, total, room, top);
  }

  return seen;
}

test('paging down and back up reaches every row of the request, none passed over', () => {
  for (const [total, room] of [
    [42, 6],
    [42, 20],
    [30, 3],
    [7, 4],
  ] as const) {
    const down = pages(total, room, 'page_down', 0);
    const up = pages(
      total,
      room,
      'page_up',
      requestStep('bottom', total, room, 0),
    );

    for (const way of [down, up]) {
      expect(new Set(way.flat()).size, `${total} over ${room}`).toStrictEqual(
        total,
      );
    }
  }

  // The design's table, a room of six: 0–4, 5–8, 9–12, … the last five.
  const down = pages(42, 6, 'page_down', 0);

  expect(down.slice(0, 3)).toStrictEqual([
    [0, 1, 2, 3, 4],
    [5, 6, 7, 8],
    [9, 10, 11, 12],
  ]);
  expect(down.at(-1)).toStrictEqual([37, 38, 39, 40, 41]);
  // Up from top 5 goes to the top, not to top 1.
  expect(requestStep('page_up', 42, 6, 5)).toStrictEqual(0);
  expect(requestStep('page_up', 42, 6, 37)).toStrictEqual(33);
});

test('a room of two has one rule and a row; a room of one no rule, a page a row', () => {
  expect(requestView(42, 2, 0)).toStrictEqual({
    top: 0,
    shown: 1,
    above: false,
    below: true,
  });
  expect(requestView(42, 2, 41)).toStrictEqual({
    top: 41,
    shown: 1,
    above: true,
    below: false,
  });
  expect(requestStep('page_down', 42, 2, 0)).toStrictEqual(1);
  expect(requestView(42, 1, 3)).toStrictEqual({
    top: 3,
    shown: 1,
    above: false,
    below: false,
  });
  expect(requestStep('page_down', 42, 1, 3)).toStrictEqual(4);
  // Home and end still jump to the two ends.
  expect(requestStep('bottom', 42, 1, 3)).toStrictEqual(41);
  expect(requestStep('top', 42, 1, 3)).toStrictEqual(0);
  expect(requestStep('line_up', 42, 1, 0)).toStrictEqual(0);
});
