import { expect, test } from 'bun:test';
import {
  cleanOutput,
  endNote,
  shellContext,
  splitContext,
  withContext,
} from '../../src/session/context.ts';
import type { ShellRun } from '../../src/session/transcript/types.ts';

const done = (run: Partial<ShellRun>): ShellRun => ({
  command: 'ls',
  stdout: '',
  stderr: '',
  running: false,
  code: 0,
  ...run,
});

test('output loses its colours, links and the lines a \\r rewrote', () => {
  expect(
    cleanOutput(
      '\x1b[31mred\x1b[0m \x1b]8;;https://x\x07link\x1b]8;;\x07\r\n' +
        '10%\r50%\r100%\n\n',
    ),
  ).toStrictEqual('red link\n100%');
});

test('only an ending that is news is noted', () => {
  expect(endNote(done({}))).toStrictEqual(undefined);
  expect(endNote(done({ running: true }))).toStrictEqual(undefined);
  expect(endNote(done({ code: 2 }))).toStrictEqual('Exit code 2');
  expect(endNote(done({ stopped: true }))).toStrictEqual('Stopped by the user');
  expect(endNote(done({ error: 'no shell' }))).toStrictEqual('Error: no shell');
});

test("runs go ahead of the prompt in Claude Code's tags", () => {
  const context = shellContext([
    done({ stdout: '\x1b[1ma\x1b[0m\nb\n' }),
    done({ command: 'false', stderr: 'bad\n', code: 1 }),
  ]);

  expect(context).toStrictEqual(
    '<bash-input>ls</bash-input>\n' +
      '<bash-stdout>a\nb</bash-stdout><bash-stderr></bash-stderr>\n' +
      '<bash-input>false</bash-input>\n' +
      '<bash-stdout></bash-stdout><bash-stderr>bad</bash-stderr>' +
      '<bash-status>Exit code 1</bash-status>',
  );
  expect(withContext('', 'hi')).toStrictEqual('hi');
  expect(withContext(context, 'hi')).toStrictEqual(`${context}\n\nhi`);
});

test('a sent prompt splits back into its runs and what was typed', () => {
  const runs: ShellRun[] = [
    done({ stdout: 'a\nb' }),
    done({ command: 'false', stderr: 'bad', code: 1 }),
    {
      command: 'sleep 9',
      stdout: '',
      stderr: '',
      running: false,
      stopped: true,
    },
    done({ command: 'big', stdout: 'x', truncated: true }),
  ];
  const sent = withContext(shellContext(runs), 'what failed?');

  expect(splitContext(sent)).toStrictEqual({ runs, text: 'what failed?' });
  expect(splitContext('plain')).toStrictEqual({ runs: [], text: 'plain' });
});
