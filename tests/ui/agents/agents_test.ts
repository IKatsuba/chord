import { expect, test } from 'bun:test';
import { emptyWatch } from '../../../src/notify.ts';
import type { TabWait } from '../../../src/session/tabs.ts';
import type { RunningMonitor } from '../../../src/session/monitors.ts';
import {
  type AgentRow,
  agentsHint,
  agentsLayout,
  agentsRowLimit,
  agentState,
  childLine,
  leftOpenLine,
  type ListRow,
  listRows,
  listTimed,
  monitorHint,
  moveListFocus,
  stopFocused,
  teamRows,
} from '../../../src/ui/agents/agents.ts';

const NOW = 100_000;

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
  rows: readonly ListRow[],
  { limit = 4, width = 116, focused = false } = {},
): string[] {
  const layout = agentsLayout(rows, { limit, width, focused, now: NOW });

  return [
    ...layout.rows.map((laid) =>
      `${laid.mark}${laid.branch ?? ''}${laid.name}  ${laid.detail}${
        laid.state === undefined
          ? ''
          : `  ${laid.state.text}${laid.state.owner?.text ?? ''}`
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
  expect(state({}, { failed: true })).toStrictEqual('✗ failed (error)');
  expect(state({ exited: true })).toStrictEqual('✗ exited (error)');
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

/** A running monitor, `minutes` old, with `events` delivered. */
function monitor(
  id: string,
  description: string,
  command: string,
  minutes: number,
  events: number,
): RunningMonitor {
  return {
    id,
    description,
    command,
    startedAt: NOW - minutes * 60_000,
    timeoutMs: 600_000,
    events,
  };
}

const ERRORS = monitor(
  'm1',
  'dev server errors',
  'tail -f dev.log | grep --line-buffered -E "ERROR|WARN"',
  6,
  3,
);
const CI = monitor(
  'm2',
  'CI run 4812',
  'gh run watch 4812 --exit-status --compact',
  1,
  0,
);

test("monitors follow the agents, each its description, $ command and how long it ran, as CHD-243's mocks draw them", () => {
  const rows = listRows(
    [],
    [
      { key: 1, monitor: ERRORS },
      { key: 1, monitor: CI },
    ],
    undefined,
  );

  expect(drawn(rows, { width: 116 })).toStrictEqual([
    '  dev server errors  $ tail -f dev.log | grep --line-buffered -E "ERROR|WARN"  running 6m · 3 events',
    '  CI run 4812        $ gh run watch 4812 --exit-status --compact               running 1m · no events',
  ]);
  // At 80 columns the commands are cut, and nothing else is.
  expect(drawn(rows, { width: 76 })).toStrictEqual([
    '  dev server errors  $ tail -f dev.log | grep --lin…  running 6m · 3 events',
    '  CI run 4812        $ gh run watch 4812 --exit-sta…  running 1m · no events',
  ]);
  // Narrower, the time goes before the command is cut below $ and twelve.
  expect(drawn(rows, { width: 50 })).toStrictEqual([
    '  dev server errors  $ tail -f dev.log…  3 events',
    '  CI run 4812        $ gh run watch 48…  no events',
  ]);
});

test("a child's monitor ends with its name, and shares the columns with the agents", () => {
  const PARSER_TESTS = monitor(
    'm1',
    'parser tests',
    'deno test --watch=src/parse tests/parse',
    2,
    1,
  );
  const rows = listRows(
    [MAIN, { ...PARSER, model: undefined }],
    [
      { key: 1, monitor: ERRORS },
      {
        key: 2,
        owner: { name: 'parser', colour: 0 },
        monitor: PARSER_TESTS,
      },
    ],
    undefined,
  );

  expect(drawn(rows, { width: 76 })).toStrictEqual([
    '  main               claude · Opus',
    '  parser             codex                     ✻ working 41s',
    '  dev server errors  $ tail -f dev.log | gre…  running 6m · 3 events',
    '  parser tests       $ deno test --watch=src…  running 2m · 1 event · parser',
  ]);
});

test('monitors run in the order they started, whichever agent started them', () => {
  const rows = listRows(
    [],
    [
      { key: 1, monitor: ERRORS },
      { key: 2, owner: { name: 'parser', colour: 0 }, monitor: CI },
    ],
    undefined,
  );

  expect(rows.map((row) => ('id' in row ? row.id : ''))).toStrictEqual([
    'm1',
    'm2',
  ]);
  expect(
    listRows(
      [],
      [
        { key: 1, monitor: CI },
        { key: 1, monitor: ERRORS },
      ],
      undefined,
    ).map((row) => ('id' in row ? row.id : '')),
  ).toStrictEqual(['m1', 'm2']);
});

test('the ❯ is on the monitor focused, else the agent picked, else the first monitor', () => {
  const both = (focus?: { key: number; id: string }) =>
    drawn(
      listRows(
        [MAIN, PARSER],
        [
          { key: 1, monitor: ERRORS },
          { key: 1, monitor: CI },
        ],
        focus,
      ),
      { focused: true },
    )
      .map((line) => line.slice(0, 2))
      .join('');

  expect(both()).toStrictEqual('❯       ');
  expect(both({ key: 1, id: 'm2' })).toStrictEqual('      ❯ ');
  // A focused monitor that has ended leaves the ❯ to the agent picked.
  expect(both({ key: 1, id: 'm9' })).toStrictEqual('❯       ');

  const alone = drawn(listRows([], [{ key: 1, monitor: ERRORS }], undefined), {
    focused: true,
  });

  expect(alone[0]!.slice(0, 2)).toStrictEqual('❯ ');
});

test('↑ ↓ move the ❯ through agents and monitors; an agent is picked, a monitor only focused', () => {
  const rows = (focus?: { key: number; id: string }) =>
    listRows(
      [MAIN, PARSER],
      [
        { key: 1, monitor: ERRORS },
        { key: 1, monitor: CI },
      ],
      focus,
    );

  expect(moveListFocus(rows(), 1)).toStrictEqual({ kind: 'agent', key: 6 });
  expect(moveListFocus(rows(), 2)).toStrictEqual({
    kind: 'monitor',
    key: 1,
    id: 'm1',
  });
  expect(moveListFocus(rows({ key: 1, id: 'm2' }), 1)).toStrictEqual({
    kind: 'monitor',
    key: 1,
    id: 'm2',
  });
  expect(moveListFocus(rows({ key: 1, id: 'm1' }), -1)).toStrictEqual({
    kind: 'agent',
    key: 6,
  });
  // Above the first row, the keys go back to the box.
  expect(moveListFocus(rows(), -1)).toStrictEqual(undefined);
  expect(
    moveListFocus(listRows([], [{ key: 1, monitor: ERRORS }], undefined), -1),
  ).toStrictEqual(undefined);
});

test('x stops the focused monitor and the ❯ goes to the row above, or the new first row, or the box', () => {
  const monitors = [
    { key: 1, monitor: ERRORS },
    { key: 1, monitor: CI },
  ];

  expect(
    stopFocused(listRows([MAIN, PARSER], monitors, undefined)),
  ).toStrictEqual(undefined);
  expect(
    stopFocused(listRows([MAIN, PARSER], monitors, { key: 1, id: 'm1' })),
  ).toStrictEqual({
    stop: { key: 1, id: 'm1' },
    then: { kind: 'agent', key: 6 },
  });
  expect(
    stopFocused(listRows([], monitors, { key: 1, id: 'm2' })),
  ).toStrictEqual({
    stop: { key: 1, id: 'm2' },
    then: { kind: 'monitor', key: 1, id: 'm1' },
  });
  expect(
    stopFocused(listRows([], monitors, { key: 1, id: 'm1' })),
  ).toStrictEqual({
    stop: { key: 1, id: 'm1' },
    then: { kind: 'monitor', key: 1, id: 'm2' },
  });
  expect(stopFocused(listRows([], [monitors[0]!], undefined))).toStrictEqual({
    stop: { key: 1, id: 'm1' },
  });
});

test("a monitor's row has its own hint: it is stopped, not written to", () => {
  expect(monitorHint(116, 'x')).toStrictEqual(
    '↑ ↓ to pick · x to stop it · enter esc to go back',
  );
  expect(monitorHint(76, 'x')).toStrictEqual('↑ ↓ pick · x stop · esc back');
  expect(monitorHint(56, undefined)).toStrictEqual('↑ ↓ pick · esc back');
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
  expect(drawn(listRows(team(), [], undefined, 6), { limit: 6 })).toStrictEqual(
    [
      '  main         claude · Opus',
      '  bugfix       team · claude · Opus   ✓ replied 40s ago',
      '  ├─ tester    claude · Sonnet        ● permission 12s',
      '  ├─ coder     codex · gpt-5.3-codex',
      '  └─ reviewer  claude · Opus          ✓ replied 1m ago',
      '  parser       codex · gpt-5.3-codex  ✻ working 9s',
    ],
  );
});

test('a list that does not fit folds each team to its lead, its size and its most urgent state naming the member', () => {
  expect(
    drawn(listRows(team(), [], undefined, 4), { limit: 4, width: 76 }),
  ).toStrictEqual([
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
    drawn(listRows(long, [], undefined, 4), { limit: 4, width: 76 }).slice(
      0,
      2,
    ),
  ).toStrictEqual([
    '  main         claude',
    '  bugfix       team · claude · 4 agents  ● tester: permission 12s',
  ]);
  // A monitor counts towards the limit, so the list folds for one too.
  expect(
    listRows(team(), [{ key: 1, monitor: ERRORS }], undefined, 6).length,
  ).toStrictEqual(4);
});

test('the team the pick is in unfolds, and the list scrolls to it while it has the keys', () => {
  const rows = (picked: string) => listRows(team(picked), [], undefined, 4);

  expect(
    drawn(rows('bugfix'), { limit: 4, width: 76, focused: true }),
  ).toStrictEqual([
    '  main         claude · Opus',
    '❯ bugfix       team · claude · Opus   ✓ replied 40s ago',
    '  ├─ tester    claude · Sonnet        ● permission 12s',
    '  … +3 more',
  ]);
  // ctrl+x a picks tester without the list having the keys: still unfolded.
  expect(
    rows('tester').map((each) => ('name' in each ? each.name : each.id)),
  ).toStrictEqual(['main', 'bugfix', 'tester', 'coder', 'reviewer', 'parser']);
  // ↑ ↓ walk the rows as drawn: onto a folded lead, then into its members.
  expect(moveListFocus(rows('parser'), -1)).toStrictEqual({
    kind: 'agent',
    key: 2,
  });
  expect(moveListFocus(rows('bugfix'), 1)).toStrictEqual({
    kind: 'agent',
    key: 3,
  });
  expect(moveListFocus(rows('reviewer'), 1)).toStrictEqual({
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
      [],
      undefined,
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
  ).toStrictEqual('  bugfix       team · claude · 3 agents  ✗ failed');
  expect(teamRows([main!, lead!], { fold: true })[1]).toStrictEqual(lead);
});

test("a folded member's time keeps the list ticking while its lead is idle and seen", () => {
  const idle = team().map((each) =>
    each.name === 'tester' ? each : { ...each, wait: { watch: emptyWatch } },
  );
  const rows = listRows(idle, [], undefined, 4);

  expect(rows.length).toStrictEqual(3);
  expect(listTimed(rows)).toStrictEqual(true);
  expect(
    listTimed(
      listRows(
        idle.map((each) => ({ ...each, wait: { watch: emptyWatch } })),
        [],
        undefined,
        4,
      ),
    ),
  ).toStrictEqual(false);
});
