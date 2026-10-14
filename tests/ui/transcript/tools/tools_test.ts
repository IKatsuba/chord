import { expect, test } from 'bun:test';
import type { ToolCall } from '../../../../src/session/transcript/types.ts';
import {
  headline,
  summary,
  toneOf,
} from '../../../../src/ui/transcript/tools/tools.ts';

function text(value: string): NonNullable<ToolCall['content']>[number] {
  return { type: 'content', content: { type: 'text', text: value } };
}

test('a title starting with a verb reads as Verb(arg)', () => {
  expect(headline({ id: 'a', title: 'Read src/main.tsx' })).toStrictEqual({
    name: 'Read',
    arg: 'src/main.tsx',
  });
  expect(
    headline({ id: 'a', title: 'Edit `src/a.ts`', kind: 'edit' }),
  ).toStrictEqual({
    name: 'Edit',
    arg: 'src/a.ts',
  });
});

test('a bare command or description is named by its kind', () => {
  expect(
    headline({ id: 'a', title: '`ls -la`', kind: 'execute' }),
  ).toStrictEqual({
    name: 'Bash',
    arg: 'ls -la',
  });
  expect(
    headline({ id: 'a', title: 'grep TODO', kind: 'search' }),
  ).toStrictEqual({
    name: 'Search',
    arg: 'grep TODO',
  });
  expect(headline({ id: 'a', title: 'Task' })).toStrictEqual({ name: 'Task' });
  expect(headline({ id: 'a' })).toStrictEqual({ name: 'Tool' });
  expect(headline({ id: 'a', kind: 'fetch' })).toStrictEqual({ name: 'Fetch' });
});

test("a title of several lines keeps its first; the rest is ctrl+o's", () => {
  expect(
    headline({
      id: 'a',
      title: "cat >> notes.md <<'EOF'  \n## 1. One\n\nEOF",
      kind: 'execute',
    }),
  ).toStrictEqual({
    name: 'Bash',
    arg: "cat >> notes.md <<'EOF'",
    more: ['## 1. One', '', 'EOF'],
  });
});

test('the status picks the tone; no status is pending', () => {
  expect(toneOf({ id: 'a' })).toStrictEqual('pending');
  expect(toneOf({ id: 'a', status: 'pending' })).toStrictEqual('pending');
  expect(toneOf({ id: 'a', status: 'in_progress' })).toStrictEqual('running');
  expect(toneOf({ id: 'a', status: 'completed' })).toStrictEqual('done');
  expect(toneOf({ id: 'a', status: 'failed' })).toStrictEqual('failed');
});

test('a call with no output says where it is', () => {
  expect(summary({ id: 'a' }, false)).toStrictEqual({
    lines: ['Waiting…'],
    hidden: 0,
    terminals: [],
    diffs: [],
  });
  expect(
    summary({ id: 'a', status: 'in_progress' }, false).lines,
  ).toStrictEqual(['Running…']);
  expect(summary({ id: 'a', status: 'completed' }, false).lines).toStrictEqual(
    [],
  );
  expect(summary({ id: 'a', status: 'failed' }, false).lines).toStrictEqual([
    'Failed',
  ]);
});

test('a call left unfinished by what ran it, which has ended, waits on nothing', () => {
  expect(summary({ id: 'a' }, true, undefined, true).lines).toStrictEqual([]);
  expect(
    summary({ id: 'a', status: 'in_progress' }, true, undefined, true).lines,
  ).toStrictEqual([]);
  expect(
    summary({ id: 'a', status: 'failed' }, true, undefined, true).lines,
  ).toStrictEqual(['Failed']);
});

test('long output keeps three lines and counts the rest', () => {
  const call: ToolCall = {
    id: 'a',
    status: 'completed',
    content: [text('1\n2\n3\n4\n5\n')],
  };

  expect(summary(call, false)).toStrictEqual({
    lines: ['1', '2', '3'],
    hidden: 2,
    terminals: [],
    diffs: [],
  });
  expect(summary(call, true)).toStrictEqual({
    lines: ['1', '2', '3', '4', '5'],
    hidden: 0,
    terminals: [],
    diffs: [],
  });
  expect(
    summary({ ...call, content: [text('1\n2\n3')] }, false).hidden,
  ).toStrictEqual(0);
});

test('a failed call says Error before its output', () => {
  expect(
    summary(
      { id: 'a', status: 'failed', content: [text('no such file')] },
      false,
    ).lines,
  ).toStrictEqual(['Error: no such file']);
});

test('a diff draws under the lines, not among them', () => {
  const { lines, hidden, diffs } = summary(
    {
      id: 'a',
      status: 'completed',
      content: [
        text('done'),
        {
          type: 'diff',
          path: 'src/a.ts',
          oldText: 'a\nb\n',
          newText: 'a\nc\nd\n',
        },
      ],
    },
    false,
  );

  expect({ lines, hidden }).toStrictEqual({ lines: ['done'], hidden: 0 });
  expect(
    diffs.map((view) => [view.path, view.added, view.removed]),
  ).toStrictEqual([['src/a.ts', 2, 1]]);
});

test('a diff alone needs no status line, unless the call failed', () => {
  const diff = {
    type: 'diff',
    path: 'a.ts',
    oldText: 'a',
    newText: 'b',
  } as const;

  for (const status of ['pending', 'in_progress', 'completed'] as const) {
    expect(
      summary({ id: 'a', status, content: [diff] }, false).lines,
    ).toStrictEqual([]);
  }

  expect(
    summary({ id: 'a', status: 'failed', content: [diff] }, false).lines,
  ).toStrictEqual(['Failed']);
});

test('a terminal draws its output in place of the call working', () => {
  const call: ToolCall = {
    id: 'a',
    status: 'in_progress',
    content: [{ type: 'terminal', terminalId: 't' }],
    terminals: [{ id: 't', output: '', exited: false }],
  };

  // Claude's adapter sends nothing of it until the command is done.
  expect(summary(call, false).lines).toStrictEqual(['Running…']);
  expect(summary(call, false).terminals).toStrictEqual([]);

  const growing = summary(
    {
      ...call,
      terminals: [{ id: 't', output: '1\n2\n3\n4\n', exited: false }],
    },
    false,
  );

  expect(growing.lines).toStrictEqual([]);
  expect(growing.terminals).toStrictEqual([
    { lines: ['2', '3', '4'], hidden: 1 },
  ]);
});

test('a failing exit is the failure, in words, without Failed', () => {
  const failed = (exitCode: number): ToolCall => ({
    id: 'a',
    status: 'failed',
    content: [{ type: 'terminal', terminalId: 't' }],
    terminals: [{ id: 't', output: 'boom\n', exited: true, exitCode }],
  });

  expect(summary(failed(1), false).lines).toStrictEqual([]);
  expect(summary(failed(1), false).terminals[0]?.note).toStrictEqual({
    text: 'Exit code 1',
    failed: true,
  });
  // A call that failed though its command did not still says so.
  expect(summary(failed(0), false).lines).toStrictEqual(['Failed']);
});

test('what Team and Open handed over wraps to the row and folds after three lines; a message stays cut', () => {
  const job =
    'Issue 214: a string at the end of a line loses its closing ' +
    'quote. readString stops at the newline before it consumes the quote. ' +
    'Add a test that fails for that reason, fix it, and have it reviewed.';
  const call = (tool: 'run_team' | 'open_agent' | 'send_message') => ({
    id: 'a',
    status: 'completed' as const,
    chord: {
      tool,
      input: {
        team: 'bugfix',
        job,
        member: 'tester',
        prompt: job,
        text: job,
      },
      answer: {},
    },
  });

  for (const tool of ['run_team', 'open_agent'] as const) {
    const folded = summary(call(tool), false, undefined, false, 40);

    expect(folded.lines.length).toStrictEqual(3);
    expect(folded.lines.every((line) => line.length <= 40)).toStrictEqual(true);
    expect(folded.hidden > 0).toStrictEqual(true);

    const whole = summary(call(tool), true, undefined, false, 40);

    expect(whole.lines.join(' ')).toStrictEqual(job);
    expect(whole.hidden).toStrictEqual(0);
  }

  expect(
    summary(call('send_message'), false, undefined, false, 40).lines,
  ).toStrictEqual([job]);
});
