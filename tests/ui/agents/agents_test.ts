import { describe, expect, test } from 'bun:test';
import { emptyWatch } from '../../../src/notify.ts';
import type { TabWait } from '../../../src/session/tabs.ts';
import {
  type AgentRow,
  agentsHint,
  agentsLayout,
  agentsRowLimit,
  agentState,
  childLine,
  leftOpenLine,
  listRows,
  listTimed,
  moveListFocus,
  summaryHint,
  teamRows,
} from '../../../src/ui/agents/agents.ts';

const NOW = 100_000;

/** No summary line under the agents. */
const NO_SUMMARY = { summary: false, onSummary: false };

function row(
  name: string,
  more: Omit<Partial<AgentRow>, 'wait'> & { wait?: Partial<TabWait> } = {},
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
  { limit = 4, width = 116, focused = false } = {},
): string[] {
  const layout = agentsLayout(rows, { limit, width, focused, now: NOW });

  return [
    ...layout.rows.map((laid) =>
      `${laid.mark}${laid.branch ?? ''}${laid.name}  ${laid.detail}${
        laid.state === undefined ? '' : `  ${laid.state.text}`
      }`.trimEnd(),
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
    '  main    claude · Opus',
    '  parser  codex · gpt-5.3-codex  ✻ working 41s',
    '  docs    claude · Sonnet        ← message from @main',
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
    '  main    claude · Opus',
    '❯ parser  codex · gpt-5.3-codex  ✻ working 41s',
  ]);
});

test('the states read most urgent first, as the strip and the picker word them', () => {
  const state = (wait: Partial<TabWait>, more: Partial<AgentRow> = {}) => {
    const found = agentState(row('x', { ...more, wait }), NOW);

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
  // A failed turn leaves the agent open: the turn failed, not the agent.
  expect(
    state({
      unseen: { kind: 'failed', since: NOW - 12_000, failure: 'turn' },
    }),
  ).toStrictEqual('✗ turn failed 12s ago (error)');
  expect(
    state({ unseen: { kind: 'replied', since: NOW - 120_000 } }),
  ).toStrictEqual('✓ replied 2m ago (success)');
  expect(state({ working: NOW - 62_000 })).toStrictEqual(
    '✻ working 1m 2s (dim)',
  );
  expect(state({})).toStrictEqual(undefined);
});

test('past its rows the list ends in … +N more, and moves so the picked row shows while it has the keys', () => {
  const rows = ['main', 'a', 'b', 'c', 'd', 'e'].map((name, index) =>
    row(name, { key: index, picked: name === 'e', model: undefined }),
  );

  expect(agentsRowLimit(24)).toStrictEqual(4);
  expect(agentsRowLimit(40)).toStrictEqual(6);
  expect(drawn(rows, { limit: 4 })).toStrictEqual([
    '  main  codex',
    '  a     codex',
    '  b     codex',
    '  … +3 more',
  ]);
  expect(drawn(rows, { limit: 4, focused: true })).toStrictEqual([
    '  c     codex',
    '  d     codex',
    '❯ e     codex',
    '  … +3 more',
  ]);
});

test('a narrow list drops the model, then the words, and cuts a name no shorter than twelve', () => {
  const long = row('the-long-parser-name', {
    wait: { working: NOW - 41_000 },
  });

  expect(drawn([MAIN, PARSER], { width: 36 })).toStrictEqual([
    '  main    claude',
    '  parser  codex   ✻ working 41s',
  ]);
  expect(drawn([MAIN, PARSER], { width: 20 })).toStrictEqual([
    '  main    claude',
    '  parser  codex   ✻',
  ]);
  expect(drawn([long], { width: 20 })).toStrictEqual([
    '  the-long-pa…  codex  ✻',
  ]);
});

test("a row's effort follows its model, and a narrow list drops it a step before the model", () => {
  const main = { ...MAIN, effort: 'high' };
  const parser = { ...PARSER, effort: 'xhigh' };

  expect(drawn([main, parser])).toStrictEqual([
    '  main    claude · Opus · high',
    '  parser  codex · gpt-5.3-codex · xhigh  ✻ working 41s',
  ]);
  expect(drawn([main, parser], { width: 50 })).toStrictEqual([
    '  main    claude · Opus',
    '  parser  codex · gpt-5.3-codex  ✻ working 41s',
  ]);
  expect(drawn([main, parser], { width: 36 })).toStrictEqual([
    '  main    claude',
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
    '  main         claude · Opus',
    '  bugfix       team · claude · Opus   ✓ replied 40s ago',
    '  ├─ tester    claude · Sonnet        ● permission 12s',
    '  ├─ coder     codex · gpt-5.3-codex',
    '  └─ reviewer  claude · Opus          ✓ replied 1m ago',
    '  parser       codex · gpt-5.3-codex  ✻ working 9s',
  ]);
});

test('a list that does not fit folds each team to its lead, its size and its most urgent state naming the member', () => {
  expect(drawn(listRows(team(), 4), { limit: 4, width: 76 })).toStrictEqual([
    '  main         claude · Opus',
    '  bugfix       team · claude · 4 agents  ● tester: permission 12s',
    '  parser       codex · gpt-5.3-codex     ✻ working 9s',
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
    '  main         claude',
    '  bugfix       team · claude · 4 agents  ● tester: permission 12s',
  ]);
});

test('the team the pick is in unfolds, and the list scrolls to it while it has the keys', () => {
  const rows = (picked: string) => listRows(team(picked), 4);

  expect(
    drawn(rows('bugfix'), { limit: 4, width: 76, focused: true }),
  ).toStrictEqual([
    '  main         claude · Opus',
    '❯ bugfix       team · claude · Opus   ✓ replied 40s ago',
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
    '  main         claude · Opus',
    '  bugfix       team · claude · 4 agents  ✻ coder: working 1m 1s',
    '  bugfix 2     team · claude · 4 agents  ● tester: permission 5s',
  ]);
  // The run picked unfolds; the other stays folded, so all six rows fit.
  expect(drawn(rows(13), { limit: 6, focused: true })).toStrictEqual([
    '  main         claude · Opus',
    '  bugfix       team · claude · 4 agents  ✻ coder: working 1m 1s',
    '  bugfix 2     team · claude · Opus',
    '❯ ├─ tester    claude · Sonnet           ● permission 5s',
    '  ├─ coder     codex · gpt-5.3-codex',
    '  └─ reviewer  claude · Opus',
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
    '  bugfix       team · claude · 4 agents  ● tester: permission 12s',
  );
  expect(
    drawn(teamRows([main!, failed, ...members.slice(1, 3)], { fold: true }), {
      limit: 9,
    })[1],
  ).toStrictEqual('  bugfix       team · claude · 3 agents  ✗ failed to start');
  expect(teamRows([main!, lead!], { fold: true })[1]).toStrictEqual(lead);
});

test("a folded member's time keeps the list ticking while its lead is idle and seen", () => {
  const idle = team().map((each) =>
    each.name === 'tester' ? each : { ...each, wait: { watch: emptyWatch } },
  );
  const rows = listRows(idle, 4);

  expect(rows.length).toStrictEqual(3);
  expect(listTimed(rows)).toStrictEqual(true);
  expect(
    listTimed(
      listRows(
        idle.map((each) => ({ ...each, wait: { watch: emptyWatch } })),
        4,
      ),
    ),
  ).toStrictEqual(false);
});

test('the three failures read apart, an exit outranking the turn it cut short, then never starting, then a failed turn; a seen failed turn clears', () => {
  const words = (wait: Partial<TabWait>, more: Partial<AgentRow> = {}) =>
    agentState(row('x', { ...more, wait: { watch: emptyWatch, ...wait } }), NOW)
      ?.words;
  const turn = {
    kind: 'failed' as const,
    since: NOW - 60_000,
    failure: 'turn' as const,
  };

  expect(words({ unseen: turn })).toStrictEqual('turn failed 1m ago');
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
  // Seen, a failed turn says nothing, and the agent reads idle and open.
  expect(words({})).toStrictEqual(undefined);
  // An exit and never starting stay until the agent is closed, seen or not.
  expect(words({ exited: true })).toStrictEqual('exited');
  expect(words({}, { failed: true })).toStrictEqual('failed to start');
  // A failed turn's time goes on counting.
  expect(
    listTimed([row('x', { wait: { watch: emptyWatch, unseen: turn } })]),
  ).toStrictEqual(true);
});

test('a folded lead names the member whose failure it shows, gravest first', () => {
  const [main, lead, ...members] = team('main');
  const quiet = (each: AgentRow): AgentRow => ({
    ...each,
    wait: { watch: emptyWatch },
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
  ).toStrictEqual('  bugfix       team · claude · 4 agents  ✗ coder: exited');
  expect(
    drawn(
      teamRows(
        rows.map((each) => (each.name === 'coder' ? quiet(each) : each)),
        { fold: true },
      ),
      { limit: 9, width: 116 },
    )[1],
  ).toStrictEqual(
    '  bugfix       team · claude · 4 agents  ✗ tester: turn failed 12s ago',
  );
});

describe('CHD-264 tester: failure age and row fallback', () => {
  test('the failure clock ignores older news, and a narrow row retains its error glyph', () => {
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

    expect(agentState(failed, NOW)?.words).toBe('turn failed 12s ago');
    expect(agentState(failed, NOW + 2000)?.words).toBe('turn failed 14s ago');
    expect(drawn([MAIN, failed], { width: 76 }).join(' ')).toContain(
      '✗ turn failed 12s ago',
    );
    expect(drawn([MAIN, failed], { width: 20 }).join(' ')).toContain('✗');
    expect(
      agentState({ ...failed, wait: { ...failed.wait, exited: true } }, NOW)
        ?.words,
    ).toBe('exited');
  });
});
