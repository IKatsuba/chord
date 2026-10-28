/**
 * The fake agent's flags and the environment variables beside them, read once
 * at start. Here rather than in `main.ts` because the scenarios read them too,
 * and `main.ts` imports the scenarios.
 */
import type { McpCapabilities } from '@agentclientprotocol/sdk';
import process from 'node:process';

/** The flags after the script, as the runtime was given them. */
export const ARGS = process.argv.slice(2);

export const RESUME_ONLY = ARGS.includes('--resume-only');

/**
 * It offers no `session/load`, so chord resumes a session it has no record
 * of too, and nothing is replayed (CHD-492).
 */
export const NO_LOAD = ARGS.includes('--no-load');

export const NO_USAGE =
  ARGS.includes('--no-usage') || process.env.CHORD_FAKE_NO_USAGE === '1';

export const TOKENS_ONLY =
  ARGS.includes('--tokens-only') || process.env.CHORD_FAKE_TOKENS_ONLY === '1';

/**
 * `--session-usage`, or `CHORD_FAKE_SESSION_USAGE=1`: a turn's answer gives
 * the session's running total of tokens, every turn so far, as dirac's does
 * (CHD-472), not the turn's own.
 */
export const SESSION_USAGE =
  ARGS.includes('--session-usage') ||
  process.env.CHORD_FAKE_SESSION_USAGE === '1';

/**
 * `--no-cost`, or `CHORD_FAKE_NO_COST=1`: the turn's `usage_update` carries
 * the context and no cost, as an agent whose provider gives none sends it.
 */
export const NO_COST =
  ARGS.includes('--no-cost') || process.env.CHORD_FAKE_NO_COST === '1';

/**
 * `--unpriced-model`, or `CHORD_FAKE_UNPRICED_MODEL=1`: with
 * `--tokens-only`'s real models, one more chord's price data does not know,
 * `fake-unpriced`, to switch to mid-session (CHD-472).
 */
export const UNPRICED_MODEL =
  ARGS.includes('--unpriced-model') ||
  process.env.CHORD_FAKE_UNPRICED_MODEL === '1';

export const NO_IMAGES =
  ARGS.includes('--no-images') || process.env.CHORD_FAKE_NO_IMAGES === '1';

export const NO_HTTP =
  ARGS.includes('--no-http') || process.env.CHORD_FAKE_NO_HTTP === '1';

/**
 * The MCP transports past stdio the fake advertises in `mcpCapabilities`:
 * `http` and `sse`, `http` left out with `--no-http`, or those the comma list
 * `--mcp-transports http,sse,acp` (`CHORD_FAKE_MCP_TRANSPORTS`) names, `none`
 * for stdio alone (CHD-441).
 */
export const MCP_TRANSPORTS: McpCapabilities = (() => {
  const flag = ARGS.indexOf('--mcp-transports');
  const chosen =
    flag >= 0 ? ARGS[flag + 1] : process.env.CHORD_FAKE_MCP_TRANSPORTS;

  if (chosen === undefined) {
    return { http: !NO_HTTP, sse: true };
  }

  const known = ['http', 'sse', 'acp'] as const;
  const named = chosen === 'none' ? [] : chosen.split(',');

  for (const each of named) {
    if (!(known as readonly string[]).includes(each)) {
      throw new Error(`unknown MCP transport to advertise "${each}"`);
    }
  }

  return Object.fromEntries(
    known.map((transport) => [transport, named.includes(transport)]),
  );
})();

export const NO_CONFIG =
  ARGS.includes('--no-config') || process.env.CHORD_FAKE_NO_CONFIG === '1';

export const NO_MODES =
  ARGS.includes('--no-modes') || process.env.CHORD_FAKE_NO_MODES === '1';

/**
 * A stop of a Claude subagent alone is held until a test lets it go: each
 * stop is written to `STOP_GATE_STOPS` in the session's gate, one id a line,
 * and the subagent ends only once `STOP_GATE_RELEASE` is there.
 */
export const STOP_GATE =
  ARGS.includes('--stop-gate') || process.env.CHORD_FAKE_STOP_GATE === '1';

/**
 * A `session/cancel` that comes with no turn playing is answered at once
 * with `Cancel heard with no turn.`, so a test sees it arrived before
 * sending what follows (CHD-426).
 */
export const SAY_CANCELS =
  ARGS.includes('--say-cancels') || process.env.CHORD_FAKE_SAY_CANCELS === '1';

/**
 * A message another agent or chord sent is answered with the whole prompt
 * that came, as a JSON string, `Received "<message …>…"`, so a test reads
 * what the agent got in its `session/prompt` (CHD-482).
 */
export const ECHO_MESSAGES =
  ARGS.includes('--echo-messages') ||
  process.env.CHORD_FAKE_ECHO_MESSAGES === '1';

/** The value given a flag `--name value`, or its environment variable. */
function valueOf(flag: string, variable: string): string | undefined {
  const at = ARGS.indexOf(flag);

  return at >= 0 ? ARGS[at + 1] : process.env[variable];
}

/**
 * `--title <text>`, or `CHORD_FAKE_TITLE`: every session the fake opens,
 * loads or resumes names itself `<text>` in a `session_info_update` just
 * after the reply, before any prompt, as an agent that titles a session of
 * its own accord does (CHD-445). None when not given, as auggie sends none.
 */
export const TITLE_AT_START = valueOf('--title', 'CHORD_FAKE_TITLE');

/**
 * `--dimcode-permission <value>`, or `CHORD_FAKE_DIMCODE_PERMISSION`: every
 * session offers dimcode's `permission` config option, `read-only`,
 * `workspace-write` or `full-access`, starting at the value given (CHD-434).
 */
export const DIMCODE_PERMISSION = valueOf(
  '--dimcode-permission',
  'CHORD_FAKE_DIMCODE_PERMISSION',
);

/**
 * The runtime `--child-runtime <name>` (or `CHORD_FAKE_CHILD_RUNTIME`)
 * names for the children the scenarios open, so a test has an agent of
 * another runtime in the window, and the screenshots theirs on the names
 * their settings give the fake (CHD-493); none when not given.
 */
export const CHILD_RUNTIME_GIVEN = valueOf(
  '--child-runtime',
  'CHORD_FAKE_CHILD_RUNTIME',
);

/** The runtime `agentother` opens its child on: `codex` unless given. */
export const CHILD_RUNTIME = CHILD_RUNTIME_GIVEN ?? 'codex';

/**
 * The model the children the scenarios open ask for, with
 * `--child-model <id>` or `CHORD_FAKE_CHILD_MODEL`, as the screenshots
 * show their runtime's; none leaves each scenario's own.
 */
export const CHILD_MODEL = valueOf('--child-model', 'CHORD_FAKE_CHILD_MODEL');

/**
 * A person's words for scenarios' names, with `--said <json>` or
 * `CHORD_FAKE_SAID`, `{ "<scenario>": "<words>" }`: a child is opened on
 * the words, and a prompt that is the words plays the scenario, so a
 * screenshot shows what a person would type (CHD-493).
 */
export const SAID: Readonly<Record<string, string>> = JSON.parse(
  valueOf('--said', 'CHORD_FAKE_SAID') ?? '{}',
) as Record<string, string>;

/**
 * The members a team's lead opens on its first turn, in order: `tester` and
 * `coder` unless `--lead-opens tester,coder,reviewer` (or
 * `CHORD_FAKE_LEAD_OPENS`) says, as the README's screenshots ask.
 */
export const LEAD_OPENS: readonly string[] = (
  valueOf('--lead-opens', 'CHORD_FAKE_LEAD_OPENS') ?? 'tester,coder'
)
  .split(',')
  .filter((name) => name !== '');

/**
 * A team file whose team `propose` proposes in place of its own, with
 * `--propose-team <file>` or `CHORD_FAKE_PROPOSE_TEAM`: the screenshots'
 * team, on the models they show.
 */
export const PROPOSE_TEAM = valueOf(
  '--propose-team',
  'CHORD_FAKE_PROPOSE_TEAM',
);

/**
 * What a session's cost starts from, in USD: with `--cost-from 0.05`, or
 * `CHORD_FAKE_COST_FROM`, each session reports its cost counted from its
 * start, as an agent that keeps it with the session does once it is resumed
 * (CHD-373); with neither, from when this process opened it, as Claude's.
 */
export const COST_FROM = Number(
  (ARGS.includes('--cost-from')
    ? ARGS[ARGS.indexOf('--cost-from') + 1]
    : process.env.CHORD_FAKE_COST_FROM) ?? 0,
);

/**
 * What the agent's own cycle adds to the session's cost, in USD: with
 * `--cycle-cost 0.005`, or `CHORD_FAKE_CYCLE_COST`, the usage update that
 * ends a Claude cycle carries the session's cost so far with it added; `0`
 * repeats the cost as it was. With neither, it carries no cost, as the
 * fake's cycles always did (CHD-373).
 */
export const CYCLE_COST = ARGS.includes('--cycle-cost')
  ? Number(ARGS[ARGS.indexOf('--cycle-cost') + 1])
  : process.env.CHORD_FAKE_CYCLE_COST === undefined
    ? undefined
    : Number(process.env.CHORD_FAKE_CYCLE_COST);

/**
 * A session resumed runs a Claude cycle of its own once it has gone quiet,
 * with no prompt sent in it: `--cycle-on-resume` or
 * `CHORD_FAKE_CYCLE_ON_RESUME=1`.
 */
export const CYCLE_ON_RESUME =
  ARGS.includes('--cycle-on-resume') ||
  process.env.CHORD_FAKE_CYCLE_ON_RESUME === '1';

/**
 * A turn's `usage_update` comes after its answer, as claude-agent-acp's
 * can, rather than ahead of it: with `--late-cost` or
 * `CHORD_FAKE_LATE_COST=1`.
 */
export const LATE_COST =
  ARGS.includes('--late-cost') || process.env.CHORD_FAKE_LATE_COST === '1';

/**
 * A turn's `usage_update` is held until the session's next prompt has
 * arrived, and goes ahead of that turn's work, as a cancelled turn's cost
 * can come once the next has begun: `--cost-at-next` or
 * `CHORD_FAKE_COST_AT_NEXT=1`.
 */
export const COST_AT_NEXT =
  ARGS.includes('--cost-at-next') ||
  process.env.CHORD_FAKE_COST_AT_NEXT === '1';

/**
 * A scenario a team's lead opens `tester` on, in place of its role: with
 * `--tester-plays taskcost`, or `CHORD_FAKE_TESTER_PLAYS`, tester starts a
 * task agent of its own (CHD-373).
 */
export const TESTER_PLAYS = ARGS.includes('--tester-plays')
  ? ARGS[ARGS.indexOf('--tester-plays') + 1]
  : process.env.CHORD_FAKE_TESTER_PLAYS;

const HANGS = ['start', 'config', 'turn'] as const;

function hangStep(): (typeof HANGS)[number] | undefined {
  const flag = ARGS.indexOf('--hang');
  const chosen = flag >= 0 ? ARGS[flag + 1] : process.env.CHORD_FAKE_HANG;

  if (chosen === undefined) {
    return undefined;
  }

  if (!HANGS.includes(chosen as (typeof HANGS)[number])) {
    throw new Error(`unknown step to hang at "${chosen}"`);
  }

  return chosen as (typeof HANGS)[number];
}

export const HANG = hangStep();

export const PLAN_CAPABILITY_ONLY =
  ARGS.includes('--plan-capability-only') ||
  process.env.CHORD_FAKE_PLAN_CAPABILITY_ONLY === '1';

export const SILENT_SET_MODE =
  ARGS.includes('--silent-set-mode') ||
  process.env.CHORD_FAKE_SILENT_SET_MODE === '1';

const STEERINGS = ['claude', 'codex'] as const;

function steeringAdapter(): (typeof STEERINGS)[number] | undefined {
  const flag = ARGS.indexOf('--steering');
  const chosen = flag >= 0 ? ARGS[flag + 1] : process.env.CHORD_FAKE_STEERING;

  if (chosen === undefined) {
    return undefined;
  }

  if (!STEERINGS.includes(chosen as (typeof STEERINGS)[number])) {
    throw new Error(`unknown adapter to steer as "${chosen}"`);
  }

  return chosen as (typeof STEERINGS)[number];
}

/**
 * The adapter whose `_session/steering` the fake answers as, `claude` or
 * `codex`; none by default, when it neither advertises nor takes it.
 */
export const STEERING = steeringAdapter();

/**
 * The adapter the fake names itself as in `initialize`, `claude` as
 * Claude's does, with `--adapter claude` or `CHORD_FAKE_ADAPTER=claude`,
 * without steering as it: chord runs cycles of the agent's own only for
 * that adapter (CHD-426).
 */
export const ADAPTER = (() => {
  const flag = ARGS.indexOf('--adapter');
  const chosen = flag >= 0 ? ARGS[flag + 1] : process.env.CHORD_FAKE_ADAPTER;

  if (chosen !== undefined && chosen !== 'claude') {
    throw new Error(`unknown adapter to name as "${chosen}"`);
  }

  return chosen;
})();

/**
 * A steer lands only once the turn playing has ended, as one sent just as a
 * turn ends does: Claude's adapter then refuses it, Codex's starts a turn of
 * its own with it.
 */
export const STEER_LATE =
  ARGS.includes('--steer-late') || process.env.CHORD_FAKE_STEER_LATE === '1';

/**
 * Every steer is refused, the turn playing or not, as an agent that will
 * not take a message into the turn it runs does (CHD-535).
 */
export const STEER_REFUSE =
  ARGS.includes('--steer-refuse') ||
  process.env.CHORD_FAKE_STEER_REFUSE === '1';

/**
 * A turn on a message ends only once `GATE_RELEASE` is in its session's
 * gate, or 10 s on, so a test says when it is answered: a reply that comes
 * after a moment the test chose, rather than a while after (CHD-501).
 */
export const HOLD_REPLY =
  ARGS.includes('--hold-reply') || process.env.CHORD_FAKE_HOLD_REPLY === '1';

export const REFUSE_CONFIG =
  ARGS.includes('--refuse-config') ||
  process.env.CHORD_FAKE_REFUSE_CONFIG === '1';

/**
 * Long enough that chunks arrive as separate events, short enough to keep
 * tests fast. `--step-ms <ms>` or `CHORD_FAKE_STEP_MS` sets it, and every
 * scenario's pace with it.
 */
export const STEP_MS = Number(
  (ARGS.includes('--step-ms')
    ? ARGS[ARGS.indexOf('--step-ms') + 1]
    : undefined) ??
    process.env.CHORD_FAKE_STEP_MS ??
    '5',
);

/**
 * `--auth-required <kind>` (`CHORD_FAKE_AUTH_REQUIRED`): every
 * `session/new`, `session/load` and `session/resume` fails `authRequired`
 * (-32000), as an agent nobody signed in to answers (CHD-435). `methods`
 * says how to sign in in its message and offers two methods at
 * `initialize`, one whose description names a command and one with a name
 * alone; `bare` says only `Authentication required` and offers none, as
 * kimi does; `link` asks a sign-in link first, as droid does, and fails so
 * unless it is accepted; `linkother` asks the same link and, unless it is
 * accepted, fails for some other reason (-32603), which needs no login.
 */
export const AUTH_REQUIRED:
  'methods' | 'bare' | 'link' | 'linkother' | undefined = (() => {
  const flag = ARGS.indexOf('--auth-required');
  const kind =
    flag >= 0 ? ARGS[flag + 1] : process.env.CHORD_FAKE_AUTH_REQUIRED;

  return kind === 'methods' ||
    kind === 'bare' ||
    kind === 'link' ||
    kind === 'linkother'
    ? kind
    : undefined;
})();

/**
 * `--start-fails <kind>` (`CHORD_FAKE_START_FAILS`): the fake fails to start
 * as an agent that cannot does (CHD-454). `traceback` writes a long Python
 * traceback on stderr and exits 1 before `initialize`, as minion-code 0.1.44
 * does; `stdout` writes a plain line on stdout and exits 0 before
 * `initialize`, as the archived kimi-cli 1.52.0 does; `notacp` answers
 * `initialize` and then every session request -32601, as agoragentic-mcp
 * 1.3.0 does; `alias` refuses `session/new` -32602 for want of an agent
 * alias, as zeroclaw does with several agents and no default.
 */
export const START_FAILS:
  'traceback' | 'stdout' | 'notacp' | 'alias' | undefined = (() => {
  const flag = ARGS.indexOf('--start-fails');
  const kind = flag >= 0 ? ARGS[flag + 1] : process.env.CHORD_FAKE_START_FAILS;

  return kind === 'traceback' ||
    kind === 'stdout' ||
    kind === 'notacp' ||
    kind === 'alias'
    ? kind
    : undefined;
})();

/** The last line of `--start-fails traceback`'s traceback. */
export const TRACEBACK_ERROR =
  "ImportError: cannot import name 'AuthMethod' from 'acp.schema'";
