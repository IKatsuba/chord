/**
 * Teams: a session that hands the fake team `bugfix` a job through chord's
 * `run_team`, twice for a second run; the lead's first turn, which opens
 * `tester` and `coder`, reports to main and, in a second run, asks the
 * first run's lead which files it holds; `tester`'s, which reports to its
 * lead, messages `coder` directly and asks the person to run the tests; and
 * `coder`'s, which messages `tester`. A team agent's first prompt is played
 * by its part's role, as main.ts reads it, so the job reads as a real one.
 */
import * as acp from '@agentclientprotocol/sdk';
import { STEP_MS } from '../options.ts';
import { pause, type Play, type Turn } from '../turn.ts';
import { callChord, chordClient } from './chord_tools.ts';
import { TASK_ARGS } from './tasks.ts';

/** A team agent's pace: 20 steps, a tenth of a second by default. */
const TEAM_STEP_MS = STEP_MS * 20;

/** The first run's job, as main writes it from the conversation. */
export const TEAM_JOB =
  'Issue 214: a string at the end of a line loses its closing quote. ' +
  'readString in src/parse/tokenize.ts stops at the newline before it ' +
  'consumes the quote. Add a test that fails for that reason, fix it, and ' +
  'have the diff reviewed. Report to me when it is done.';

/** The second run's job. */
export const SECOND_JOB =
  'Issue 219: parseDate in src/parse/date.ts reads "2026-02-30" as March 2. ' +
  'Add a test that fails for that reason, fix it, and have the diff ' +
  'reviewed. Report to me when it is done.';

/** What the lead opens `tester` with. */
export const TESTER_PROMPT =
  'Write a test in tests/parse/tokenize_test.ts that fails because a ' +
  'string at the end of a line loses its closing quote. Edit tests/ only. ' +
  'Tell me when it fails for that reason.';

/** What the lead opens `coder` with. */
export const CODER_PROMPT =
  "You will edit src/parse/tokenize.ts, and only it, once tester's test " +
  'fails. Read it now; change nothing yet.';

/** The lead's first report to main. */
export const LEAD_REPORT =
  'On it. tester is writing a failing test in tests/parse/tokenize_test.ts; ' +
  'coder waits for it and will edit src/parse/tokenize.ts only. I will ' +
  "report when the test fails for the bug's own reason.";

/** `tester`'s report to its lead. */
export const TESTER_REPORT =
  'It fails for that reason: "a" at the end of a line comes back as "a, ' +
  'with no closing quote. Only tests/parse/tokenize_test.ts changed.';

/** `tester`'s message to `coder`, not through the lead. */
export const TESTER_TO_CODER =
  'The failing test is in tests/parse/tokenize_test.ts and stays mine. ' +
  'Fix readString so it passes; I will run the suite after.';

/** `coder`'s message to `tester`. */
export const CODER_TO_TESTER =
  'Reading src/parse/tokenize.ts now. Tell me when your test fails.';

/** A team agent's part, by its session, as main.ts read it off the prompt. */
export const teamParts = new Map<
  string,
  { readonly from: string; readonly text: string }
>();

/** The runs a lead's part names as open beside it, by their leads' names. */
function otherRuns(text: string): string[] {
  const named = /by these names: ([^\n]*)\.$/m.exec(text)?.[1];

  return named === undefined ? [] : named.split(/, (?:and )?| and /);
}

/** A call of the agent's own, done after a step. */
async function work(turn: Turn, title: string, output: string): Promise<void> {
  const toolCallId = turn.callId('execute');

  await turn.send({
    sessionUpdate: 'tool_call',
    toolCallId,
    title,
    kind: 'edit' satisfies acp.ToolKind,
    status: 'in_progress',
  });
  await pause(turn.signal, TEAM_STEP_MS * 5);
  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: 'completed',
    content: [{ type: 'content', content: { type: 'text', text: output } }],
  });
}

/** Asks the person to run `command`, and says how they answered. */
async function askToRun(turn: Turn, command: string): Promise<acp.StopReason> {
  const toolCallId = turn.callId('execute');
  const toolCall: acp.ToolCall = {
    toolCallId,
    title: `\`${command}\``,
    kind: 'execute',
    status: 'pending',
  };

  await turn.send({ sessionUpdate: 'tool_call', ...toolCall });

  const answer = await turn.client.request('session/request_permission', {
    sessionId: turn.sessionId,
    toolCall,
    options: [
      { optionId: 'allow', name: 'Allow', kind: 'allow_once' },
      { optionId: 'always', name: 'Always allow', kind: 'allow_always' },
      { optionId: 'deny', name: 'Deny', kind: 'reject_once' },
    ],
  });

  if (answer.outcome.outcome === 'cancelled') {
    return 'cancelled';
  }

  const allowed = answer.outcome.optionId !== 'deny';

  await turn.send({
    sessionUpdate: 'tool_call_update',
    toolCallId,
    status: allowed ? 'completed' : 'failed',
    ...(allowed
      ? {
          content: [
            {
              type: 'content',
              content: { type: 'text', text: '1 failed, 213 passed' },
            },
          ],
        }
      : {}),
  });
  await turn.say(
    allowed
      ? 'The suite fails only where the new test does.'
      : 'Not run; I will ask bugfix how to go on.',
  );

  return 'end_turn';
}

/** Hands team `bugfix` `job`, then says where its reports will come. */
export async function handOver(
  turn: Turn,
  job: string,
): Promise<acp.StopReason> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    await callChord(turn, client, 'list_teams', {});

    const answer = await callChord(turn, client, 'run_team', {
      team: 'bugfix',
      job,
    });
    const name =
      answer === undefined
        ? undefined
        : (JSON.parse(answer) as { name: string }).name;

    await turn.say(
      name === undefined
        ? 'chord did not start the team.'
        : `${name} has the job. Its lead will report here; you can look in ` +
            'with ↓.',
    );
  } finally {
    await client.close();
  }

  return 'end_turn';
}

/** How bugfix works, as the proposal's body has it. */
const PROPOSED_BODY = `# How bugfix works

1. The lead reads the job, finds the files involved, and names who may edit which before anyone starts.
2. tester writes a test that fails for the bug's own reason. It edits \`tests/\` only, and reports the failure.
3. coder fixes the code so that test passes. It edits only the files the lead named for it, and never \`tests/\`.
4. reviewer reads the diff and edits nothing. If it finds a problem, the lead hands it back to coder.
5. tester runs the whole suite once more, and the lead reports to main.

## Who edits what

- One writer per file at a time. Before a member starts, the lead tells it which files are its own.
- A member that needs a file it does not own asks its owner directly, and tells the lead what they agreed.
- Another run of a team may be working in this directory: the leads agree on files among themselves.
- Nobody commits. The person commits.

## Reporting

The lead writes to main when it needs a decision only the person can make, when the job is done, and when it cannot be done.`;

/** The team the fake proposes first, as `propose_team` takes it. */
export const PROPOSED_TEAM = {
  name: 'bugfix',
  description:
    'Fixes a bug end to end: a failing test first, then the fix, then a ' +
    'review of the diff.',
  lead: {
    agent: 'claude',
    model: 'opus',
    mode: 'default',
    instructions:
      'Read the job and the code it points at until you can ' +
      'name the cause and the files involved. Open tester first, coder ' +
      "once tester's test fails, and reviewer last, on the diff.",
  },
  members: [
    {
      name: 'tester',
      role: 'Writes the failing test, then proves the fix',
      agent: 'claude',
      model: 'sonnet',
      mode: 'acceptEdits',
      instructions:
        'Write the smallest test that fails because of the ' +
        'bug, and run it to show that.',
    },
    {
      name: 'coder',
      role: 'Writes the fix, in the files the lead names',
      agent: 'codex',
      model: 'gpt-5.3-codex',
      mode: 'auto',
      instructions:
        'Make the failing test pass with the smallest change. ' +
        'Do not touch tests.',
    },
    {
      name: 'reviewer',
      role: 'Reads the diff and edits nothing',
      agent: 'claude',
      model: 'opus',
      mode: 'plan',
      instructions: 'Read `git diff` and the test. Never edit a file.',
    },
  ],
  body: PROPOSED_BODY,
};

/**
 * The team changed as the person asked: reviewer on codex, and tester
 * running the suite without asking.
 */
export const CHANGED_TEAM = {
  ...PROPOSED_TEAM,
  members: PROPOSED_TEAM.members.map((member) =>
    member.name === 'tester'
      ? { ...member, mode: 'bypassPermissions' }
      : member.name === 'reviewer'
        ? {
            ...member,
            agent: 'codex',
            model: 'gpt-5.3-codex',
            mode: 'read-only',
          }
        : member,
  ),
  body: PROPOSED_BODY.replace(
    '5. tester runs the whole suite once more,',
    '5. tester runs the whole suite once more, without asking,',
  ),
};

/**
 * `bugfix` with efforts, as CHD-356 drew it: the lead on high, tester on
 * medium, coder and reviewer on their runtime's own.
 */
export const EFFORTS_TEAM = {
  ...PROPOSED_TEAM,
  lead: { ...PROPOSED_TEAM.lead, effort: 'high' },
  members: PROPOSED_TEAM.members.map((member) =>
    member.name === 'tester' ? { ...member, effort: 'medium' } : member,
  ),
};

/**
 * `EFFORTS_TEAM` changed: tester on high and bypassPermissions, coder on
 * xhigh, reviewer read-only, so the table has each kind of `was`.
 */
export const CHANGED_EFFORTS_TEAM = {
  ...EFFORTS_TEAM,
  members: EFFORTS_TEAM.members.map((member) =>
    member.name === 'tester'
      ? { ...member, effort: 'high', mode: 'bypassPermissions' }
      : member.name === 'coder'
        ? { ...member, effort: 'xhigh' }
        : member.name === 'reviewer'
          ? { ...member, mode: 'read-only' }
          : member,
  ),
};

/** What the fake proposes after a proposal, the person's words having changed it. */
type Again = 'proposeagain' | 'proposeeffortsagain';

/**
 * The sessions whose last turn proposed a team: their next words, whatever
 * they say, are what to change, and get the changed team proposed.
 */
export const proposing = new Map<string, Again>();

/** As long as the fake waits for the person to answer the save box. */
const SAVE_BOX_MS = 3_600_000;

/**
 * Proposes `team` through chord's `propose_team`, after `intro`, and says
 * what came of it: where it was saved, or nothing, as the person will say
 * what to change.
 */
async function propose(
  turn: Turn,
  team: typeof PROPOSED_TEAM,
  intro: string,
  again: Again = 'proposeagain',
): Promise<acp.StopReason> {
  const client = await chordClient(turn);

  if (client === undefined) {
    await turn.say('No chord server in this session.');

    return 'end_turn';
  }

  try {
    await turn.say(intro);

    const answer = await callChord(
      turn,
      client,
      'propose_team',
      team,
      SAVE_BOX_MS,
    );

    proposing.set(turn.sessionId, again);

    if (answer?.startsWith('Saved to ')) {
      await turn.say(
        `${team.name} is saved for ${
          answer.includes('.config') ? 'every project' : 'this project'
        }. Hand it a bug with /team run ${team.name} and the bug, or just ` +
          `tell me to hand one to ${team.name}.`,
      );
    }
  } finally {
    await client.close();
  }

  return 'end_turn';
}

export const TEAMS = {
  // Proposes `bugfix` for the person to save.
  propose: (turn) =>
    propose(
      turn,
      PROPOSED_TEAM,
      'A lead on Opus to split the work, and three members, one for each ' +
        'step. Only one of them edits a file at a time.',
    ),

  // Proposes `bugfix` again, as the person's words after a proposal change
  // it: the reviewer on codex, the tester running the suite unasked.
  proposeagain: (turn) =>
    propose(
      turn,
      CHANGED_TEAM,
      'The reviewer on codex too, read-only, and tester in ' +
        'bypassPermissions, so it runs the suite without asking.',
    ),

  // Proposes `bugfix` with efforts, and on the person's words, a change to
  // them.
  proposeefforts: (turn) =>
    propose(
      turn,
      EFFORTS_TEAM,
      'The lead thinks hard, tester a little; the rest on their own.',
      'proposeeffortsagain',
    ),

  proposeeffortsagain: (turn) =>
    propose(
      turn,
      CHANGED_EFFORTS_TEAM,
      'tester on high and bypassPermissions, coder on xhigh, and the ' +
        'reviewer read-only.',
      'proposeeffortsagain',
    ),

  // Hands the first job to `bugfix`.
  team: (turn) => handOver(turn, TEAM_JOB),

  // A member and a task of main's asking the person at once: bugfix runs as
  // `team` hands it over, its tester asking, and `taskchild` starts as `task`
  // starts it, asking too (CHD-431).
  async teamtask(turn) {
    const client = await chordClient(turn);

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'run_team', {
        team: 'bugfix',
        job: TEAM_JOB,
      });
      await callChord(turn, client, 'spawn_task', TASK_ARGS);
      await turn.say('The team and the task are both at work.');
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // Hands the second job to `bugfix`, a second run while the first is open.
  team2: (turn) => handOver(turn, SECOND_JOB),

  // The lead's first turn: opens `tester`, then `coder`, reports to main,
  // and asks each other run's lead which files it holds.
  async teamlead(turn) {
    const client = await chordClient(turn);
    const others = otherRuns(teamParts.get(turn.sessionId)?.text ?? '');

    if (client === undefined) {
      await turn.say('No chord server in this session.');

      return 'end_turn';
    }

    try {
      await callChord(turn, client, 'open_agent', {
        member: 'tester',
        prompt: TESTER_PROMPT,
      });
      await callChord(turn, client, 'open_agent', {
        member: 'coder',
        prompt: CODER_PROMPT,
      });

      for (const other of others) {
        await callChord(turn, client, 'send_message', {
          to: other,
          text:
            'This run keeps to src/parse/date.ts and ' +
            'tests/parse/date_test.ts. Which files do you hold?',
        });
      }

      await callChord(turn, client, 'send_message', {
        to: 'main',
        text: LEAD_REPORT,
      });
      await turn.say("tester and coder are open; I wait for tester's test.");
    } finally {
      await client.close();
    }

    return 'end_turn';
  },

  // `tester`'s first turn: the test written, a report to its lead, a word
  // to `coder` directly, then the suite, which asks the person.
  async teamtester(turn) {
    const client = await chordClient(turn);
    const lead = teamParts.get(turn.sessionId)?.from ?? 'bugfix';

    try {
      await work(
        turn,
        'Write tests/parse/tokenize_test.ts',
        'Wrote 12 lines to tests/parse/tokenize_test.ts',
      );

      if (client !== undefined) {
        await callChord(turn, client, 'send_message', {
          to: lead,
          text: TESTER_REPORT,
        });
        await callChord(turn, client, 'send_message', {
          to: 'coder',
          text: TESTER_TO_CODER,
        });
      }
    } finally {
      await client?.close();
    }

    await pause(turn.signal, TEAM_STEP_MS * 5);

    return await askToRun(turn, 'deno task test tests/parse');
  },

  // `coder`'s first turn: a word to `tester`, then it waits.
  async teamcoder(turn) {
    const client = await chordClient(turn);

    try {
      await pause(turn.signal, TEAM_STEP_MS * 5);

      if (client !== undefined) {
        await callChord(turn, client, 'send_message', {
          to: 'tester',
          text: CODER_TO_TESTER,
        });
      }

      await turn.say("Waiting for tester's test.");
    } finally {
      await client?.close();
    }

    return 'end_turn';
  },
} satisfies Record<string, Play>;
