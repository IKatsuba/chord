import { expect, test } from 'bun:test';
import { TRUNCATED } from '../../../../src/session/context.ts';
import type { Terminal } from '../../../../src/session/transcript/types.ts';
import {
  isEmpty,
  TERMINAL_LINES,
  terminalView,
} from '../../../../src/ui/transcript/tools/terminal.ts';

const terminal = (fields: Partial<Terminal>): Terminal => ({
  id: 't',
  output: '',
  exited: false,
  ...fields,
});

test('a folded terminal keeps its latest lines and counts those above', () => {
  const lines = Array.from({ length: 7 }, (_, index) => `line ${index + 1}`);
  const view = terminalView(terminal({ output: lines.join('\n') }), false);

  expect(view.lines).toStrictEqual(lines.slice(-TERMINAL_LINES));
  expect(view.hidden).toStrictEqual(7 - TERMINAL_LINES);
  expect(view.note).toStrictEqual(undefined);
});

test('ctrl+o shows the whole output, and says where its start was cut', () => {
  const output = 'a\nb\nc\nd\ne\n';

  expect(terminalView(terminal({ output }), true)).toStrictEqual({
    lines: ['a', 'b', 'c', 'd', 'e'],
    hidden: 0,
  });
  expect(
    terminalView(terminal({ output, truncated: true }), true).lines,
  ).toStrictEqual([TRUNCATED, 'a', 'b', 'c', 'd', 'e']);
  // Folded, the cut is above the hidden lines, so it is not said.
  expect(
    terminalView(terminal({ output, truncated: true }), false).lines,
  ).toStrictEqual(['c', 'd', 'e']);
});

test('the output is drawn as the reducer keeps it, tabs already spaces', () => {
  expect(
    terminalView(terminal({ output: 'a       b\n界      d\n\n' }), true).lines,
  ).toStrictEqual(['a       b', '界      d']);
});

test('a failing exit says its code; success says nothing more', () => {
  expect(
    terminalView(
      terminal({ output: 'boom\n', exited: true, exitCode: 2 }),
      false,
    ).note,
  ).toStrictEqual({ text: 'Exit code 2', failed: true });
  expect(
    terminalView(terminal({ output: 'ok\n', exited: true, exitCode: 0 }), false)
      .note,
  ).toStrictEqual(undefined);
  expect(
    terminalView(terminal({ exited: true, signal: 'SIGTERM' }), false).note,
  ).toStrictEqual({ text: 'Killed by SIGTERM', failed: true });
});

test("an agent's signal name is drawn on one line, in the note's own tone", () => {
  expect(
    terminalView(terminal({ exited: true, signal: 'SIG\nTERM\n' }), false).note,
  ).toStrictEqual({ text: 'Killed by SIG TERM', failed: true });
  expect(
    terminalView(terminal({ exited: true, signal: '' }), false).note,
  ).toStrictEqual({ text: 'Killed', failed: true });
});

test('a terminal that wrote nothing is empty until it ends', () => {
  expect(isEmpty(terminalView(terminal({}), false))).toStrictEqual(true);
  expect(
    isEmpty(terminalView(terminal({ output: '\n' }), false)),
  ).toStrictEqual(true);
  expect(
    terminalView(terminal({ exited: true, exitCode: 0 }), false).note,
  ).toStrictEqual({ text: '(No output)', failed: false });
});
