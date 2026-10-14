import { expect, test } from 'bun:test';
import type { ShellRun } from '../../../src/session/transcript/types.ts';
import {
  bashCommand,
  entersBash,
  SHELL_LINES,
  shellView,
  typedText,
} from '../../../src/ui/prompt/bash.ts';

const run = (fields: Partial<ShellRun>): ShellRun => ({
  command: 'ls',
  stdout: '',
  stderr: '',
  running: false,
  code: 0,
  ...fields,
});

test('a ! on an empty prompt starts bash mode, typed or pasted', () => {
  expect(entersBash(false, '', '!')).toStrictEqual('');
  expect(entersBash(false, '', '!ls -la')).toStrictEqual('ls -la');
  expect(entersBash(false, 'hi', 'hi!')).toStrictEqual(undefined);
  expect(entersBash(false, '', 'ls')).toStrictEqual(undefined);
  // In bash mode a ! is part of the command.
  expect(entersBash(true, '', '!')).toStrictEqual(undefined);
});

test('history keeps a command with its ! on', () => {
  expect(typedText(true, 'ls')).toStrictEqual('!ls');
  expect(typedText(false, 'ls')).toStrictEqual('ls');
  expect(bashCommand('!ls')).toStrictEqual('ls');
  expect(bashCommand('ls')).toStrictEqual(undefined);
});

test('a run shows stdout, then stderr, and a failing exit code', () => {
  expect(
    shellView(run({ stdout: 'a\n', stderr: 'oops\n', code: 3 }), false, 'esc'),
  ).toStrictEqual({
    lines: [
      { text: 'a', stream: 'stdout' },
      { text: 'oops', stream: 'stderr' },
    ],
    hidden: 0,
    note: { text: 'Exit code 3', failed: true },
  });
});

test('a run says it runs, that it was stopped, or that it was silent', () => {
  expect(shellView(run({ running: true }), false, 'esc').note).toStrictEqual({
    text: 'Running… (esc to stop)',
    failed: false,
  });
  expect(shellView(run({ stopped: true }), false, 'esc').note).toStrictEqual({
    text: 'Stopped by the user',
    failed: false,
  });
  expect(shellView(run({}), false, 'esc').note).toStrictEqual({
    text: '(No output)',
    failed: false,
  });
  expect(shellView(run({ stdout: 'ok' }), false, 'esc').note).toStrictEqual(
    undefined,
  );
});

test('long output folds until ctrl+o', () => {
  const stdout = Array.from({ length: 25 }, (_, i) => `line ${i}`).join('\n');

  expect(shellView(run({ stdout }), false, 'esc').lines.length).toStrictEqual(
    SHELL_LINES,
  );
  expect(shellView(run({ stdout }), false, 'esc').hidden).toStrictEqual(
    25 - SHELL_LINES,
  );
  expect(shellView(run({ stdout }), true, 'esc').lines.length).toStrictEqual(
    25,
  );
  expect(shellView(run({ stdout }), true, 'esc').hidden).toStrictEqual(0);
});
