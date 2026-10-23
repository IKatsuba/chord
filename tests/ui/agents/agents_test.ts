import { describe, expect, test } from 'bun:test';
import stringWidth from 'string-width';
import { emptyWatch } from '../../../src/notify.ts';
import type { AgentWait } from '../../../src/session/waits.ts';
import {
  type AgentRow,
  agentsHeight,
  agentsHint,
  agentsLines,
  agentsLayout,
  agentsRowLimit,
  type AgentsView,
  enteredView,
  agentMark,
  agentState,
  childLine,
  leftOpenLine,
  listRows,
  listTimed,
  moveListFocus,
  scrolledView,
  summaryHint,
  teamRows,
} from '../../../src/ui/agents/agents.ts';

const NOW = 100_000;

/** No summary line under the agents. */
const NO_SUMMARY = { summary: false, onSummary: false };

function row(
  name: string,
  more: Omit<Partial<AgentRow>, 'wait'> & { wait?: Partial<AgentWait> } = {},
): AgentRow {
  const { wait, ...rest } = more;

  return {
    key: name.length,
    name,
    runtime: 'codex',
    model: 'gpt-5.3-codex',
    picked: false,
    failed: false,
    ...rest,
    wait: { watch: emptyWatch, ...wait },
  };
}

/** The rows as the list draws them, without the colours. */
function drawn(
  rows: readonly AgentRow[],
  {
    limit = 4,
    width = 116,
    focused = false,
    view,
  }: {
    limit?: number;
    width?: number;
    focused?: boolean;
    view?: AgentsView | undefined;
  } = {},
): string[] {
  const layout = agentsLayout(rows, { limit, width, focused, now: NOW, view });

  return [
    ...layout.rows.flatMap((laid) =>
      laid.lines.map(({ at, gutter }) => {
        if (at === 0) {
          return `${gutter}${laid.branch ?? ''}${laid.name}  ${laid.detail}${
            laid.state === undefined ? '' : `  ${laid.state.text}`
          }${laid.unseen === undefined ? '' : `  ${laid.unseen.text}`}`.trimEnd();
        }

        // A wrapped row's further lines: the name's, what went under the
        // detail.
        const name = laid.names[at - 1];
        const below = (laid.below[at - 1] ?? [])
          .map(({ text }) => text)
          .join('');

        return `${gutter}${
          name === undefined
            ? ' '.repeat(laid.nameWidth)
            : name.tree + name.text
        }${below === '' ? '' : `  ${below}`}`.trimEnd();
      }),
    ),
    ...(layout.more > 0 ? [`  … +${layout.more} more`] : []),
  ];
}

const MAIN = row('main', { runtime: 'claude', model: 'Opus', picked: true });
const PARSER = row('parser', { wait: { working: NOW - 41_000 } });
const DOCS = row('docs', {
  runtime: 'claude',
  model: 'Sonnet',
  wait: { unseen: { kind: 'message', from: '@main', since: NOW } },
});

test('each agent is a row of its name, runtime and model, and state, in columns', () => {
  expect(drawn([MAIN, PARSER, DOCS])).toStrictEqual([
    '  main    claude · Opus          ◦ idle 0s',
    '  parser  codex · gpt-5.3-codex  ✻ working 41s',
    '  docs    claude · Sonnet        ◦ idle 0s      ← new message',
  ]);
});

test('the picked row is marked while the list has the keys', () => {
  expect(
    drawn(
      [MAIN, { ...PARSER, picked: true }].map((each, index) =>
        index === 0 ? { ...each, picked: false } : each,
      ),
      { focused: true },
    ),
  ).toStrictEqual([
    '  main    claude · Opus          ◦ idle 0s',
    '❯ parser  codex · gpt-5.3-codex  ✻ working 41s',
  ]);
});

test('an agent always has one state, most urgent first, and what is not yet seen is a mark beside it (CHD-471)', () => {
  const state = (wait: Partial<AgentWait>, more: Partial<AgentRow> = {}) => {
    const found = agentState(row('x', { ...more, wait }), NOW);

    return `${found.glyph} ${found.words} (${found.tone})`;
  };

  const mark = (wait: Partial<AgentWait>) => {
    const found = agentMark(row('x', { wait }));

    return found && `${found.glyph} ${found.words} (${found.tone})`;
  };

  expect(
    state({ asking: { on: { kind: 'permission' }, since: NOW - 12_000 } }),
  ).toStrictEqual('● permission 12s (warning)');
  expect(
    state({ asking: { on: { kind: 'input', message: 'Go?' }, since: NOW } }),
  ).toStrictEqual('● input 0s (warning)');
  expect(state({}, { failed: true })).toStrictEqual(
    '✗ failed to start (error)',
  );
  expect(state({ exited: true })).toStrictEqual('✗ exited (error)');
  expect(state({ working: NOW - 62_000 })).toStrictEqual(
    '✻ working 1m 2s (working)',
  );
  // Idle since it last stopped, in its first unit.
  expect(state({ stopped: NOW - 190_000 })).toStrictEqual('◦ idle 3m (dim)');

  // A failed turn leaves the agent open and idle: the failure is a mark.
  const failed = {
    stopped: NOW - 12_000,
    unseen: {
      kind: 'failed' as const,
      since: NOW - 12_000,
      failure: 'turn' as const,
    },
  };

  expect(state(failed)).toStrictEqual('◦ idle 12s (dim)');
  expect(mark(failed)).toStrictEqual('✗ turn failed (error)');
  expect(mark({ unseen: { kind: 'replied', since: NOW } })).toStrictEqual(
    '✓ new reply (dim)',
  );
  expect(
    mark({ unseen: { kind: 'message', from: '@main', since: NOW } }),
  ).toStrictEqual('← new message (dim)');
  // Its state says it is gone; that is no mark.
  expect(
    mark({
      exited: true,
      unseen: { kind: 'failed', since: NOW, failure: 'exited' },
    }),
  ).toStrictEqual(undefined);
  expect(mark({})).toStrictEqual(undefined);
});

test('past its rows the list ends in … +N more, and moves so the picked row shows while it has the keys', () => {
  const rows = ['main', 'a', 'b', 'c', 'd', 'e'].map((name, index) =>
    row(name, { key: index, picked: name === 'e', model: undefined }),
  );

  expect(agentsRowLimit(24)).toStrictEqual(4);
  expect(agentsRowLimit(40)).toStrictEqual(6);
  expect(drawn(rows, { limit: 4 })).toStrictEqual([
    '  main  codex  ◦ idle 0s',
    '  a     codex  ◦ idle 0s',
    '  b     codex  ◦ idle 0s',
    '  … +3 more',
  ]);
  expect(drawn(rows, { limit: 4, focused: true })).toStrictEqual([
    '  c     codex  ◦ idle 0s',
    '  d     codex  ◦ idle 0s',
    '❯ e     codex  ◦ idle 0s',
    '  … +3 more',
  ]);
});

test("a narrow list drops the model, then puts a row's state under its detail, and wraps a long name in a third of the width, cutting nothing (CHD-471)", () => {
  const long = row('the-long-parser-name', {
    wait: { working: NOW - 41_000 },
  });

  expect(drawn([MAIN, PARSER], { width: 36 })).toStrictEqual([
    '  main    claude  ◦ idle 0s',
    '  parser  codex   ✻ working 41s',
  ]);
  expect(drawn([MAIN, PARSER], { width: 20, limit: 6 })).toStrictEqual([
    '  main    claude',
    '          ◦ idle 0s',
    '  parser  codex',
    '          ✻ working',
    '          41s',
  ]);
  expect(drawn([long], { width: 20, limit: 6 })).toStrictEqual([
    '  the-lo  codex',
    '  ng-par  ✻ working',
    '  ser-na  41s',
    '  me',
  ]);
  // Each wrapped row counts its lines toward the limit.
  expect(drawn([MAIN, PARSER], { width: 20 })).toStrictEqual([
    '  main    claude',
    '          ◦ idle 0s',
    '  … +1 more',
  ]);
});

test("a row's effort follows its model, and a narrow list drops it a step before the model", () => {
  const main = { ...MAIN, effort: 'high' };
  const parser = { ...PARSER, effort: 'xhigh' };

  expect(drawn([main, parser])).toStrictEqual([
    '  main    claude · Opus · high           ◦ idle 0s',
    '  parser  codex · gpt-5.3-codex · xhigh  ✻ working 41s',
  ]);
  expect(drawn([main, parser], { width: 50 })).toStrictEqual([
    '  main    claude · Opus          ◦ idle 0s',
    '  parser  codex · gpt-5.3-codex  ✻ working 41s',
  ]);
  expect(drawn([main, parser], { width: 36 })).toStrictEqual([
    '  main    claude  ◦ idle 0s',
    '  parser  codex   ✻ working 41s',
  ]);
});

test('the hint says what the keys do, shorter at 80 columns', () => {
  expect(agentsHint(116, 'x')).toStrictEqual(
    '↑ ↓ to pick · enter to write to it · x to close · esc to go back',
  );
  expect(agentsHint(76, 'x')).toStrictEqual(
    '↑ ↓ pick · enter write · x close · esc back',
  );
  expect(agentsHint(76, undefined)).toStrictEqual(
    '↑ ↓ pick · enter write · esc back',
  );
});

test("a child's transcript opens with its name, runtime, model and who opened it when", () => {
  const line = childLine(
    { name: 'parser', runtime: 'codex', openedAt: NOW - 240_000 },
    'gpt-5.3-codex',
    NOW,
  );

  expect(line.name + line.rest).toStrictEqual(
    'parser · codex · gpt-5.3-codex · opened by main 4m ago',
  );
});

test("a team's lead and member transcripts say so in their first line, and who opened them", () => {
  const lead = childLine(
    {
      name: 'bugfix',
      runtime: 'claude',
      team: 'bugfix',
      openedAt: NOW - 420_000,
    },
    'Opus',
    NOW,
  );
  const member = childLine(
    {
      name: 'tester',
      runtime: 'claude',
      team: 'bugfix',
      leadName: 'bugfix 2',
      openedAt: NOW - 360_000,
    },
    'Sonnet',
    NOW,
  );

  expect(lead.name + lead.rest).toStrictEqual(
    'bugfix · team · claude · Opus · opened by @main 7m ago',
  );
  expect(member.name + member.rest).toStrictEqual(
    "tester · claude · Sonnet · bugfix 2's member · opened by @bugfix 2 6m ago",
  );
});

test('the closing note of a resumed session names each agent left open with its runtime', () => {
  expect(leftOpenLine([{ name: 'parser', runtime: 'codex' }])).toStrictEqual(
    'parser (codex) was open when this session was left and is not ' +
      'reopened · /resume lists it',
  );
  expect(
    leftOpenLine([
      { name: 'parser', runtime: 'codex' },
      { name: 'docs', runtime: 'claude' },
    ]),
  ).toStrictEqual(
    'parser (codex) and docs (claude) were open when this session was left ' +
      'and are not reopened · /resume lists them',
  );
  expect(
    leftOpenLine([
      { name: 'parser', runtime: 'codex' },
      { name: 'docs', runtime: 'claude' },
      { name: 'printer', runtime: 'gemini' },
    ]).split(' were ')[0],
  ).toStrictEqual('parser (codex), docs (claude), and printer (gemini)');
});

test("the closing note counts each team run as one item, with its agents, and names each team's /team run once", () => {
  const parser = { name: 'parser', runtime: 'codex' };
  const bugfix = {
    name: 'bugfix',
    runtime: 'claude',
    team: 'bugfix',
    agents: 4,
  };

  expect(leftOpenLine([parser, bugfix])).toStrictEqual(
    'parser (codex) and team bugfix (4 agents) were open when this session ' +
      'was left and are not reopened · /resume lists them · /team run ' +
      'bugfix starts the team again',
  );
  // /resume lists the lead and each member, so even one run is "them".
  expect(leftOpenLine([{ ...bugfix, agents: 1 }])).toStrictEqual(
    'team bugfix (1 agent) was open when this session was left and is not ' +
      'reopened · /resume lists them · /team run bugfix starts the team again',
  );
  expect(
    leftOpenLine([
      bugfix,
      { ...bugfix, name: 'bugfix 2', agents: 3 },
      { name: 'docs', runtime: 'claude', team: 'docs', agents: 2 },
    ]),
  ).toStrictEqual(
    'team bugfix (4 agents), team bugfix 2 (3 agents), and team docs ' +
      '(2 agents) were open when this session was left and are not ' +
      'reopened · /resume lists them · /team run bugfix and /team run docs ' +
      'start the teams again',
  );
});

test('↑ ↓ move the ❯ through the agents on to the summary line, its last stop; with no agents it is the one stop', () => {
  const rows = listRows([MAIN, PARSER]);
  const on = { summary: true, onSummary: true };
  const off = { summary: true, onSummary: false };

  expect(moveListFocus(rows, 1, off)).toStrictEqual({ kind: 'agent', key: 6 });
  expect(moveListFocus(rows, 2, off)).toStrictEqual({ kind: 'summary' });
  // The last stays the last.
  expect(moveListFocus(rows, 1, on)).toStrictEqual({ kind: 'summary' });
  // ↑ from it goes back to the last agent row.
  expect(moveListFocus(rows, -1, on)).toStrictEqual({ kind: 'agent', key: 6 });
  // No summary line drawn: the agents alone, the last staying the last.
  expect(
    moveListFocus(rows, 2, { summary: false, onSummary: false }),
  ).toStrictEqual({ kind: 'agent', key: 6 });
  // Above the first row, the keys go back to the box.
  expect(moveListFocus(rows, -1, off)).toStrictEqual(undefined);
  expect(moveListFocus([], 1, off)).toStrictEqual({ kind: 'summary' });
  expect(moveListFocus([], -1, off)).toStrictEqual(undefined);
  expect(
    moveListFocus([], 1, { summary: false, onSummary: false }),
  ).toStrictEqual(undefined);
});

test('the ❯ leaves the agent rows while the summary line has it, the agent staying picked', () => {
  const rows = listRows([MAIN, PARSER]);

  expect(drawn(rows, { focused: true })[0]!.slice(0, 2)).toStrictEqual('❯ ');
  expect(
    drawn(rows, { focused: false }).map((line) => line.slice(0, 2)),
  ).toStrictEqual(['  ', '  ']);
});

test("the summary line's hint says it opens, shorter at 80 columns", () => {
  expect(summaryHint(116)).toStrictEqual(
    '↑ ↓ to move · enter to open · esc to go back',
  );
  expect(summaryHint(76)).toStrictEqual('↑ ↓ move · enter open · esc back');
});

/**
 * CHD-240's team at work: `bugfix` with three members, `tester` asking,
 * and `parser`, an M4 child, after it; `picked` has the prompt.
 */
function team(picked = 'main'): AgentRow[] {
  return [
    row('main', { key: 1, runtime: 'claude', model: 'Opus' }),
    row('bugfix', {
      key: 2,
      runtime: 'team · claude',
      model: 'Opus',
      team: 2,
      wait: { unseen: { kind: 'replied', since: NOW - 40_000 } },
    }),
    row('tester', {
      key: 3,
      runtime: 'claude',
      model: 'Sonnet',
      team: 2,
      wait: { asking: { on: { kind: 'permission' }, since: NOW - 12_000 } },
    }),
    row('coder', { key: 4, team: 2 }),
    row('reviewer', {
      key: 5,
      runtime: 'claude',
      model: 'Opus',
      team: 2,
      wait: { unseen: { kind: 'replied', since: NOW - 60_000 } },
    }),
    row('parser', { key: 6, wait: { working: NOW - 9_000 } }),
  ].map((each) => ({ ...each, picked: each.name === picked }));
}

test("a team's members nest under its lead with CHD-149's branches, as 120-4-team-list.txt draws them", () => {
  expect(drawn(listRows(team(), 6), { limit: 6 })).toStrictEqual([
    '  main         claude · Opus          ◦ idle 0s',
    '  bugfix       team · claude · Opus   ◦ idle 0s         ✓ new reply',
    '  ├─ tester    claude · Sonnet        ● permission 12s',
    '  ├─ coder     codex · gpt-5.3-codex  ◦ idle 0s',
    '  └─ reviewer  claude · Opus          ◦ idle 0s         ✓ new reply',
    '  parser       codex · gpt-5.3-codex  ✻ working 9s',
  ]);
});

test('a list that does not fit folds each team to its lead, its size and its most urgent state naming the member', () => {
  expect(drawn(listRows(team(), 4), { limit: 4, width: 76 })).toStrictEqual([
    '  main         claude                    ◦ idle 0s',
    '  bugfix       team · claude · 4 agents  ● tester: permission 12s  ✓',
    '  parser       codex                     ✻ working 9s',
  ]);

  // A model too long for the row drops the models; the size stays, as it
  // says more.
  const long = team().map((each) =>
    each.name === 'main'
      ? { ...each, model: 'Fake Large with a 1M context window' }
      : each,
  );

  expect(
    drawn(listRows(long, 4), { limit: 4, width: 76 }).slice(0, 2),
  ).toStrictEqual([
    '  main         claude                    ◦ idle 0s',
    '  bugfix       team · claude · 4 agents  ● tester: permission 12s  ✓',
  ]);
});

test('the team the pick is in unfolds, and the list scrolls to it while it has the keys', () => {
  const rows = (picked: string) => listRows(team(picked), 4);

  expect(
    drawn(rows('bugfix'), { limit: 4, width: 76, focused: true }),
  ).toStrictEqual([
    '  main         claude · Opus          ◦ idle 0s',
    '❯ bugfix       team · claude · Opus   ◦ idle 0s         ✓ new reply',
    '  ├─ tester    claude · Sonnet        ● permission 12s',
    '  … +3 more',
  ]);
  // ctrl+x a picks tester without the list having the keys: still unfolded.
  expect(rows('tester').map((each) => each.name)).toStrictEqual([
    'main',
    'bugfix',
    'tester',
    'coder',
    'reviewer',
    'parser',
  ]);
  // ↑ ↓ walk the rows as drawn: onto a folded lead, then into its members.
  expect(moveListFocus(rows('parser'), -1, NO_SUMMARY)).toStrictEqual({
    kind: 'agent',
    key: 2,
  });
  expect(moveListFocus(rows('bugfix'), 1, NO_SUMMARY)).toStrictEqual({
    kind: 'agent',
    key: 3,
  });
  expect(moveListFocus(rows('reviewer'), 1, NO_SUMMARY)).toStrictEqual({
    kind: 'agent',
    key: 6,
  });
});

test('two runs fold one by one, each with its own state', () => {
  const second = team()
    .slice(1, 5)
    .map((each) => ({
      ...each,
      key: each.key + 10,
      team: 12,
      name: each.name === 'bugfix' ? 'bugfix 2' : each.name,
      wait:
        each.name === 'tester'
          ? {
              watch: each.wait.watch,
              asking: {
                on: { kind: 'permission' as const },
                since: NOW - 5_000,
              },
            }
          : { watch: each.wait.watch },
    }));
  const first = team()
    .slice(0, 5)
    .map((each) =>
      each.name === 'coder'
        ? { ...each, wait: { ...each.wait, working: NOW - 61_000 } }
        : { ...each, wait: { watch: each.wait.watch } },
    );
  const rows = (picked?: number) =>
    listRows(
      [...first, ...second].map((each) => ({
        ...each,
        picked: each.key === (picked ?? 1),
      })),
      6,
    );

  expect(drawn(rows(), { limit: 6 })).toStrictEqual([
    '  main         claude · Opus             ◦ idle 0s',
    '  bugfix       team · claude · 4 agents  ✻ coder: working 1m 1s',
    '  bugfix 2     team · claude · 4 agents  ● tester: permission 5s',
  ]);
  // The run picked unfolds; the other stays folded, so all six rows fit.
  expect(drawn(rows(13), { limit: 6, focused: true })).toStrictEqual([
    '  main         claude · Opus             ◦ idle 0s',
    '  bugfix       team · claude · 4 agents  ✻ coder: working 1m 1s',
    '  bugfix 2     team · claude · Opus      ◦ idle 0s',
    '❯ ├─ tester    claude · Sonnet           ● permission 5s',
    '  ├─ coder     codex · gpt-5.3-codex     ◦ idle 0s',
    '  └─ reviewer  claude · Opus             ◦ idle 0s',
  ]);
});

test("a folded lead's own state is its own, and a lead with no member open folds nothing", () => {
  const [main, lead, ...members] = team('main');
  const failed = { ...lead!, failed: true };

  expect(
    drawn(teamRows([main!, failed, ...members], { fold: true }), {
      limit: 9,
    })[1],
  ).toStrictEqual(
    '  bugfix       team · claude · 4 agents  ● tester: permission 12s  ✓ new reply',
  );
  expect(
    drawn(teamRows([main!, failed, ...members.slice(1, 3)], { fold: true }), {
      limit: 9,
    })[1],
  ).toStrictEqual(
    '  bugfix       team · claude · 3 agents  ✗ failed to start  ✓ new reply',
  );
  expect(teamRows([main!, lead!], { fold: true })[1]).toStrictEqual(lead);
});

test("the list ticks while any agent on it is open, an idle one's time counting too, and not once all are gone (CHD-471)", () => {
  const idle = team().map((each) => ({ ...each, wait: { watch: emptyWatch } }));

  expect(listTimed(listRows(idle, 4))).toStrictEqual(true);
  expect(
    listTimed(
      idle.map((each) => ({
        ...each,
        wait: { watch: emptyWatch, exited: true as const },
      })),
    ),
  ).toStrictEqual(false);
});

test('an exit and never starting are states, gravest first; a failed turn is a mark the agent reads idle beside, gone once seen', () => {
  const words = (wait: Partial<AgentWait>, more: Partial<AgentRow> = {}) =>
    agentState(row('x', { ...more, wait: { watch: emptyWatch, ...wait } }), NOW)
      .words;
  const turn = {
    kind: 'failed' as const,
    since: NOW - 60_000,
    failure: 'turn' as const,
  };

  expect(words({ unseen: turn, stopped: NOW - 60_000 })).toStrictEqual(
    'idle 1m',
  );
  expect(agentMark(row('x', { wait: { unseen: turn } }))?.words).toStrictEqual(
    'turn failed',
  );
  expect(words({ unseen: turn, exited: true })).toStrictEqual('exited');
  expect(words({ unseen: turn }, { failed: true })).toStrictEqual(
    'failed to start',
  );
  expect(words({ exited: true }, { failed: true })).toStrictEqual('exited');
  // Asking still comes first.
  expect(
    words({
      unseen: turn,
      exited: true,
      asking: { on: { kind: 'permission' }, since: NOW },
    }),
  ).toStrictEqual('permission 0s');
  // Seen, a failed turn leaves no mark.
  expect(agentMark(row('x'))).toStrictEqual(undefined);
  // An exit and never starting stay until the agent is closed, seen or not.
  expect(words({ exited: true })).toStrictEqual('exited');
  expect(words({}, { failed: true })).toStrictEqual('failed to start');
});

test("a folded lead names the member that is gone, gravest first, and its mark is the first of its agents' unnamed", () => {
  const [main, lead, ...members] = team('main');
  const quiet = (each: AgentRow): AgentRow => ({
    ...each,
    wait: { watch: emptyWatch, stopped: NOW - 30_000 },
  });
  const rows = [
    main!,
    quiet(lead!),
    ...members.map((member) =>
      member.name === 'tester'
        ? {
            ...member,
            wait: {
              watch: emptyWatch,
              stopped: NOW - 12_000,
              unseen: {
                kind: 'failed' as const,
                since: NOW - 12_000,
                failure: 'turn' as const,
              },
            },
          }
        : member.name === 'coder'
          ? { ...member, wait: { watch: emptyWatch, exited: true as const } }
          : quiet(member),
    ),
  ];

  expect(
    drawn(teamRows(rows, { fold: true }), { limit: 9, width: 116 })[1],
  ).toStrictEqual(
    '  bugfix       team · claude · 4 agents  ✗ coder: exited  ✗ turn failed',
  );
  // All idle: from the one that stopped last.
  expect(
    drawn(
      teamRows(
        rows.map((each) => (each.name === 'coder' ? quiet(each) : each)),
        { fold: true },
      ),
      { limit: 9, width: 116 },
    )[1],
  ).toStrictEqual(
    '  bugfix       team · claude · 4 agents  ◦ idle 12s  ✗ turn failed',
  );
});

describe('CHD-264 tester: failure age and row fallback', () => {
  test('an idle failed turn has a timeless mark, and a narrow row retains its error glyph', () => {
    const failed = row('parser', {
      wait: {
        unseen: {
          kind: 'failed',
          failure: 'turn',
          since: NOW - 120_000,
          failedAt: NOW - 12_000,
        },
      },
    });

    expect(agentState(failed, NOW).words).toBe('idle 0s');
    expect(agentMark(failed)).toEqual({
      glyph: '✗',
      words: 'turn failed',
      tone: 'error',
    });
    expect(drawn([MAIN, failed], { width: 76 }).join(' ')).toContain(
      '◦ idle 0s  ✗ turn failed',
    );
    expect(drawn([MAIN, failed], { width: 20, limit: 6 }).join(' ')).toContain(
      '✗',
    );
    expect(
      agentState({ ...failed, wait: { ...failed.wait, exited: true } }, NOW)
        ?.words,
    ).toBe('exited');
    expect(
      agentMark({ ...failed, wait: { ...failed.wait, exited: true } }),
    ).toBeUndefined();
  });
});

test("a reply not yet seen is a mark with no time: the agent's own time says when it stopped, in a row and a folded lead (CHD-471)", () => {
  const reply = { kind: 'replied' as const, since: NOW - 23_000 };
  const parser = row('parser', {
    wait: { watch: emptyWatch, stopped: NOW - 1_000, unseen: reply },
  });

  expect(agentState(parser, NOW).words).toStrictEqual('idle 1s');
  expect(agentMark(parser)?.words).toStrictEqual('new reply');

  const [main, lead, ...members] = team('main');
  const quiet = (each: AgentRow): AgentRow => ({
    ...each,
    wait: { watch: emptyWatch, stopped: NOW - 30_000 },
  });
  const folded = teamRows(
    [
      main!,
      quiet(lead!),
      ...members.map((member) =>
        member.name === 'coder'
          ? {
              ...member,
              wait: { watch: emptyWatch, stopped: NOW - 1_000, unseen: reply },
            }
          : quiet(member),
      ),
    ],
    { fold: true },
  );

  expect(agentState(folded[1]!, NOW).words).toStrictEqual('idle 1s');
  expect(agentMark(folded[1]!)?.words).toStrictEqual('new reply');
});

test("a narrow list drops a mark's words before the state's, each leaving its glyph (CHD-471)", () => {
  const replied = row('parser', {
    wait: {
      stopped: NOW - 13_000,
      unseen: { kind: 'replied', since: NOW },
    },
  });
  const rows = [
    { ...MAIN, wait: { ...MAIN.wait, stopped: NOW - 4_000 } },
    replied,
  ];

  expect(drawn(rows)).toStrictEqual([
    '  main    claude · Opus          ◦ idle 4s',
    '  parser  codex · gpt-5.3-codex  ◦ idle 13s  ✓ new reply',
  ]);
  expect(drawn(rows, { width: 40 })).toStrictEqual([
    '  main    claude  ◦ idle 4s',
    '  parser  codex   ◦ idle 13s  ✓',
  ]);
  // Narrower still, each state goes whole under its detail, its mark after it.
  expect(drawn(rows, { width: 22, limit: 6 })).toStrictEqual([
    '  main    claude',
    '          ◦ idle 4s',
    '  parser  codex',
    '          ◦ idle 13s',
    '          ✓',
  ]);
});

describe('CHD-471 tester: state and unseen marks are independent', () => {
  test('working retains an older reply and a gone agent is no longer timed', () => {
    const working = row('parser', {
      wait: {
        working: NOW - 9000,
        stopped: NOW - 30000,
        unseen: { kind: 'replied', since: NOW - 20000 },
      },
    });

    expect(agentState(working, NOW).words).toBe('working 9s');
    expect(agentState(working, NOW + 2000).words).toBe('working 11s');
    expect(agentMark(working)?.words).toBe('new reply');
    expect(drawn([working]).join(' ')).toContain('✻ working 9s  ✓ new reply');
    expect(listTimed([working])).toBe(true);
    expect(
      listTimed([{ ...working, wait: { watch: emptyWatch, exited: true } }]),
    ).toBe(false);
  });

  test('folding ranks state and marks independently, with idle from the latest stop', () => {
    const [main, lead, ...members] = team('main');
    const rows = [main!, lead!, ...members].map((each, index) => ({
      ...each,
      wait: { watch: emptyWatch, stopped: NOW - (index + 1) * 10000 },
    }));
    const marked = rows.map((each) => ({
      ...each,
      wait: {
        ...each.wait,
        ...(each.name === 'tester'
          ? {
              asking: {
                on: { kind: 'permission' as const },
                since: NOW - 4000,
              },
              unseen: { kind: 'message' as const, from: '@main', since: NOW },
            }
          : each.name === 'coder'
            ? {
                unseen: { kind: 'replied' as const, since: NOW },
              }
            : each.name === 'reviewer'
              ? {
                  unseen: {
                    kind: 'failed' as const,
                    failure: 'turn' as const,
                    since: NOW,
                  },
                }
              : {}),
      },
    }));
    const folded = teamRows(marked, { fold: true })[1]!;

    expect(agentState(folded, NOW).words).toBe('tester: permission 4s');
    expect(agentMark(folded)?.words).toBe('turn failed');

    const noFailure = teamRows(
      marked.filter((each) => each.name !== 'reviewer'),
      { fold: true },
    )[1]!;

    expect(agentMark(noFailure)?.words).toBe('new reply');

    const quiet = teamRows(rows, { fold: true })[1]!;

    expect(agentState(quiet, NOW).words).toBe('idle 20s');
    expect(agentMark(quiet)).toBeUndefined();
  });
});

describe('CHD-471 a row that does not fit wraps, and counts its lines', () => {
  const asking = (since: number) => ({
    asking: { on: { kind: 'permission' as const }, since: NOW - since },
  });
  const rows = [
    row('main', { key: 1, runtime: 'fake', wait: { stopped: NOW - 4_000 } }),
    row('parser', {
      key: 2,
      runtime: 'fake',
      wait: {
        stopped: NOW - 13_000,
        unseen: { kind: 'replied', since: NOW },
      },
    }),
    row('docs', {
      key: 3,
      runtime: 'fake',
      wait: {
        ...asking(17_000),
        unseen: { kind: 'message', from: '@main', since: NOW },
      },
    }),
    row('bugfix', {
      key: 4,
      runtime: 'team · fake',
      team: 4,
      wait: { stopped: NOW, unseen: { kind: 'replied', since: NOW } },
    }),
    row('tester', { key: 5, runtime: 'fake', team: 4, wait: asking(8_000) }),
    row('coder', { key: 6, runtime: 'fake', team: 4 }),
  ];
  const height = (width: number) => (laid: readonly AgentRow[]) =>
    agentsHeight(laid, { width, now: NOW });

  test("only a row whose detail leaves its state no room puts it under the detail, the others' column set without it", () => {
    const folded = listRows(rows, 5, height(39));

    expect(drawn(folded, { width: 39, limit: 5 })).toStrictEqual([
      '  main       fake  ◦ idle 4s',
      '  parser     fake  ◦ idle 13s        ✓',
      '  docs       fake  ● permission 17s  ←',
      '  bugfix     team · fake · 3 agents',
      '             ● tester: permission 8s  ✓',
    ]);
  });

  test("a team folds when its rows' lines, not its rows, pass the limit, so the width can fold it", () => {
    expect(listRows(rows, 6, height(116))).toHaveLength(6);
    // At 30 the states go under, two lines a row: the team folds.
    expect(listRows(rows, 6, height(30))).toHaveLength(4);
  });

  test('past the limit the list keeps whole rows, the picked one among them, and counts the rest', () => {
    const picked = rows.map((each) => ({
      ...each,
      picked: each.name === 'coder',
    }));

    expect(drawn(picked, { width: 30, limit: 5, focused: true })).toStrictEqual(
      [
        '  tester  fake',
        '          ● permission 8s',
        '❯ coder   fake  ◦ idle 0s',
        '  … +4 more',
      ],
    );
  });

  test("a member's long name wraps behind the tree's │, and the last member's behind spaces", () => {
    const named = [
      row('main', { key: 1, runtime: 'fake' }),
      row('bugfix', { key: 2, runtime: 'team · fake', team: 2 }),
      row('tester-with-a-long-name', { key: 3, runtime: 'fake', team: 2 }),
      row('coder-with-a-long-name', { key: 4, runtime: 'fake', team: 2 }),
    ];

    expect(
      drawn(teamRows(named, { fold: false }), { width: 60, limit: 9 }),
    ).toStrictEqual([
      '  main                  fake         ◦ idle 0s',
      '  bugfix                team · fake  ◦ idle 0s',
      '  ├─ tester-with-a-lon  fake         ◦ idle 0s',
      '  │  g-name',
      '  └─ coder-with-a-long  fake         ◦ idle 0s',
      '     -name',
    ]);
  });
});

test('a detail wider than its line on its own wraps under its start, inside a word only where the word alone is wider, and the state follows under it (CHD-471)', () => {
  const rows = [
    row('main', { key: 1, runtime: 'fake', model: undefined }),
    row('parser', {
      key: 2,
      runtime: 'a-runtime-named-past-the-line and more words',
      model: undefined,
      wait: { stopped: NOW - 4_000 },
    }),
  ];

  expect(drawn(rows, { width: 30, limit: 9 })).toStrictEqual([
    '  main    fake  ◦ idle 0s',
    '  parser  a-runtime-named-past',
    '          -the-line and more',
    '          words',
    '          ◦ idle 4s',
  ]);
});

describe('CHD-471 a row taller than the list is read by line, the list never past its limit', () => {
  const title =
    'Summarise the release notes for 0.56.0 from the commits since 0.55.2, grouped by area, with a line for each user-facing change and a note for each breaking one, then draft the announcement for the forum and the changelog entry, and list the open questions for the owner to settle before the tag.';
  const rows = [
    row('main', {
      key: 1,
      runtime: 'fake',
      model: undefined,
      wait: { stopped: NOW - 4_000 },
    }),
    row(title, {
      key: 2,
      runtime: 'fake',
      model: undefined,
      wait: { working: NOW - 41_000 },
    }),
    row('docs', { key: 3, runtime: 'fake', model: undefined }),
  ];
  const frame = { limit: 4, width: 76, now: NOW };
  const pick = (key: number) =>
    rows.map((each) => ({ ...each, picked: each.key === key }));

  test('with the prompt keeping the keys, the tall row shows the lines that fit, ↓ beside its last, and … +N more counts the rows after it', () => {
    expect(drawn(rows, { width: 76 })).toStrictEqual([
      '  main                       fake  ◦ idle 4s',
      '  Summarise the release      fake  ✻ working 41s',
      '↓ notes for 0.56.0 from the',
      '  … +1 more',
    ]);
  });

  test('picked, it comes into sight the least move from where the list was, and ↓ moves a line of it a press, ↑ and ↓ marking what is out of sight', () => {
    const { top } = agentsLayout(pick(1), { ...frame, focused: true });
    let view = enteredView(pick(2), top, frame);

    expect(drawn(pick(2), { width: 76, focused: true, view })).toStrictEqual([
      '  main                       fake  ◦ idle 4s',
      '❯ Summarise the release      fake  ✻ working 41s',
      '  notes for 0.56.0 from the',
      '↓ commits since 0.55.2,',
    ]);

    for (let press = 0; press < 4; press += 1) {
      view = scrolledView(pick(2), 1, { ...frame, view });
    }

    expect(drawn(pick(2), { width: 76, focused: true, view })).toStrictEqual([
      '↑ grouped by area, with a',
      '  line for each user-facing',
      '  change and a note for',
      '↓ each breaking one, then',
    ]);

    // ↑ goes back a line a press until its first line is in sight, then
    // the pick moves on as moveListFocus says.
    view = scrolledView(pick(2), -1, { ...frame, view });

    expect(view?.top).toStrictEqual(3);

    let back = view;

    while (back !== undefined) {
      view = back;
      back = scrolledView(pick(2), -1, { ...frame, view });
    }

    expect(view?.top).toStrictEqual(1);
    expect(drawn(pick(2), { width: 76, focused: true, view })[0]).toStrictEqual(
      '❯ Summarise the release      fake  ✻ working 41s',
    );
  });

  test('read to its last line, ↓ goes no further in it, and picked from below it shows from its first line', () => {
    let view = enteredView(pick(2), 0, frame);
    let next = view;

    while (next !== undefined) {
      view = next;
      next = scrolledView(pick(2), 1, { ...frame, view });
    }

    expect(drawn(pick(2), { width: 76, focused: true, view })).toStrictEqual([
      '↑ changelog entry, and list',
      '  the open questions for',
      '  the owner to settle',
      '↓ before the tag.',
    ]);

    // From docs, below, ↑ picks it: the least move shows its first line.
    const { top } = agentsLayout(pick(3), { ...frame, focused: true, view });

    expect(enteredView(pick(2), top, frame)?.top).toStrictEqual(1);
  });

  test('another width, or no view, starts it again the least move from the top; the list is never past its limit', () => {
    const view = { key: 2, width: 76, limit: 4, top: 6 };

    expect(drawn(pick(2), { width: 60, focused: true, view })).toHaveLength(4);
    // The same width at another height: a view for another limit is not
    // this one's.
    expect(
      drawn(pick(2), { width: 76, limit: 6, focused: true, view })[1],
    ).toStrictEqual('❯ Summarise the release      fake  ✻ working 41s');
    expect(drawn(pick(2), { width: 76, focused: true })[1]).toStrictEqual(
      '❯ Summarise the release      fake  ✻ working 41s',
    );

    for (const width of [30, 50, 76, 116]) {
      for (const focused of [false, true]) {
        expect(
          drawn(pick(2), { width, focused, limit: 4 }).length,
        ).toBeLessThanOrEqual(4);
      }
    }
  });
});

describe('CHD-471 L1b tester: every wrapped line remains reachable', () => {
  for (const width of [26, 39, 76, 116]) {
    for (const limit of [4, 6]) {
      test(`wide text and long runtime survive the ${width}-column ${limit}-line budget`, () => {
        const name = '解析🚀 ' + 'abcdefghijk '.repeat(30);
        const runtime =
          'runtime-with-a-very-long-unbroken-identifier ' +
          '追加の説明 '.repeat(10);
        const rows = [
          row(name, {
            key: 10,
            picked: true,
            runtime,
            wait: {
              asking: { on: { kind: 'permission' }, since: NOW - 17000 },
              unseen: { kind: 'replied', since: NOW },
            },
          }),
        ];
        const frame = { width, limit, now: NOW };
        const complete = agentsLayout(rows, {
          ...frame,
          limit: 10000,
          focused: true,
        }).rows[0]!;
        const compact = (text: string) => text.replace(/\s/g, '');

        expect(
          compact(
            [complete.name, ...complete.names.map((line) => line.text)].join(
              '',
            ),
          ),
        ).toBe(compact(name));

        const detail = [
          complete.detail,
          ...complete.below.flatMap((line) => line.map((run) => run.text)),
        ].join('');

        expect(compact(detail)).toContain(compact(runtime));
        expect(
          compact([complete.state?.text ?? '', detail].join('')),
        ).toContain('●permission17s');

        let view = enteredView(rows, 0, frame);
        const visited = new Set<number>();

        for (let step = 0; step <= complete.height; step += 1) {
          const layout = agentsLayout(rows, { ...frame, focused: true, view });
          const lines = drawn(rows, { width, limit, focused: true, view });

          expect(lines.length).toBeLessThanOrEqual(limit);
          expect(lines.every((line) => stringWidth(line) <= width)).toBe(true);

          for (const line of layout.rows[0]!.lines) {
            visited.add(line.at);
          }

          const next = scrolledView(rows, 1, { ...frame, view });

          if (next === undefined) {
            break;
          }

          expect(next.top).toBe((view?.top ?? 0) + 1);

          view = next;
        }

        expect([...visited].sort((a, b) => a - b)).toEqual(
          Array.from({ length: complete.height }, (_, at) => at),
        );

        for (let step = 0; step <= complete.height; step += 1) {
          const previous = scrolledView(rows, -1, { ...frame, view });

          if (previous === undefined) {
            break;
          }

          view = previous;
        }

        expect(view?.top).toBe(0);
      });
    }
  }
});

describe('CHD-464 tester: list space at its floor', () => {
  test('an absent or single agent needs no folded row, while several keep one agent and more', () => {
    const options = { limit: 1, width: 76, focused: false, now: NOW };
    const rows = ['main', 'tester', 'coder'].map((name, key) =>
      row(name, { key, model: undefined }),
    );

    expect(agentsLines([], options)).toBe(0);
    expect(agentsLines(rows.slice(0, 1), options)).toBe(1);
    expect(agentsLines(rows, options)).toBe(2);
    expect(drawn(rows, { limit: 1, width: 76 })).toStrictEqual([
      '  main    codex  ◦ idle 0s',
      '  … +2 more',
    ]);
    expect(agentsLines(rows, { ...options, limit: 4 })).toBe(3);
    expect(agentsLines(rows, options)).toBe(2);
  });
});
