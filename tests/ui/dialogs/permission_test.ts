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
