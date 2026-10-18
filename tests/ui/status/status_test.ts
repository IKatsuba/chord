import { describe, expect, test } from 'bun:test';
import stringWidth from 'string-width';
import {
  betweenNotice,
  contextUsed,
  SPINNER_STEPS,
  spinnerMarks,
  modePart,
  STATUS_SEPARATOR,
  type StatusFacts,
  statusLine,
  type TabBehind,
  waitsNotice,
  workingLine,
} from '../../../src/ui/status/status.ts';
import { idle, type TabWait } from '../../../src/session/tabs.ts';
import type { TurnState } from '../../../src/session/transcript/types.ts';

// Two digits used, as wide as the `99% left` the layouts were measured on.
const usage = { used: 120_000, size: 200_000 };
const facts: StatusFacts = {
  model: 'Fake Large with a 1M context window',
  mode: 'plan',
  usage,
  hint: '? for shortcuts',
};

/** The line as one string: the left side, a gap, the right side. */
function text(facts: StatusFacts, width: number): string {
  const { left, right } = statusLine(facts, width);
  const sides = [
    left.map((part) => part.text).join(' '),
    right.map((part) => part.text).join(STATUS_SEPARATOR),
  ];

  return sides.filter((side) => side !== '').join('  ');
}

test('context used is the complement of the free share rounded down', () => {
  expect(contextUsed(usage)).toStrictEqual(60);
  expect(contextUsed({ used: 1200, size: 200_000 })).toStrictEqual(1);
  expect(contextUsed({ used: 0, size: 200_000 })).toStrictEqual(0);
  expect(contextUsed({ used: 199_000, size: 200_000 })).toStrictEqual(100);
  expect(contextUsed({ used: 300, size: 200 })).toStrictEqual(100);
  expect(contextUsed({ used: 0, size: 0 })).toStrictEqual(100);
});

test('a mode goes on the left in place of the hint, the model alone on the right', () => {
  expect(text(facts, 116)).toStrictEqual(
    '⏸ plan mode on (shift+tab to cycle)  Fake Large with a 1M context window · 60% context used',
  );
  expect(statusLine(facts, 116).left[0]).toStrictEqual({
    text: '⏸ plan mode on',
    tone: 'plan',
  });
});

test('in the default mode the hint is on the left', () => {
  expect(text({ ...facts, mode: 'default' }, 116)).toStrictEqual(
    '? for shortcuts  Fake Large with a 1M context window · 60% context used',
  );
});

test('a narrow line drops the cycle hint, then cuts the model, never the mode', () => {
  expect(text(facts, 90)).toStrictEqual(
    '⏸ plan mode on (shift+tab to cycle)  Fake Large with a 1M context window · 60% used',
  );
  expect(text(facts, 70)).toStrictEqual(
    '⏸ plan mode on  Fake Large with a 1M context window · 60% context used',
  );
  expect(text(facts, 50)).toStrictEqual(
    '⏸ plan mode on  Fake Large with a 1M… · 60% used',
  );
  expect(text(facts, 30)).toStrictEqual('⏸ plan mode on  60% used');
  expect(text(facts, 20)).toStrictEqual('⏸ plan mode on');

  for (let width = 14; width <= 120; width++) {
    const line = text(facts, width);

    expect(line.startsWith('⏸ plan mode on'), line).toBeTruthy();
    expect(
      stringWidth(line) <= width,
      `"${line}" is wider than ${width}`,
    ).toBeTruthy();
  }
});

test('without a mode a narrow line shortens, then drops the hint', () => {
  const quiet = { ...facts, mode: undefined };

  expect(text(quiet, 70)).toStrictEqual(
    '? for shortcuts  Fake Large with a 1M context window · 60% used',
  );
  expect(text(quiet, 46)).toStrictEqual(
    '? for shortcuts  Fake Large with a… · 60% used',
  );
  expect(text(quiet, 30)).toStrictEqual('Fake Large with a… · 60% used');
  expect(text(quiet, 10)).toStrictEqual('60% used');

  for (let width = 8; width <= 120; width++) {
    const line = text(quiet, width);

    expect(
      stringWidth(line) <= width,
      `"${line}" is wider than ${width}`,
    ).toBeTruthy();
  }
});

test('a notice stays when the facts have to give way', () => {
  const quitting = { ...facts, notice: 'Press ctrl+c again to quit' };
  const line = text(quitting, 60);

  expect(stringWidth(line) <= 60).toBeTruthy();
  expect(
    line.startsWith('Press ctrl+c again to quit  Fake Large'),
  ).toStrictEqual(true);
  expect(line.endsWith('… · 60% used')).toStrictEqual(true);
});

test('a narrow notice drops the facts rather than be cut', () => {
  const quitting = { ...facts, notice: 'Press ctrl+c again to quit' };

  expect(text(quitting, 36)).toStrictEqual(
    'Press ctrl+c again to quit  60% used',
  );
  expect(text(quitting, 30)).toStrictEqual('Press ctrl+c again to quit');

  for (let width = 26; width <= 120; width++) {
    const line = text(quitting, width);

    expect(line.startsWith('Press ctrl+c again to quit'), line).toBeTruthy();
    expect(
      stringWidth(line) <= width,
      `"${line}" is wider than ${width}`,
    ).toBeTruthy();
  }
});

test('only what the agent reported is on the line', () => {
  expect(text({ hint: '? for shortcuts' }, 80)).toStrictEqual(
    '? for shortcuts',
  );
  expect(text({ model: 'Fake Large' }, 80)).toStrictEqual('Fake Large');
  expect(text({ usage }, 80)).toStrictEqual('60% context used');
  // The default mode says nothing, as in Claude Code.
  expect(text({ mode: 'default', usage }, 80)).toStrictEqual(
    '60% context used',
  );
  expect(text({ mode: 'acceptEdits' }, 80)).toStrictEqual(
    '⏵⏵ accept edits on (shift+tab to cycle)',
  );
});

test("Claude's modes keep Claude Code's words; others read as the agent names them", () => {
  expect(modePart('auto')).toStrictEqual({
    text: '⏵⏵ auto mode on',
    tone: 'auto',
  });
  expect(modePart('bypassPermissions')).toStrictEqual({
    text: '⏵⏵ bypass permissions on',
    tone: 'bypass',
  });
  expect(modePart('read-only', 'Read Only')).toStrictEqual({
    text: '⏵⏵ read only mode on',
    tone: 'plain',
  });
  expect(modePart('review')).toStrictEqual({
    text: '⏵⏵ review mode on',
    tone: 'plain',
  });
  expect(modePart('default', 'Default')).toStrictEqual(undefined);
});

test('context running low is marked above 80% used', () => {
  const at = statusLine({ usage: { used: 160_000, size: 200_000 } }, 80);
  const above = statusLine({ usage: { used: 161_000, size: 200_000 } }, 80);

  expect(at.right).toStrictEqual([{ text: '80% context used', tone: 'plain' }]);
  expect(above.right).toStrictEqual([
    { text: '81% context used', tone: 'low' },
  ]);
});

test('bash mode says so in place of the mode and the hint', () => {
  const { left } = statusLine({ ...facts, bash: true }, 116);

  expect(left).toStrictEqual([{ text: '! for bash mode', tone: 'bash' }]);
  expect(
    statusLine(
      { ...facts, bash: true, notice: 'Press ctrl+c again to quit' },
      116,
    ).left[0]?.text,
  ).toStrictEqual('Press ctrl+c again to quit');
});

test('a failed notice is coloured as a warning, any other is plain', () => {
  const notice = 'fail.sh exited with code 3; the draft is unchanged';

  expect(statusLine({ notice, failed: true }, 80).left).toStrictEqual([
    { text: notice, tone: 'failed' },
  ]);
  expect(statusLine({ notice }, 80).left).toStrictEqual([
    { text: notice, tone: 'plain' },
  ]);
});

test("vim's mode is marked first, as Claude Code marks it, and stays when the line is narrow", () => {
  expect(text({ ...facts, vim: 'insert' }, 116)).toStrictEqual(
    '-- INSERT -- ⏸ plan mode on (shift+tab to cycle)  Fake Large with a 1M context window · 60% context used',
  );
  expect(text({ ...facts, mode: 'default', vim: 'normal' }, 76)).toStrictEqual(
    '-- NORMAL -- ? for shortcuts  Fake Large with a 1M context window · 60% used',
  );
  expect(
    text({ ...facts, vim: 'normal' }, 40).startsWith('-- NORMAL --'),
  ).toBeTruthy();
  expect(
    text(
      { ...facts, notice: 'Press ctrl+c again to quit', vim: 'insert' },
      76,
    ).startsWith('-- INSERT -- Press ctrl+c again to quit'),
  ).toBeTruthy();
});

function behind(number: number, agent: string, wait: Partial<TabWait>) {
  return { number, agent, wait: { ...idle, ...wait } } satisfies TabBehind;
}

const permission = {
  asking: { on: { kind: 'permission' as const, title: 'Write' }, since: 20 },
};
const replied = { unseen: { kind: 'replied' as const, since: 10 } };

test('the waits notice names the one that waits, or counts them', () => {
  expect(waitsNotice([], 'ctrl+x a')).toStrictEqual(undefined);
  expect(waitsNotice([behind(3, 'fake', { working: 5 })])).toStrictEqual(
    undefined,
  );
  expect(
    waitsNotice([behind(2, 'claude', permission), behind(3, 'fake', replied)]),
  ).toStrictEqual({ text: '● 2 claude needs your permission', tone: 'waits' });
  expect(
    waitsNotice([
      behind(2, 'claude', {
        asking: { on: { kind: 'input', message: 'Who?' }, since: 1 },
      }),
    ])?.text,
  ).toStrictEqual('● 2 claude asks for input');
  expect(
    waitsNotice([behind(2, 'claude', permission), behind(4, 'x', permission)])
      ?.text,
  ).toStrictEqual('● 2 sessions wait');
  expect(waitsNotice([behind(3, 'fake', replied)], 'ctrl+x a')).toStrictEqual({
    text: '✓ 3 fake replied',
    tone: 'plain',
    key: 'ctrl+x a',
  });
  // A failure outranks a reply, and names the one that failed.
  expect(
    waitsNotice([
      behind(3, 'fake', replied),
      behind(4, 'fake', { unseen: { kind: 'failed', since: 30 } }),
    ]),
  ).toStrictEqual({ text: "✗ 4 fake's turn failed", tone: 'ended' });
});

test('a failure says what failed: a turn, a start or an exit; many count each kind, gravest first, with no noun', () => {
  const failed = (failure: 'turn' | 'start' | 'exited', since = 30) => ({
    unseen: { kind: 'failed' as const, since, failure },
    ...(failure === 'exited' ? { exited: true as const } : {}),
  });
  const parser = (wait: Partial<TabWait>): TabBehind => ({
    ...behind(1, 'fake', wait),
    name: 'parser',
  });

  expect(waitsNotice([parser(failed('turn'))])?.text).toStrictEqual(
    "✗ parser's turn failed",
  );
  expect(waitsNotice([parser(failed('start'))])?.text).toStrictEqual(
    '✗ parser failed to start',
  );
  expect(waitsNotice([parser(failed('exited'))])?.text).toStrictEqual(
    '✗ parser exited',
  );
  expect(waitsNotice([behind(1, 'fake', failed('turn'))])?.text).toStrictEqual(
    "✗ 1 fake's turn failed",
  );
  expect(
    waitsNotice(
      [behind(1, 'fake', failed('turn')), behind(2, 'fake', failed('exited'))],
      'ctrl+x a',
    ),
  ).toStrictEqual({
    text: '✗ 1 exited · 1 turn failed',
    tone: 'ended',
    key: 'ctrl+x a',
  });
  expect(
    waitsNotice([
      parser(failed('turn', 10)),
      behind(2, 'fake', failed('turn', 20)),
      behind(3, 'fake', failed('start')),
      behind(4, 'fake', failed('exited')),
      behind(5, 'fake', failed('exited')),
    ])?.text,
  ).toStrictEqual('✗ 2 exited · 1 failed to start · 2 turns failed');
  // Replies alone still count as sessions, which only tabs behind make.
  expect(
    waitsNotice([behind(1, 'fake', replied), behind(2, 'fake', replied)])?.text,
  ).toStrictEqual('✓ 2 sessions replied');
});

test('the waits notice goes ahead of the hint, and the hint goes first', () => {
  const waits = waitsNotice([behind(2, 'claude', permission)], 'ctrl+x a');
  const line = { ...facts, mode: 'default', waits };

  expect(text(line, 116)).toStrictEqual(
    '● 2 claude needs your permission · ctrl+x a to go · ? for shortcuts  Fake Large with a 1M context window · 60% used',
  );
  expect(text(line, 76)).toStrictEqual(
    '● 2 claude needs your permission · ctrl+x a  Fake Large with a… · 60% used',
  );
  expect(statusLine(line, 76).left[0]?.tone).toStrictEqual('waits');
  // With no usage there is room for a cut model, but the hint goes first.
  expect(
    !text({ ...line, usage: undefined }, 76).includes('for shortcuts'),
    'the hint stayed beside a cut model',
  ).toBeTruthy();
  // A message just asked for stands alone.
  expect(
    text({ ...line, notice: 'No session waits' }, 116).split('  ')[0],
  ).toStrictEqual('No session waits');
});

test('a context chord worked out is marked, and a window nobody knows says nothing', () => {
  expect(
    text(
      {
        ...facts,
        mode: 'default',
        usage: { ...usage, estimated: ['size'] },
      },
      116,
    ),
  ).toStrictEqual(
    '? for shortcuts  Fake Large with a 1M context window · ~60% context used',
  );
  // An estimated cost alone leaves the agent's context unmarked.
  expect(
    text(
      {
        ...facts,
        mode: 'default',
        usage: { ...usage, estimated: ['cost'] },
      },
      116,
    ),
  ).toStrictEqual(
    '? for shortcuts  Fake Large with a 1M context window · 60% context used',
  );
  expect(
    text({ ...facts, mode: 'default', usage: { used: 10, size: 0 } }, 116),
  ).toStrictEqual('? for shortcuts  Fake Large with a 1M context window');
});

test('the spinner line follows the turn', () => {
  const since = 1_000;
  const turn = (status: TurnState['status']): TurnState =>
    status === 'idle'
      ? { status }
      : status === 'cancelling'
        ? { status, turnId: 't', since, cancelledAt: since }
        : status === 'awaiting_permission'
          ? { status, turnId: 't', since, permissions: [] }
          : { status, turnId: 't', since };

  expect(workingLine(turn('idle'), 13_000, false, 'esc')).toStrictEqual(
    undefined,
  );
  expect(workingLine(turn('working'), 13_000, false, 'esc')).toStrictEqual({
    label: 'Working…',
    detail: '12s · esc to interrupt',
  });
  // Esc answers the permission prompt there, so the line offers no interrupt.
  expect(
    workingLine(turn('awaiting_permission'), 13_000, false, 'esc'),
  ).toStrictEqual({
    label: 'Waiting for permission…',
    detail: '12s',
  });
  // chord's own question asks no permission.
  expect(
    workingLine(
      {
        status: 'awaiting_permission',
        turnId: 't',
        since,
        permissions: [
          {
            id: 'p',
            options: [],
            save: { question: 'Save team bugfix?', files: {}, escape: 'no' },
          },
        ],
      },
      13_000,
      false,
      'esc',
    ),
  ).toStrictEqual({ label: 'Waiting for you…', detail: '12s' });
  expect(workingLine(turn('cancelling'), 13_000, false, 'esc')).toStrictEqual({
    label: 'Interrupting…',
    detail: '12s',
  });
  // A compaction within the turn is said where Working… was, as Claude Code does.
  expect(
    workingLine(turn('working'), 13_000, false, 'esc', true),
  ).toStrictEqual({
    label: 'Compacting conversation…',
    detail: '12s · esc to interrupt',
  });
});

test('the effort sits between the model and the context, with its word while the line is wide', () => {
  const line = { ...facts, mode: 'default', effort: 'medium' };

  expect(text(line, 116)).toStrictEqual(
    '? for shortcuts  Fake Large with a 1M context window · medium effort · 60% context used',
  );
  expect(statusLine(line, 116).right[1]).toStrictEqual({
    text: 'medium effort',
    tone: 'plain',
  });
  // Short, it loses its word at the step the context loses its own.
  expect(text(line, 76)).toStrictEqual(
    '? for shortcuts  Fake Large with a 1M context window · medium · 60% used',
  );
});

test('the effort goes before the model is cut', () => {
  const line = { ...facts, mode: 'default', effort: 'medium' };

  expect(text(line, 70)).toStrictEqual(
    '? for shortcuts  Fake Large with a 1M context window · 60% used',
  );
  expect(text(line, 55)).toStrictEqual(
    '? for shortcuts  Fake Large with a 1M conte… · 60% used',
  );
  expect(text(line, 30)).toStrictEqual('Fake Large with a… · 60% used');
});

test('no effort offered leaves the line as it was, and an effort with no model stands alone', () => {
  const line = { ...facts, mode: 'default' };

  for (const width of [116, 76, 70, 55, 30]) {
    expect(text({ ...line, effort: undefined }, width)).toStrictEqual(
      text(line, width),
    );
  }

  expect(
    text({ ...line, model: undefined, effort: 'high' }, 116),
  ).toStrictEqual('? for shortcuts  high effort · 60% context used');
});

test('the spinner runs the light mark along three, then rests', () => {
  const mark = {
    stops: ['#89f5b3', '#47e7a5', '#15c7a2'],
    tone: 'greenBright',
  } as const;
  const lit = (step: number) =>
    spinnerMarks(step, mark).map(({ colour }) => colour === '#89f5b3');

  expect(SPINNER_STEPS).toBe(4);
  expect(lit(0)).toStrictEqual([true, false, false]);
  expect(lit(1)).toStrictEqual([false, true, false]);
  expect(lit(2)).toStrictEqual([false, false, true]);
  expect(lit(3)).toStrictEqual([false, false, false]);
  expect(spinnerMarks(1, mark)).toStrictEqual([
    { colour: '#15c7a2', dim: false },
    { colour: '#89f5b3', dim: false },
    { colour: '#15c7a2', dim: false },
  ]);
});

test('with no gradient the spinner dims all but the lit mark, in the one tone', () => {
  expect(spinnerMarks(2, { tone: 'green' })).toStrictEqual([
    { colour: 'green', dim: true },
    { colour: 'green', dim: true },
    { colour: 'green', dim: false },
  ]);
});

describe('CHD-264 tester: grouped failures', () => {
  test('a stale turn cause with an exited process counts as exited, and the narrow notice preserves both groups', () => {
    const turn = {
      unseen: { kind: 'failed' as const, failure: 'turn' as const, since: 1 },
    };
    const entries = [
      behind(1, 'fake', turn),
      behind(2, 'fake', { ...turn, exited: true }),
    ];
    const notice = waitsNotice(entries, 'ctrl+x a');

    expect(notice?.text).toBe('✗ 1 exited · 1 turn failed');
    expect(waitsNotice([...entries].reverse(), 'ctrl+x a')).toStrictEqual(
      notice,
    );
    expect(text({ ...facts, waits: notice }, 76)).toContain(
      '✗ 1 exited · 1 turn failed · ctrl+x a',
    );
    expect(notice?.text).not.toContain('sessions');
    expect(waitsNotice([behind(2, 'fake', { exited: true })])).toBeUndefined();
  });
});

test("a tab behind names a child's failure for the child, in the tab; only its own main's is the tab's", () => {
  const failed = (failure: 'turn' | 'start' | 'exited') => ({
    unseen: { kind: 'failed' as const, since: 30, failure },
  });
  const child = (failure: 'turn' | 'start' | 'exited'): TabBehind => ({
    ...behind(2, 'fake', failed(failure)),
    waiter: 'parser',
  });

  expect(waitsNotice([child('exited')])?.text).toStrictEqual(
    '✗ parser exited in 2 fake',
  );
  expect(waitsNotice([child('turn')])?.text).toStrictEqual(
    "✗ parser's turn failed in 2 fake",
  );
  expect(waitsNotice([child('start')])?.text).toStrictEqual(
    '✗ parser failed to start in 2 fake',
  );
  expect(waitsNotice([behind(2, 'fake', failed('turn'))])?.text).toStrictEqual(
    "✗ 2 fake's turn failed",
  );
});

test("the front session's own request between turns names the key that answers it, short where it must be (CHD-158)", () => {
  const permission = { ...facts, mode: 'default', hint: undefined };
  const waits = betweenNotice('permission', 'ctrl+x a');

  expect(text({ ...permission, waits }, 120)).toStartWith(
    '● permission asked between turns · ctrl+x a to answer  ',
  );
  expect(text({ ...permission, waits }, 80)).toStartWith(
    '● permission · ctrl+x a to answer  ',
  );
  expect(
    text({ ...permission, waits: betweenNotice('input', 'ctrl+x a') }, 120),
  ).toStartWith('● input asked between turns · ctrl+x a to answer  ');
  expect(
    text({ ...permission, waits: betweenNotice('input', 'ctrl+x a') }, 80),
  ).toStartWith('● input · ctrl+x a to answer  ');
});

test('an asking task is named as its box names it, or by whose task it is where that does not fit (CHD-431)', () => {
  const asking = (on: 'permission' | 'input'): TabWait => ({
    ...idle,
    asking: {
      on:
        on === 'permission'
          ? { kind: 'permission', subagentId: 'task-1' }
          : { kind: 'input', message: 'Which?', subagentId: 'task-1' },
      since: 0,
    },
  });
  const main = (on: 'permission' | 'input'): TabBehind => ({
    number: 0,
    agent: 'main',
    name: 'main',
    wait: asking(on),
    task: 'Agent(Fix the tokenizer) · fake',
  });
  const line = {
    ...facts,
    mode: 'default',
    hint: undefined,
    waits: waitsNotice([main('permission')], 'ctrl+x a'),
  };

  expect(text(line, 120)).toStartWith(
    '● Agent(Fix the tokenizer) · fake needs your permission · ctrl+x a to go  ',
  );
  expect(text(line, 80)).toStartWith(
    "● main's task needs your permission · ctrl+x a  ",
  );
  expect(waitsNotice([main('input')], 'ctrl+x a')?.text).toStrictEqual(
    '● Agent(Fix the tokenizer) · fake asks for input',
  );

  // Two asking are counted as ever, a task as one agent.
  const tester: TabBehind = {
    number: 0,
    agent: 'tester',
    name: 'tester',
    wait: asking('input'),
  };

  expect(
    waitsNotice([main('permission'), tester], 'ctrl+x a')?.text,
  ).toStrictEqual('● 2 agents wait');
});

describe('CHD-431 tester: task hints preserve identity and fit', () => {
  const owner = (
    name: string,
    task: string,
    kind: 'permission' | 'input' = 'permission',
  ): TabBehind => ({
    number: 0,
    agent: name,
    name,
    task,
    wait: {
      ...idle,
      asking: {
        since: 0,
        on:
          kind === 'permission'
            ? { kind, subagentId: task }
            : { kind, message: 'Question', subagentId: task },
      },
    },
  });

  for (const kind of ['permission', 'input'] as const) {
    test(`a very long child's task ${kind} uses its owner without truncating the task or dropping the model`, () => {
      const waits = waitsNotice(
        [owner('parser', `Agent(${'tokenizer '.repeat(40)}) · fake`, kind)],
        'ctrl+y',
      );
      const line = text(
        { ...facts, mode: 'default', hint: undefined, waits },
        80,
      );

      expect(line).toContain(
        `● parser's task ${kind === 'permission' ? 'needs your permission' : 'asks for input'} · ctrl+y`,
      );
      expect(line).toContain('Fake Large');
      expect(line).not.toContain('tokenizer');
      expect(stringWidth(line)).toBeLessThanOrEqual(80);
    });
  }

  test('a task and a different tab count as sessions, then show the remaining task after the other settles', () => {
    const task = owner('parser', 'Agent(Fix the tokenizer) · fake');
    const other: TabBehind = {
      number: 2,
      agent: 'fake',
      wait: {
        ...idle,
        asking: { on: { kind: 'input', message: 'Form' }, since: 5 },
      },
    };

    expect(waitsNotice([task, other], 'ctrl+x a')?.text).toBe(
      '● 2 sessions wait',
    );
    expect(waitsNotice([task], 'ctrl+x a')?.text).toBe(
      '● Agent(Fix the tokenizer) · fake needs your permission',
    );
    expect(waitsNotice([], 'ctrl+x a')).toBeUndefined();
  });
});
