import { expect, test } from 'bun:test';
import stringWidth from 'string-width';
import type { Team } from '../../../../src/teams.ts';
import {
  agentRows,
  bodyChange,
  bodyChangeLine,
  bodyLines,
  changeRows,
  instructionLines,
  LEAD_ROLE,
  proposalBody,
  proposalOf,
  proposalTable,
  savedLine,
  skipsAsking,
  type TableLine,
} from '../../../../src/ui/transcript/tools/proposal.ts';

const TEAM: Team = {
  description: 'Fixes a bug end to end',
  lead: { agent: 'claude', model: 'opus', mode: 'default' },
  members: [
    {
      name: 'tester',
      role: 'Writes the failing test, then proves the fix',
      agent: 'claude',
      model: 'sonnet',
      mode: 'acceptEdits',
      instructions: 'Write it.\nRun it.',
    },
    {
      name: 'coder',
      role: 'Writes the fix, in the files the lead names',
      agent: 'codex',
      model: 'gpt-5.3-codex',
      mode: 'auto',
      instructions: 'Fix it.',
    },
  ],
  body: '# How bugfix works',
};

test('a proposal is read from what chord served, and not before or after a refusal', () => {
  const input = { name: 'bugfix', ...TEAM };

  expect(
    proposalOf({
      tool: 'propose_team',
      input,
      answer: { proposal: 'new', files: {} },
      pending: true,
    }),
  ).toStrictEqual({ name: 'bugfix', team: TEAM, kind: 'new' });
  expect(
    proposalOf({
      tool: 'propose_team',
      input,
      answer: { proposal: 'change', files: {}, before: TEAM, saved: false },
    }),
  ).toStrictEqual({
    name: 'bugfix',
    team: TEAM,
    kind: 'change',
    before: TEAM,
    saved: false,
  });
  expect(proposalOf({ tool: 'propose_team', input })).toStrictEqual(undefined);
  expect(
    proposalOf({ tool: 'propose_team', input, error: 'no' }),
  ).toStrictEqual(undefined);
});

test("the table's columns fit the width: the role and then agent · model wrap in their columns, the mode never", () => {
  const rows = agentRows(TEAM);
  const wide = proposalTable(rows, 120);

  expect(wide.map((line) => line.text)).toStrictEqual([
    `lead    claude · opus          default      ${LEAD_ROLE}`,
    'tester  claude · sonnet        acceptEdits  Writes the failing test, then proves the fix',
    'coder   codex · gpt-5.3-codex  auto         Writes the fix, in the files the lead names',
  ]);
  expect(
    wide.map(({ text, mode: [start, end] }) => text.slice(start, end)),
  ).toStrictEqual(['default', 'acceptEdits', 'auto']);

  // A tool result's words, the role wraps, never cut (CHD-422).
  expect(proposalTable(rows, 70).map((line) => line.text)).toStrictEqual([
    'lead    claude · opus          default      Splits the job, says who',
    '                                            edits which files, reports',
    '                                            to main',
    'tester  claude · sonnet        acceptEdits  Writes the failing test,',
    '                                            then proves the fix',
    'coder   codex · gpt-5.3-codex  auto         Writes the fix, in the',
    '                                            files the lead names',
  ]);
  // Where agent · model's longest word and the role's least do not fit
  // beside the other cells, the table is laid out as opened.
  expect(proposalTable(rows, 44)).toStrictEqual(
    proposalTable(rows, 44, false, true),
  );
});

test('opened, each role is whole on lines of its own under its row, to the right edge', () => {
  const rows = agentRows(TEAM);
  const opened = proposalTable(rows, 80, false, true);

  expect(opened.map((line) => line.text)).toStrictEqual([
    'lead    claude · opus          default',
    `        ${LEAD_ROLE}`,
    'tester  claude · sonnet        acceptEdits',
    '        Writes the failing test, then proves the fix',
    'coder   codex · gpt-5.3-codex  auto',
    '        Writes the fix, in the files the lead names',
  ]);
  expect(
    opened.map(({ text, mode: [start, end] }) => text.slice(start, end)),
  ).toStrictEqual(['default', '', 'acceptEdits', '', 'auto', '']);
  expect(opened.map((line) => [line.row.name, line.role])).toStrictEqual([
    ['lead', undefined],
    ['lead', true],
    ['tester', undefined],
    ['tester', true],
    ['coder', undefined],
    ['coder', true],
  ]);
  // The same shape at any width, so nothing jumps as the terminal resizes.
  expect(proposalTable(rows, 200, false, true)).toStrictEqual(opened);
  expect(
    proposalTable(rows, 50, false, true).map((line) => line.text),
  ).toStrictEqual([
    'lead    claude · opus          default',
    '        Splits the job, says who edits which',
    '        files, reports to main',
    'tester  claude · sonnet        acceptEdits',
    '        Writes the failing test, then proves the',
    '        fix',
    'coder   codex · gpt-5.3-codex  auto',
    '        Writes the fix, in the files the lead',
    '        names',
  ]);
});

test('opened, a change keeps every model whole, its mark and was on the first row', () => {
  const after: Team = {
    ...TEAM,
    members: [
      { ...TEAM.members[0]!, mode: 'bypassPermissions' },
      TEAM.members[1]!,
    ],
  };
  const lines = proposalTable(agentRows(after, TEAM), 80, true, true);

  expect(lines.map((line) => line.text)).toStrictEqual([
    '   lead    claude · opus          default',
    `           ${LEAD_ROLE}`,
    '~  tester  claude · sonnet        bypassPermissions was acceptEdits',
    '           Writes the failing test, then proves the fix',
    '   coder   codex · gpt-5.3-codex  auto',
    '           Writes the fix, in the files the lead names',
  ]);
  expect(lines.map(({ text, was }) => was && text.slice(...was))).toStrictEqual(
    [undefined, undefined, ' was acceptEdits', undefined, undefined, undefined],
  );
});

test('opened, where the mode leaves no room, the role spans the agent and mode columns', () => {
  const after: Team = {
    ...TEAM,
    members: [
      { ...TEAM.members[0]!, mode: 'bypassPermissions' },
      TEAM.members[1]!,
    ],
  };
  const lines = proposalTable(agentRows(after, TEAM), 44, true, true);

  expect(
    lines.filter((line) => line.role).map((line) => line.text),
  ).toStrictEqual([
    '           Splits the job, says who edits',
    '           which files, reports to main',
    '           Writes the failing test, then',
    '           proves the fix',
    '           Writes the fix, in the files the',
    '           lead names',
  ]);
});

test('opened, a row that does not fit wraps its mode first and its model last, at spaces', () => {
  const reviewer = {
    name: 'security-review',
    role: 'Reviews the diff for security problems and edits nothing',
    agent: 'claude',
    model: 'claude-sonnet-4-5-20250929',
    mode: 'acceptEdits',
    instructions: 'Review it.',
  };
  const before: Team = { ...TEAM, members: [reviewer] };
  const after: Team = {
    ...TEAM,
    members: [{ ...reviewer, mode: 'bypassPermissions' }],
  };
  const rows = agentRows(after, before);
  const lines = proposalTable(rows, 74, true, true);

  expect(lines.map((line) => line.text)).toStrictEqual([
    '   lead             claude · opus                        default',
    '                    Splits the job, says who edits which files, reports to',
    '                    main',
    '~  security-review  claude · claude-sonnet-4-5-20250929  bypassPermissions',
    '                                                         was acceptEdits',
    '                    Reviews the diff for security problems and edits',
    '                    nothing',
  ]);
  expect(lines.map((line) => line.text).join('')).not.toContain('…');
  expect(
    lines.map(({ text, mode: [start, end] }) => text.slice(start, end)),
  ).toStrictEqual(['default', '', '', 'bypassPermissions', '', '', '']);
  expect(lines.map(({ text, was }) => was && text.slice(...was))).toStrictEqual(
    [undefined, undefined, undefined, undefined, 'was acceptEdits'].concat(
      Array<undefined>(2).fill(undefined),
    ),
  );
  expect(lines.map((line) => line.role === true)).toStrictEqual([
    false,
    true,
    true,
    false,
    false,
    true,
    true,
  ]);

  // Narrower, agent · model wraps at its space too, the id whole.
  expect(
    proposalTable(rows, 72, true, true)
      .slice(3, 6)
      .map((line) => line.text),
  ).toStrictEqual([
    '~  security-review  claude ·                           bypassPermissions',
    '                    claude-sonnet-4-5-20250929         was acceptEdits',
    '                    Reviews the diff for security problems and edits',
  ]);
});

test("a change's rows are marked against the team saved before, its gone members last", () => {
  const after: Team = {
    ...TEAM,
    members: [
      { ...TEAM.members[0]!, mode: 'bypassPermissions' },
      { ...TEAM.members[1]!, name: 'fixer' },
    ],
  };
  // Each row's first line, which holds its mode, a wrapped role under it.
  const lines = proposalTable(agentRows(after, TEAM), 120, true).filter(
    ({ mode: [start, end] }) => end > start,
  );

  expect(lines.map((line) => line.text.slice(0, 11))).toStrictEqual([
    '   lead    ',
    '~  tester  ',
    '+  fixer   ',
    '-  coder   ',
  ]);
  expect(
    lines.map(({ text, mode: [start, end] }) => text.slice(start, end)),
  ).toStrictEqual(['default', 'bypassPermissions', 'auto', 'auto']);
  expect(lines.map(({ text, was }) => was && text.slice(...was))).toStrictEqual(
    [undefined, ' was acceptEdits', undefined, undefined],
  );
});

test('a member named lead is marked as itself, never as the lead', () => {
  const reviewer = {
    name: 'lead',
    role: 'Reviews the fix',
    agent: 'claude',
    instructions: 'Review',
  };
  const before: Team = { ...TEAM, members: [...TEAM.members, reviewer] };
  const changed: Team = {
    ...before,
    members: [
      ...TEAM.members,
      {
        ...reviewer,
        instructions: 'Review carefully',
      },
    ],
  };
  const marks = (rows: ReturnType<typeof agentRows>) =>
    rows.map((row) => [row.role, row.change]);

  expect(marks(agentRows(changed, before))).toStrictEqual([
    [LEAD_ROLE, undefined],
    [TEAM.members[0]!.role, undefined],
    [TEAM.members[1]!.role, undefined],
    ['Reviews the fix', 'changed'],
  ]);
  expect(marks(agentRows(TEAM, before))).toStrictEqual([
    [LEAD_ROLE, undefined],
    [TEAM.members[0]!.role, undefined],
    [TEAM.members[1]!.role, undefined],
    ['Reviews the fix', 'removed'],
  ]);
});

test("a changed row says the mode it had, none where its mode is the same, and — for the runtime's own", () => {
  const after: Team = {
    ...TEAM,
    lead: { ...TEAM.lead, model: 'sonnet' },
    members: [{ ...TEAM.members[0]!, mode: undefined }, TEAM.members[1]!],
  };

  expect(agentRows(after, TEAM).map((row) => row.was)).toStrictEqual([
    undefined,
    'acceptEdits',
    undefined,
  ]);
  expect(agentRows(TEAM, after).map((row) => row.was)).toStrictEqual([
    undefined,
    '—',
    undefined,
  ]);
});

test("a change's body counts itself as not yet written, and folds to its changed lines on a tall window only", () => {
  const before = Array.from({ length: 20 }, (_, index) => `line ${index}`).join(
    '\n',
  );
  const after = before.replace('line 10', 'line ten');
  const folded = bodyChange({
    name: 'bugfix',
    before,
    after,
    expanded: false,
    rows: changeRows(40),
  });

  expect(bodyChangeLine('bugfix', folded.view)).toStrictEqual(
    "bugfix.md's body · 1 addition, 1 removal",
  );
  expect(folded.view.rows.map((row) => row.kind)).toStrictEqual([
    'context',
    'removed',
    'added',
    'context',
  ]);
  expect(folded.view.hidden).toStrictEqual(0);
  expect(folded.hidden).toStrictEqual(4);

  const short = bodyChange({
    name: 'bugfix',
    before,
    after,
    expanded: false,
    rows: changeRows(24),
  });

  expect(short.view.rows).toStrictEqual([]);
  expect(short.hidden).toStrictEqual(8);
  expect(
    bodyChange({ name: 'bugfix', before, after, expanded: true, rows: 0 }).view
      .rows.length,
  ).toStrictEqual(8);
});

test('a mode that skips the person ok is told apart', () => {
  expect(
    ['bypassPermissions', 'full-access', 'default', 'auto', undefined].map(
      skipsAsking,
    ),
  ).toStrictEqual([true, true, false, false, false]);
});

test('the body folds to its first lines where the window has the rows, and ctrl+o adds the instructions', () => {
  const blocks = ['How bugfix works', '1. One\n2. Two', 'Reporting'];
  const instructions = ['', "tester's instructions", 'Write it.'];

  expect(bodyLines(40)).toStrictEqual(2);
  expect(bodyLines(24)).toStrictEqual(0);
  expect(
    proposalBody({ instructions, blocks, keep: 2, expanded: false }),
  ).toStrictEqual({ lines: ['', 'How bugfix works', '1. One'], hidden: 7 });
  expect(
    proposalBody({ instructions, blocks, keep: 0, expanded: false }),
  ).toStrictEqual({ lines: [], hidden: 10 });
  expect(
    proposalBody({ instructions, blocks, keep: 2, expanded: true }).lines,
  ).toStrictEqual([
    ...instructions,
    '',
    'How bugfix works',
    '',
    '1. One',
    '2. Two',
    '',
    'Reporting',
  ]);
});

test("the person's answer leaves its line under the call", () => {
  const view = { name: 'bugfix', team: TEAM, kind: 'new' as const };

  expect(savedLine(view)).toStrictEqual(undefined);
  expect(savedLine({ ...view, saved: '.chord/teams/bugfix.md' })).toStrictEqual(
    {
      text:
        'Saved to .chord/teams/bugfix.md · /team run bugfix <job> hands it ' +
        'a job',
      saved: true,
    },
  );
  expect(savedLine({ ...view, saved: false })).toStrictEqual({
    text: 'Not saved · the person will say what to change',
    saved: false,
  });
});

test("each agent's instructions are wrapped to the width whole, a long line no longer cut (CHD-332)", () => {
  const long =
    'Ты ведущий команды `dev`: читай задачу, `quarry task list`, решай, кто что делает, и следи за правилом.';
  const team: Team = {
    ...TEAM,
    lead: { ...TEAM.lead, instructions: long },
    members: [TEAM.members[0]!],
  };
  const lines = instructionLines(team, 30);

  expect(lines).toStrictEqual([
    '',
    "lead's instructions",
    'Ты ведущий команды `dev`:',
    'читай задачу, `quarry task',
    'list`, решай, кто что делает,',
    'и следи за правилом.',
    '',
    "tester's instructions",
    'Write it.',
    'Run it.',
  ]);
});

/** CHD-356's team: three agents set an effort, the reviewer leaves it. */
const EFFORTS: Team = {
  ...TEAM,
  lead: { ...TEAM.lead, effort: 'high' },
  members: [
    { ...TEAM.members[0]!, effort: 'high' },
    { ...TEAM.members[1]!, effort: 'xhigh' },
    {
      name: 'reviewer',
      role: 'Reads the diff and edits nothing',
      agent: 'claude',
      model: 'opus',
      mode: 'plan',
      instructions: 'Read it.',
    },
  ],
};

/** The same team saved before: tester on medium and bypass, coder on none. */
const EFFORTS_BEFORE: Team = {
  ...EFFORTS,
  members: [
    { ...EFFORTS.members[0]!, effort: 'medium', mode: 'bypassPermissions' },
    { ...TEAM.members[1]! },
    { ...EFFORTS.members[2]!, mode: 'read-only' },
  ],
};

test('an effort is a column between agent · model and the mode, — where none is set, and none where no agent sets one', () => {
  expect(
    proposalTable(agentRows(EFFORTS), 114).map((line) => line.text),
  ).toStrictEqual([
    `lead      claude · opus          high   default      ${LEAD_ROLE}`,
    'tester    claude · sonnet        high   acceptEdits  Writes the failing test, then proves the fix',
    'coder     codex · gpt-5.3-codex  xhigh  auto         Writes the fix, in the files the lead names',
    'reviewer  claude · opus          —      plan         Reads the diff and edits nothing',
  ]);
  // The role pays for the column at 80, wrapping in what is left.
  expect(
    proposalTable(agentRows(EFFORTS), 74).map((line) => line.text),
  ).toStrictEqual([
    'lead      claude · opus          high   default      Splits the job, says',
    '                                                     who edits which',
    '                                                     files, reports to',
    '                                                     main',
    'tester    claude · sonnet        high   acceptEdits  Writes the failing',
    '                                                     test, then proves the',
    '                                                     fix',
    'coder     codex · gpt-5.3-codex  xhigh  auto         Writes the fix, in',
    '                                                     the files the lead',
    '                                                     names',
    'reviewer  claude · opus          —      plan         Reads the diff and',
    '                                                     edits nothing',
  ]);
  expect(agentRows(TEAM)[0]!.effort).toStrictEqual('—');
  expect(proposalTable(agentRows(TEAM), 120)[0]!.text).toStrictEqual(
    `lead    claude · opus          default      ${LEAD_ROLE}`,
  );
});

test('a changed effort says the one it had, dim, and folded drops that before agent · model narrows', () => {
  const firsts = (lines: TableLine[]) =>
    lines.filter(({ mode: [start, end] }) => end > start);
  const rows = agentRows(EFFORTS, EFFORTS_BEFORE);

  expect(rows.map((row) => [row.effort, row.effortWas])).toStrictEqual([
    ['high', undefined],
    ['high', 'medium'],
    ['xhigh', '—'],
    ['—', undefined],
  ]);
  expect(
    agentRows(TEAM, EFFORTS).map((row) => [row.effort, row.effortWas]),
  ).toStrictEqual([
    ['—', 'high'],
    ['—', 'high'],
    ['—', 'xhigh'],
    // reviewer, gone, as it was.
    ['—', undefined],
  ]);

  const all = proposalTable(rows, 114, true);
  const wide = firsts(all);

  expect(all.map((line) => line.text)).toStrictEqual([
    '   lead      claude · opus          high             default                            Splits the job, says who',
    '                                                                                        edits which files, reports',
    '                                                                                        to main',
    '~  tester    claude · sonnet        high was medium  acceptEdits was bypassPermissions  Writes the failing test,',
    '                                                                                        then proves the fix',
    '~  coder     codex · gpt-5.3-codex  xhigh was —      auto                               Writes the fix, in the',
    '                                                                                        files the lead names',
    '~  reviewer  claude · opus          —                plan was read-only                 Reads the diff and edits',
    '                                                                                        nothing',
  ]);
  expect(wide[1]!.text.slice(...wide[1]!.effortWas!)).toStrictEqual(
    ' was medium',
  );
  expect(wide[0]!.effortWas).toStrictEqual(undefined);

  // Too narrow for its columns beside the changed cells, laid out as opened.
  expect(proposalTable(rows, 74, true)).toStrictEqual(
    proposalTable(rows, 74, true, true),
  );
});

test('opened, a changed cell that wraps breaks before was, and the effort wraps before the model', () => {
  const rows = agentRows(EFFORTS, EFFORTS_BEFORE);
  const opened = proposalTable(rows, 74, true, true);

  expect(opened.map((line) => line.text)).toStrictEqual([
    '   lead      claude · opus          high             default',
    '             Splits the job, says who edits which files, reports to main',
    '~  tester    claude · sonnet        high was medium  acceptEdits',
    '                                                     was bypassPermissions',
    '             Writes the failing test, then proves the fix',
    '~  coder     codex · gpt-5.3-codex  xhigh was —      auto',
    '             Writes the fix, in the files the lead names',
    '~  reviewer  claude · opus          —                plan was read-only',
    '             Reads the diff and edits nothing',
  ]);
  expect(opened[3]!.text.slice(...opened[3]!.was!)).toStrictEqual(
    'was bypassPermissions',
  );

  // CHD-356's worst case: a 15-cell name and a 26-cell model id.
  const long = proposalTable(
    agentRows(EFFORTS, {
      ...EFFORTS_BEFORE,
      members: [
        ...EFFORTS_BEFORE.members,
        {
          name: 'security-review',
          role: 'Reviews the diff for security problems and edits nothing',
          agent: 'claude',
          model: 'claude-sonnet-4-5-20250929',
          effort: 'max',
          mode: 'bypassPermissions',
          instructions: 'Review it.',
        },
      ],
    }),
    74,
    true,
    true,
  );

  expect(long.slice(3, 6).map((line) => line.text)).toStrictEqual([
    '~  tester           claude · sonnet              high    acceptEdits',
    '                                                 was     was',
    '                                                 medium  bypassPermissions',
  ]);
  expect(long[4]!.text.slice(...long[4]!.effortWas!)).toStrictEqual('was');
  expect(long[5]!.text.slice(...long[5]!.effortWas!)).toStrictEqual('medium');
  expect(long[5]!.text.slice(...long[5]!.was!)).toStrictEqual(
    'bypassPermissions',
  );
  expect(long.slice(-4, -2).map((line) => line.text)).toStrictEqual([
    '-  security-review  claude ·                     max     bypassPermissions',
    '                    claude-sonnet-4-5-20250929',
  ]);
});

test('narrow, every word of agent · model and of the role is kept, each wrapping in its column', () => {
  const rows = agentRows(EFFORTS, EFFORTS_BEFORE);

  for (const width of [74, 60]) {
    const lines = proposalTable(rows, width, true);
    const read = lines.map((line) => line.text).join(' ');

    for (const row of rows) {
      for (const word of `${row.runtime} ${row.role}`.split(' ')) {
        expect(read.includes(word), `${word} at ${width}`).toBeTruthy();
      }
    }

    expect(lines.some((line) => line.text.includes('…'))).toBeFalsy();
  }
});

test('no row of a narrow table is wider than its width, so every word stays in its column', () => {
  for (const [rows, marked] of [
    [agentRows(EFFORTS, EFFORTS_BEFORE), true],
    [agentRows(TEAM), false],
  ] as const) {
    for (let width = 70; width >= 48; width--) {
      const lines = proposalTable(rows, width, marked);

      for (const line of lines) {
        expect(
          stringWidth(line.text) <= width,
          `${width}: ${line.text}`,
        ).toBeTruthy();
      }
    }
  }
});
