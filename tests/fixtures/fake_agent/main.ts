/**
 * A fake ACP agent over stdio, for tests and for checking chord's screen by
 * hand without spending anyone's account. It is the agent side of the ACP SDK,
 * so the protocol on the wire is the real one; only the replies are scripted.
 *
 * The scenario comes from, in order: a prompt whose whole text is a scenario
 * name, then `--scenario <name>`, then `CHORD_FAKE_SCENARIO`, then `text`.
 * Prompt-chosen scenarios let one long-lived session play several in a row.
 *
 * Every session advertises two slash commands, `greet` and `echo`, right after
 * `session/new`, as Claude's adapter does; a prompt that starts with one plays
 * it instead of a scenario.
 *
 * Shell output chord sends ahead of a prompt is answered first, with a line
 * naming each command and the first line of what it wrote; what follows the
 * output picks the scenario as a prompt alone would.
 *
 * `session/load` takes any id shaped like the ones `session/new` hands out (a
 * UUID) and replays `HISTORY` before it answers, as ACP asks; any other id is
 * not found. The fake keeps no sessions on disk, so every loaded session has
 * that same short past. `CHORD_FAKE_REFUSE_LOAD=1` makes every load fail, as
 * an agent that lost the session would. Started with `--resume-only`, it also
 * offers `session/resume`, as Claude's adapter does, which chord takes when its
 * record holds the past: it takes the same ids and replays nothing. With
 * `--no-load` as well it offers no `session/load`, so chord resumes even a
 * session it has no record of.
 *
 * Every turn that ends on its own reports what it used, as Claude's adapter
 * does: a `usage_update` with the context filled so far, the model's window
 * and the session's cost so far, and the turn's tokens in its answer.
 * Started with `--no-usage`, or with `CHORD_FAKE_NO_USAGE=1`, it reports
 * none, as an agent that says nothing of its usage would. Started with
 * `--tokens-only`, or with `CHORD_FAKE_TOKENS_ONLY=1`, it reports the turn's
 * tokens in its answer and nothing else, no cost and no window, as Codex's
 * adapter can; its models are then real ones chord's price data knows,
 * `gpt-5.3-codex` (in use until switched), `claude-haiku-4-5`, and the
 * README's screenshots' `claude-opus-5-5` and `gpt-6.1-sol`.
 * Started with `--cost-from <usd>`, or `CHORD_FAKE_COST_FROM`, each
 * session's cost counts from that amount, as an agent that keeps it with the
 * session reports after a resume; with `--late-cost`, or
 * `CHORD_FAKE_LATE_COST=1`, the `usage_update` comes after the answer, as
 * Claude's adapter can send it.
 * `--cost-at-next` holds it for the session's next prompt instead.
 * `--session-usage` makes each answer's tokens the session's running total,
 * as dirac's are, and `--no-cost` leaves the cost out of the update.
 * `--cycle-cost <usd>` adds that to the session's cost on the usage update
 * that ends a Claude cycle, and `--cycle-on-resume` runs one in a session
 * resumed (CHD-373).
 *
 * It takes images in a prompt, and answers each one first with a line naming
 * its media type and its size in bytes, so a capture shows what arrived, and
 * each `resource_link` with a line naming it and its URI.
 * Started with `--no-images`, or with `CHORD_FAKE_NO_IMAGES=1`, its
 * `promptCapabilities` say it takes none, as an agent that reads only text.
 *
 * Besides its model and modes, every session offers one more config option,
 * `effort` (low, medium, high; medium until set), as Claude's adapter offers
 * its effort. Started with `--no-config`, or with `CHORD_FAKE_NO_CONFIG=1`, it
 * offers no such option; with `--refuse-config`, or with
 * `CHORD_FAKE_REFUSE_CONFIG=1`, it refuses every change to it. Started with
 * `--no-modes`, or with `CHORD_FAKE_NO_MODES=1`, it offers no modes either
 * way and refuses `session/set_mode`, as an agent without modes would; the
 * `mode` scenario says which mode the turn runs in. Its mode is changed
 * through its `mode` config option or `session/set_mode`; started with
 * `--silent-set-mode`, or with `CHORD_FAKE_SILENT_SET_MODE=1`, it answers
 * `session/set_mode`, and `session/set_config_option` for the mode, as
 * Codex's adapter does, with an empty answer and no update, though the mode
 * moves.
 *
 * Besides the scenarios the window draws, three play what a transport has to
 * survive: `late` sends a chunk after answering the prompt, `twins` asks a
 * permission with two options of one kind, and `unknown` sends an update of a
 * kind ACP does not have and a notification of the agent's own. `cancels`
 * says how many `session/cancel`s came with no turn playing. An accepted
 * `link` is followed by `elicitation/complete`.
 *
 * Started with `--plan-capability-only`, or with
 * `CHORD_FAKE_PLAN_CAPABILITY_ONLY=1`, the `plan` scenario sends its plan as
 * Codex's adapter does: as a `plan_update` with an id only to a client that
 * declares `clientCapabilities.plan`, and to any other as reply text.
 *
 * `proposal` sends a plan as Codex's plan mode proposes one, whatever the
 * flags: to a client that takes plans by id, a markdown `plan_update` that is
 * rewritten and then grows, a `file` plan, and a `plan_removed` for the
 * markdown one, with reply text between; to any other, the plans as text.
 *
 * `shell` runs a command as Codex's adapter does, to any client: a tool call
 * naming its terminal, the output in pieces under the call's `_meta` about
 * half a second apart, and a failing exit with the last piece; `shellcut`
 * the same with a hyperlink whose URL runs past chord's output bound and
 * whose end comes in a later piece. `bash` runs one
 * as Claude's adapter does: to a client that asks for terminal output in
 * `clientCapabilities._meta`, the terminal named up front and nothing of the
 * output until the command is done, about half a second later, then all of
 * it and the exit; to any other, the output as a `console` code block.
 * `bashtwo` and `bashone` do the same, their next step after the command
 * waiting until two messages, or one, were steered in, 10 s at most
 * (`steeredIn`). The gated and held variants other scenarios have
 * (`overlaptwo`, `subagentstatesstay`, `planshrinkgated`, `agentsheldgated`,
 * `longheld`, `leftformgated`, `taskstayshold`, `texttillsteered`) are
 * named in this folder's AGENTS.md. Each wait they add, for a gate, a
 * message or a cancel, is 10 s at most; `taskstayshold`'s parent, as
 * `taskstays`', still holds its turn until it is cancelled or the client
 * goes.
 * `bashcut` leaves a command running and a call that never ran for about
 * 10 s: a cancel ends both `failed` with the lines Claude's adapter gives,
 * the command's terminal with no exit code; left alone, the turn ends and
 * the command fails with the adapter's line for no result. `bashask` asks
 * to run a command as Codex's adapter does, mid-run, the call
 * `in_progress` with output under it, then one as Claude's does, before it
 * runs, the call `pending` until it completes.
 *
 * Started with `--hang <step>`, or with `CHORD_FAKE_HANG=<step>`, it stops
 * answering, as an agent that has wedged: `start` never answers `initialize`,
 * `config` never answers `session/set_config_option`, `session/set_mode` or
 * `session/set_model`, and `turn` never ends a prompt, cancelled or not. It then also ignores
 * SIGTERM and outlives its stdin, so only SIGKILL ends it, or its parent
 * going: a test run killed mid-test must not leave it behind.
 *
 * `compact` compacts the context as Claude's adapter does: to a client that
 * declares `clientCapabilities.session.compaction`, a `compaction_update` in
 * progress, the summary in chunks over about 2 s, then the update that it
 * completed, with no summary, as the chunks carried it; cancelled, it says so.
 * `codexcompact` does as Codex's adapter does, with no summary at all, and
 * `compactfail` fails, with the error Claude's adapter sends. To any other
 * client, each runs as a `Compact conversation` tool call of kind `think`.
 *
 * `subagent` runs subagents in the draft form Codex's adapter sends to a
 * client that declares
 * `clientCapabilities.subagents`: each announced to its parent by
 * `subagent_spawned`, its work sent under a session id of its own, opaque
 * and never one an earlier fake process gave, as after a resume, and its
 * end by `subagent_state_update`. Two start back to back: one makes a plan,
 * calls tools, starts a subagent of its own and asks permission to write;
 * the other fails. After a line of the parent's, a third starts alone and
 * outlives the turn by about 2 s. A cancel ends
 * every one still open as `cancelled` before the turn is answered, as the
 * draft form does. `subagentupdate` sends one in ACP's own
 * `subagent_update` shape, running and then idle. `subagentstates` plays
 * what `subagent` never reaches: the parent's plan beside a lone subagent of
 * five calls with a plan of its own, then a pair the parent waits on with a
 * call of its own, both finishing. `claudesubagents` sends four in ACP's
 * form as Claude's adapter does, each `subagent_update` titled by name and
 * role, open to a cancel of its own, its whole task a `session_message` on
 * its session: one waits on the person for a write (`requires_action`) and
 * ends idle `end_turn`, one `error`, one `cancelled`, one `unknown`; a
 * cancel ends each still at work idle `cancelled`. `claudebackground` runs
 * one the turn waits on beside one in the background, which goes on about
 * 4 s, past the turn and past a cancel that stops only the first.
 * `claudeslowstop` is the same, its subagents taking about 2 s to stop alone.
 * `claudebetween` starts one in the background that, about 2 s after the
 * turn has answered, asks to write a report and then asks a form, and
 * `mainbetween` has the session's own agent ask for a write about half a
 * second after its answer, and `taskbetween` starts `taskchild` as `task`
 * does and ends its turn at once, so the task asks with none of its
 * parent's running: requests with no turn running (CHD-158).
 * `teamtask` runs bugfix as `team` does and starts `taskchild` as `task` does,
 * so a member and a task of main's ask at once (CHD-431).
 * `leftask` asks for a write in its turn and ends the turn with it still
 * open, then says the answer once it comes (CHD-158, the owner's Q44).
 * `mainbetweentwice` asks as `mainbetween` does, then a second write at once,
 * silent half a second (less at a quick pace, never more) after that one's
 * answer before it says what came back.
 * `claudemessage` messages a Claude subagent again once it is done, as
 * SendMessage does, and it runs once more. `claudewaiting` holds one in
 * `requires_action` about 2 s with no request of its sent, then done, and
 * `claudenostop` one that takes its own cancel back. A `session/cancel` on a
 * Claude subagent's own id stops that one alone, idle and `cancelled`, its
 * parent's turn going on. With `--stop-gate` or `CHORD_FAKE_STOP_GATE=1`
 * each such stop is written, one id a line, to `<cwd>/.fake-gate/stops`, and
 * held until the test writes `<cwd>/.fake-gate/stop-release`. To any
 * other client each
 * says so in a line of text.
 *
 * Started with `--steering claude` or `--steering codex`, or with
 * `CHORD_FAKE_STEERING`, it advertises `_session/steering` in
 * `InitializeResponse._meta`, as both adapters do, and answers it as that
 * adapter does: a prompt steered into the turn playing is `injected`, and the
 * turn's next step, or its end, says `Read the message from <sender>.`; with
 * no turn playing, Claude's answers `promptRequired` and does nothing where
 * the request's `_meta.steering.idleBehavior` asks for that, and otherwise,
 * as Codex's always does, plays it as a turn of its own and answers
 * `startedNewTurn`. As Claude's, it names itself in `agentInfo` as that
 * adapter does, whose steer cuts the turn's open calls off; the fake cuts
 * none, so a test sees what chord holds back. Without it, the method is not
 * found. With
 * `--steer-late`, or `CHORD_FAKE_STEER_LATE=1`, a steer lands only once the
 * turn playing has ended, as one that meets a turn's end does. As Codex's, a
 * prompt that comes while a turn plays opens with `Started alongside a turn
 * still playing.`, which chord must never cause.
 * `permissionsteer` asks for a write as `permission` does, then takes its
 * next step only once a message steered in has reached it, as a model's next
 * step comes only after the tool's result, so a message chord holds behind
 * the write lands in the turn whatever the load.
 *
 * `--step-ms <ms>`, or `CHORD_FAKE_STEP_MS`, sets how long a step takes, and
 * with it the pace of every scenario; 5 ms by default.
 *
 * `session/list` gives the sessions this process created, newest first, in
 * the directory asked for; `session/set_model` takes either model, the older
 * way Claude's adapter still answers.
 *
 * It takes stdio, HTTP and SSE MCP servers, and keeps the ones each session
 * was given in `session/new`, `session/load` or `session/resume`; the `mcp`
 * scenario answers with them as JSON, exactly as they arrived, and `opened`
 * with the request that last opened the session and its `_meta`. It connects
 * only to chord's own, the last HTTP server named `chord` or `chord-<n>`, and
 * only in the
 * `chordtools` scenario, which calls `list_agents` and `list_sessions` there
 * through the MCP SDK's client and answers with what came back;
 * `chordcalls` makes those calls as tool calls, titled as Claude's adapter
 * titles an MCP call, and a `spawn_task` chord refuses. `task` starts
 * `taskchild` on the fake runtime as a task agent and works on a while;
 * `taskchild` asks permission, messages its parent and reports. `agents`
 * opens `parser` on `agentchild` and `docs` on `permission`, both long-lived
 * on the fake runtime, and messages `parser` twice; `agentchild` messages
 * its parent twice; `agentsheld` opens `docs` alone and messages it while
 * it waits on its permission; `agentclose` closes `parser` and messages it
 * after; `agentsend` opens `parser` and sends it a short message and a long
 * markdown one, `codexagentsend` the same in Codex's calls, and
 * `agentsendrefused` sends the long one to `parser` unopened; `agentprose`
 * and `codexagentprose` send it long Cyrillic and ASCII paragraphs, which
 * `prosechild` and `codexprosechild` send back;
 * `agentlong` opens `parser` on a long markdown instruction;
 * `agenttask`, `agentexit` and `agentfail` open `parser` on `task`, on
 * `crash`, whose agent writes its last words to stderr and exits mid-turn,
 * and on `error`; `agentcost` opens it on `costwait`, to close it busy with
 * a cost said; `agenttitled` opens one on `text` under a title too
 * long for the agents list at 80x24. `taskeffort` and `agenteffort` start a task and open an
 * agent on `text` on high effort, `taskmaxeffort` and `agentmaxeffort` on
 * max, which it does not offer, and say where chord's answer says they
 * started; `effort` says the effort the turn runs on. `team` and `team2` hand team `bugfix` a job through
 * `run_team`; a team agent's first prompt, its team part ahead of the
 * message, plays `teamlead`, `teamtester` or `teamcoder` by its role, unless
 * the message names a scenario. `soak` hands `bugfix` `soaklead`, whose lead
 * and members then take `soakturn` after `soakturn` until chord quits. A
 * prompt that is a message chord wrapped is answered with who sent it, or,
 * when what it says is a scenario's name, plays that scenario, as a child's
 * first prompt is its parent's message. With
 * `--no-http` or `CHORD_FAKE_NO_HTTP=1` its `mcpCapabilities` leave HTTP out,
 * and `--mcp-transports <list>` (`CHORD_FAKE_MCP_TRANSPORTS`) advertises just
 * the transports it names past stdio, `none` for stdio alone. `titled` names
 * its session in a `session_info_update`, and `retitled` names it twice
 * (CHD-491); `titledlook` and `titledfix` give those two names one prompt
 * each.
 */
import process from 'node:process';
import { Readable, Writable } from 'node:stream';
import { setTimeout as delay } from 'node:timers/promises';
import * as acp from '@agentclientprotocol/sdk';
import { splitContext } from '../../../src/session/context.ts';
import { FAKE_COMMANDS } from '../commands.ts';
import { LINK_URL } from '../forms.ts';
import { readCapabilities } from './client.ts';
import {
  ARGS,
  AUTH_REQUIRED,
  HANG,
  NO_CONFIG,
  DIMCODE_PERMISSION,
  MCP_TRANSPORTS,
  NO_IMAGES,
  NO_MODES,
  NO_COST,
  NO_USAGE,
  SESSION_USAGE,
  REFUSE_CONFIG,
  RESUME_ONLY,
  NO_LOAD,
  SILENT_SET_MODE,
  START_FAILS,
  TRACEBACK_ERROR,
  STEER_LATE,
  HOLD_REPLY,
  STEERING,
  ADAPTER,
  COST_AT_NEXT,
  COST_FROM,
  CYCLE_ON_RESUME,
  LATE_COST,
  SAY_CANCELS,
  ECHO_MESSAGES,
  STEP_MS,
  TOKENS_ONLY,
} from './options.ts';
import { COMPACTION } from './scenarios/compaction.ts';
import { CHORD_TOOLS } from './scenarios/chord_tools.ts';
import { FORMS } from './scenarios/forms.ts';
import { MISBEHAVING } from './scenarios/misbehaving.ts';
import { MODES } from './scenarios/modes.ts';
import { PERMISSIONS } from './scenarios/permissions.ts';
import { PLANS } from './scenarios/plans.ts';
import { SHELL } from './scenarios/shell.ts';
import { claudeChildren, SUBAGENTS } from './scenarios/subagents.ts';
import { TASKS } from './scenarios/tasks.ts';
import { CYCLES, runCycle } from './scenarios/cycles.ts';
import { AGENTS, GATE_RELEASE, gateOpened, heard } from './scenarios/agents.ts';
import { EFFORTS } from './scenarios/efforts.ts';
import { MONITORS } from './scenarios/monitors.ts';
import { senders, SOAK } from './scenarios/soak.ts';
import { proposing, teamParts, TEAMS } from './scenarios/teams.ts';
import { TEXT } from './scenarios/text.ts';
import { TOOLS } from './scenarios/tools.ts';
import {
  AVAILABLE_EFFORTS,
  AVAILABLE_MODELS,
  AVAILABLE_MODES,
  configOptions,
  cwds,
  efforts,
  DIMCODE_PERMISSIONS,
  permissions,
  FIRST_MODEL,
  locked,
  mcpServers,
  models,
  modes,
  openedWith,
  steers,
  strayCancels,
  costs,
} from './sessions.ts';
import {
  type Client,
  lifetime,
  loadMarks,
  pause,
  type Play,
  Turn,
  type Update,
} from './turn.ts';

const SCENARIOS = [
  'text',
  'texttillsteered',
  'thought',
  'tools',
  'steps',
  'stepslater',
  'calls',
  'rawoutputs',
  'longresults',
  'overlap',
  'overlaptwo',
  'overlapfail',
  'overlapask',
  'subagentcall',
  'unordered',
  'edit',
  'rewrite',
  'headlines',
  'heredoc',
  'longcommand',
  'mcpnote',
  'codexmcpnote',
  'markdown',
  'markdownwrap',
  'markdowncode',
  'graphemes',
  'permission',
  'plan',
  'planshrink',
  'planshrinkgated',
  'proposal',
  'cursorplan',
  'cursorplanearly',
  'cursorplanbad',
  'grokplan',
  'grokplanempty',
  'planheard',
  'grokplanwrong',
  'cursorplanlate',
  'planform',
  'shell',
  'shellcut',
  'bash',
  'bashtwo',
  'bashone',
  'bashcut',
  'bashask',
  'claudebetween',
  'mainbetween',
  'leftask',
  'mainbetweentwice',
  'taskbetween',
  'taskstays',
  'taskstayshold',
  'tasktillsteered',
  'teamtask',
  'compact',
  'codexcompact',
  'compactfail',
  'status',
  'error',
  'slow',
  'titled',
  'retitled',
  'titledlook',
  'titledfix',
  'costwait',
  'costwaitlate',
  'long',
  'longheld',
  'todos',
  'exitplan',
  'fullaccess',
  'claudeexitplan',
  'lock',
  'mcp',
  'opened',
  'form',
  'link',
  'askclaude',
  'askclaudeone',
  'askcodex',
  'askdroid',
  'askopencode',
  'askdimcode',
  'askcodexwait',
  'taskask',
  'taskaskstays',
  'mode',
  'effort',
  'late',
  'twins',
  'permissionsteer',
  'mcpask',
  'bigask',
  'bigasktwice',
  'unknown',
  'cancels',
  'subagent',
  'subagentupdate',
  'claudesubagents',
  'claudebackground',
  'claudeslowstop',
  'claudemessage',
  'claudewaiting',
  'claudenostop',
  'subagentstates',
  'subagentstatesstay',
  'chordtools',
  'cutcalls',
  'cutcallsback',
  'cutcallsunfinished',
  'cutcallsunfinishedv2',
  'task',
  'chordcalls',
  'codexchordcalls',
  'codexmodels',
  'leftform',
  'leftformgated',
  'bigaskleft',
  'claudecycle',
  'claudecyclebare',
  'claudecycleask',
  'codebuddycycle',
  'taskchild',
  'taskchildhold',
  'tasklong',
  'taskcost',
  'tasktallname',
  'tasktwo',
  'taskwait',
  'agents',
  'agentother',
  'agentsquiet',
  'agentsheld',
  'agentsheldgated',
  'agentchild',
  'agentclose',
  'agentcall',
  'agentcalltwice',
  'agentcallgated',
  'callchildgated',
  'callchild',
  'callchildtwo',
  'agentsend',
  'codexagentsend',
  'agentsendrefused',
  'agentprose',
  'codexagentprose',
  'prosechild',
  'codexprosechild',
  'agentlong',
  'agenttask',
  'agentcost',
  'agentexit',
  'agentfail',
  'agenttitled',
  'taskeffort',
  'taskmaxeffort',
  'agenteffort',
  'agentmaxeffort',
  'crash',
  'monitor',
  'monitors',
  'monitorexit',
  'monitortimeout',
  'monitorflood',
  'monitorchild',
  'childmonitor',
  'team',
  'team2',
  'teamlead',
  'teamtester',
  'teamcoder',
  'teamreviewer',
  'propose',
  'proposeagain',
  'proposeefforts',
  'proposeeffortsagain',
  'soak',
  'soaklead',
  'soakturn',
] as const;

type Scenario = (typeof SCENARIOS)[number];

function isScenario(value: string | undefined): value is Scenario {
  return SCENARIOS.includes(value as Scenario);
}

function defaultScenario(): Scenario {
  const flag = ARGS.indexOf('--scenario');
  const chosen = flag >= 0 ? ARGS[flag + 1] : process.env.CHORD_FAKE_SCENARIO;

  if (chosen === undefined) {
    return 'text';
  }

  if (!isScenario(chosen)) {
    throw new Error(`unknown scenario "${chosen}"`);
  }

  return chosen;
}

/** An answer that never comes. */
function never(): Promise<never> {
  return new Promise(() => {});
}

if (HANG !== undefined) {
  process.on('SIGTERM', () => {});

  // A wedged agent does not notice its client leaving, but its own parent
  // dying leaves nobody to send the SIGKILL: it is in a group of its own, so
  // a killed test run or chord takes nothing of it along. A parent that died
  // before this line ran has already handed it to init, pid 1.
  const parent = process.ppid;

  setInterval(() => {
    if (parent === 1 || process.ppid !== parent) {
      process.exit(1);
    }
  }, 200);
}

function promptText(prompt: acp.ContentBlock[]): string {
  return prompt
    .map((block) => (block.type === 'text' ? block.text : ''))
    .join('')
    .trim();
}

/** Every scenario, each family's from its module under `scenarios/`. */
const PLAY: Record<Scenario, Play> = {
  ...TEXT,
  ...TOOLS,
  ...PERMISSIONS,
  ...PLANS,
  ...FORMS,
  ...SHELL,
  ...COMPACTION,
  ...MODES,
  ...SUBAGENTS,
  ...MISBEHAVING,
  ...CHORD_TOOLS,
  ...TASKS,
  ...CYCLES,
  ...AGENTS,
  ...EFFORTS,
  ...MONITORS,
  ...TEAMS,
  ...SOAK,
};

const fallback = defaultScenario();
const turns = new Map<string, AbortController>();
/** The turn each session is playing, which a steer goes into. */
const playing = new Map<string, Turn>();
/** Each session's `session/prompt` still unanswered, which a late steer waits out. */
const prompted = new Map<string, Promise<unknown>>();

/**
 * The messages chord holds for a session's next prompt and sends ahead of
 * it, each joined to the next by a blank line, as `Conversation.send` does.
 */
const HELD_NOTES =
  /^(?:<message from="[^"]*"(?: monitor="[^"]*")?>\n[\s\S]*?\n<\/message>\n\n)+/;

/**
 * chord's note that calls of its tools were cut off, sent ahead of the next
 * prompt (CHD-417): answered first, its first line quoted, and the prompt
 * behind it played as if it came alone.
 */
const CUT_NOTE =
  /^<message from="chord">\n(Your \S+ (?:to @\S+ )?(?:call )?was cut off before it reached chord[\s\S]*?)\n<\/message>\n\n/;

/**
 * `text` as a JSON string with every C0, DEL and C1 character as `\uXXXX`:
 * `JSON.stringify` leaves DEL and C1 raw, which the transcript gives no cells.
 */
function quoted(text: string): string {
  // eslint-disable-next-line no-control-regex
  const escaped = text.replace(/["\\\u0000-\u001f\u007f-\u009f]/g, (found) =>
    found === '"' || found === '\\'
      ? `\\${found}`
      : `\\u${found.charCodeAt(0).toString(16).padStart(4, '0')}`,
  );

  return `"${escaped}"`;
}

/**
 * A prompt that starts with one of `FAKE_COMMANDS`: `greet` answers with a
 * fixed line, `echo` with what follows it; or with `verbatim`.
 */
async function playCommand(
  turn: Turn,
  text: string,
): Promise<acp.StopReason | undefined> {
  // `/team new` as it reaches the agent: the words after chord's line that
  // names propose_team, behind the notes chord held for main's next prompt,
  // each a wrapped message on its own, as a run's `/team run` leaves one.
  if (
    text
      .replace(HELD_NOTES, '')
      .startsWith('The person asks for a team of agents through /team new')
  ) {
    return await PLAY.propose(turn);
  }

  // `verbatim <text>` says the text back quoted, so a control character
  // chord sent shows on screen as its escape.
  const verbatim = /^verbatim (.*)$/s.exec(text);

  if (verbatim) {
    await turn.say(quoted(verbatim[1]!));

    return 'end_turn';
  }

  const [, name, rest = ''] = /^\/(\S+)\s*(.*)$/s.exec(text) ?? [];

  switch (name) {
    case 'greet':
      await turn.say('Hello', ' from the fake agent.');

      return 'end_turn';
    case 'echo':
      await turn.say(rest === '' ? '(nothing to echo)' : rest);

      return 'end_turn';
    default:
      return undefined;
  }
}

/**
 * A message another agent sent through chord, wrapped as chord wraps one:
 * answered with a line that says who it was from, whatever it says, or with
 * `asked`, the whole prompt, under `ECHO_MESSAGES`.
 */
async function playMessage(
  turn: Turn,
  from: string,
  asked: string,
): Promise<acp.StopReason> {
  await turn.say(
    ECHO_MESSAGES
      ? `Received ${quoted(asked)}`
      : `Received the message from ${from}.`,
  );

  return 'end_turn';
}

/** Every session this process created, oldest first, for `session/list`. */
const created: acp.SessionInfo[] = [];

/** Each model's context window, as its name gives it. */
const WINDOWS: Record<string, number> = {
  'fake-large': 1_000_000,
  'fake-small': 200_000,
};

/** The tokens every turn reports, as `PromptResponse.usage`. */
const TURN_USAGE = {
  inputTokens: 1000,
  outputTokens: 200,
  cachedReadTokens: 800,
  totalTokens: 2000,
};

/** What each turn adds to the session's cost, in USD. */
const TURN_COST = 0.0125;

/** How long after its answer a late turn's cost comes. */
const LATE_COST_MS = 100;

/** A turn's cost held for its session's next prompt, with `--cost-at-next`. */
const heldCosts = new Map<string, Update>();

/** How many turns each session has reported usage for. */
const reported = new Map<string, number>();

/**
 * The usage a turn that set none of its own reports as it ends: the session's
 * totals so far in a `usage_update`, the turn's own tokens in the answer.
 */
async function reportUsage(turn: Turn): Promise<void> {
  const count = (reported.get(turn.sessionId) ?? 0) + 1;

  reported.set(turn.sessionId, count);

  // The session's running total, every turn so far, with `--session-usage`.
  const times = SESSION_USAGE ? count : 1;
  const usage = {
    inputTokens: TURN_USAGE.inputTokens * times,
    outputTokens: TURN_USAGE.outputTokens * times,
    cachedReadTokens: TURN_USAGE.cachedReadTokens * times,
    totalTokens: TURN_USAGE.totalTokens * times,
  };

  // With `--no-cost` as well, the usage update still goes, with no cost.
  if (TOKENS_ONLY && !NO_COST) {
    turn.usage = usage;

    return;
  }

  const cost = (costs.get(turn.sessionId) ?? COST_FROM) + TURN_COST;

  costs.set(turn.sessionId, cost);

  const update: Update = {
    sessionUpdate: 'usage_update',
    used: TURN_USAGE.totalTokens * count,
    size: WINDOWS[models.get(turn.sessionId) ?? FIRST_MODEL] ?? 0,
    ...(NO_COST ? {} : { cost: { amount: cost, currency: 'USD' } }),
  };

  turn.usage = usage;

  if (COST_AT_NEXT) {
    heldCosts.set(turn.sessionId, update);

    return;
  }

  if (!LATE_COST) {
    await turn.send(update);

    return;
  }

  void (async () => {
    try {
      await pause(lifetime.signal, LATE_COST_MS);
      await turn.client.notify('session/update', {
        sessionId: turn.sessionId,
        update,
      });
    } catch {
      // The client went first.
    }
  })();
}

/**
 * What a loaded session says happened before: two prompts, a tool call that
 * read a file, and the replies, as the `tools` and `text` scenarios play them.
 */
const HISTORY: Update[] = [
  {
    sessionUpdate: 'user_message_chunk',
    content: { type: 'text', text: 'tools' },
  },
  {
    sessionUpdate: 'tool_call',
    toolCallId: 'history-read-1',
    title: 'Read README.md',
    kind: 'read',
    status: 'completed',
    locations: [{ path: 'README.md' }],
    rawInput: { path: 'README.md' },
    content: [{ type: 'content', content: { type: 'text', text: '# chord' } }],
    rawOutput: '# chord',
  },
  {
    sessionUpdate: 'agent_message_chunk',
    content: { type: 'text', text: 'Read it.' },
  },
  {
    sessionUpdate: 'user_message_chunk',
    content: { type: 'text', text: 'text' },
  },
  {
    sessionUpdate: 'agent_message_chunk',
    content: {
      type: 'text',
      text: 'Hello, world. This reply came in chunks.',
    },
  },
];

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/** The modes `session/new` and its kin answer with, the older way. */
function sessionModes(): { modes?: acp.SessionModeState } {
  return NO_MODES
    ? {}
    : { modes: { currentModeId: 'default', availableModes: AVAILABLE_MODES } };
}

/** Sends the commands just after the reply, as Claude's adapter does. */
function advertiseCommands(client: Client, sessionId: string): void {
  setTimeout(
    () =>
      void client
        .notify('session/update', {
          sessionId,
          update: {
            sessionUpdate: 'available_commands_update',
            availableCommands: FAKE_COMMANDS,
          },
        })
        .catch(() => {}),
  );
}

/**
 * Plays a prompt as a turn of the session's: the one `session/prompt` asks
 * for, or one a steer started with no turn running, as Codex's adapter does,
 * which says nothing before `answered`, the steer's answer, has gone.
 */
async function playPrompt(
  client: Client,
  params: Pick<acp.PromptRequest, 'sessionId' | 'prompt'>,
  answered: Promise<void> = Promise.resolve(),
): Promise<acp.PromptResponse> {
  if (HANG === 'turn') {
    await never();
  }

  heard(params.sessionId, promptText(params.prompt));

  // Codex's adapter does not stop a turn it started itself for a prompt:
  // the two would run side by side.
  const alongside = STEERING === 'codex' && turns.has(params.sessionId);

  turns.get(params.sessionId)?.abort();

  const controller = new AbortController();

  turns.set(params.sessionId, controller);

  const { runs, text: whole } = splitContext(promptText(params.prompt));
  const cutNote = CUT_NOTE.exec(whole.trimStart());
  const text =
    cutNote === null ? whole : whole.trimStart().slice(cutNote[0].length);
  const asked = text.trim();
  const scenario = isScenario(asked) ? asked : fallback;

  const turn = new Turn(client, params.sessionId, controller.signal);

  try {
    playing.set(params.sessionId, turn);
    await answered;

    if (alongside) {
      await turn.say('Started alongside a turn still playing. ');
    }

    if (cutNote !== null) {
      await turn.say(
        `Received chord's note: ${cutNote[1]!.split('\n')[0]}\n\n`,
      );
    }

    for (const run of runs) {
      const first = run.stdout.split('\n')[0] ?? '';

      await turn.say(`Received \`${run.command}\`: ${first}\n\n`);
    }

    for (const block of params.prompt) {
      if (block.type === 'image') {
        const bytes = atob(block.data).length;

        await turn.say(
          `Received an image: ${block.mimeType}, ${bytes} bytes\n\n`,
        );
      } else if (block.type === 'resource_link') {
        await turn.say(`Received a link: ${block.name}, ${block.uri}\n\n`);
      }
    }

    // A team agent's first prompt has its team part ahead of the message,
    // and plays as its role in the team: the lead, `tester` or `coder`.
    const team =
      /^<team name="[^"]*" role="(lead|member)"(?: member="([^"]*)")?>\n([\s\S]*?)\n<\/team>\n/.exec(
        asked,
      );
    const wrapped = team === null ? asked : asked.slice(team[0].length);
    // A monitor's names its id after the sender.
    const message =
      /^<message from="([^"]*)"(?: monitor="[^"]*")?>\n([\s\S]*)\n<\/message>$/.exec(
        wrapped,
      );
    const said = message?.[2]?.trim();
    const role = team === null ? undefined : `team${team[2] ?? team[1]}`;

    if (message) {
      senders.set(params.sessionId, message[1]!.split(' · ')[0]!);
    }

    if (team !== null && message) {
      teamParts.set(params.sessionId, {
        from: message[1]!.split(' · ')[0]!,
        text: team[3]!,
      });
    }

    // A message that names a scenario plays it, a team agent's first
    // one too; any other first message plays the agent's role.
    const stopReason =
      message && isScenario(said)
        ? await PLAY[said](turn)
        : message && isScenario(role)
          ? await PLAY[role](turn)
          : message
            ? await playMessage(turn, message[1]!, asked)
            : ((await playCommand(turn, asked)) ??
              // The words after a proposal say what to change in it.
              (await (() => {
                const again = proposing.get(params.sessionId);

                proposing.delete(params.sessionId);

                return again !== undefined && !isScenario(asked)
                  ? PLAY[again](turn)
                  : PLAY[scenario](turn);
              })()));

    // A message steered in after the last step is read before the end, as
    // an adapter's turn goes on until it has answered one.
    await turn.read();

    if (HOLD_REPLY && message) {
      await gateOpened(turn, GATE_RELEASE);
    }

    if (turn.usage === undefined && stopReason === 'end_turn' && !NO_USAGE) {
      await reportUsage(turn);
    }

    return turn.usage === undefined
      ? { stopReason }
      : { stopReason, usage: turn.usage };
  } catch (error) {
    if (controller.signal.aborted) {
      return { stopReason: 'cancelled' as const };
    }

    throw error;
  } finally {
    turn.end();

    if (turns.get(params.sessionId) === controller) {
      turns.delete(params.sessionId);
      playing.delete(params.sessionId);
    }
  }
}

/** `_session/steering`'s params, as both adapters take them. */
interface SteerRequest {
  readonly sessionId: string;
  readonly prompt: acp.ContentBlock[];
  readonly _meta?: {
    readonly steering?: { readonly idleBehavior?: string };
  };
}

/** How a session was opened, as `opened` says it: `meta` only when sent. */
function opened(method: string, meta: unknown) {
  return meta === undefined || meta === null ? { method } : { method, meta };
}

/**
 * The ways in `--auth-required methods` offers at `initialize`: one whose
 * description names the command to run, one with a name alone.
 */
const AUTH_METHODS: acp.AuthMethod[] = [
  {
    id: 'fake-login',
    name: 'Log in with the fake',
    description: 'Run `fake login` in the terminal',
  },
  { id: 'fake-sso', name: 'Log in with SSO' },
];

/**
 * Refuses a session request under `--auth-required`, as an agent nobody
 * signed in to does (CHD-435): `authRequired`; with `link`, after a sign-in
 * link asked outside any session while the request waits that is not
 * accepted, as droid 0.244.0 does (its `authenticateWithElicitation`).
 */
async function refuseUnsigned(
  client: acp.AgentContext,
  requestId: acp.JsonRpcId,
): Promise<void> {
  if (AUTH_REQUIRED === 'methods') {
    throw acp.RequestError.authRequired(
      undefined,
      'run `fake login` from your terminal, or set FAKE_API_KEY',
    );
  }

  if (AUTH_REQUIRED === 'bare') {
    throw acp.RequestError.authRequired();
  }

  if (AUTH_REQUIRED === 'link' || AUTH_REQUIRED === 'linkother') {
    const answer = await client.request('elicitation/create', {
      requestId,
      mode: 'url',
      elicitationId: crypto.randomUUID(),
      message: 'Sign in to the fake to continue',
      url: LINK_URL,
    });

    if (answer.action !== 'accept') {
      throw AUTH_REQUIRED === 'link'
        ? acp.RequestError.authRequired(
            undefined,
            'Sign-in was cancelled. Retry to sign in.',
          )
        : new acp.RequestError(-32603, 'The fake could not open its session.');
    }
  }
}

// An agent that cannot start goes before it reads a line (CHD-454).
if (START_FAILS === 'traceback') {
  process.stderr.write(
    [
      'Traceback (most recent call last):',
      ...Array.from({ length: 60 }, (_, n) => [
        `  File "/opt/agent/lib/python3.12/site-packages/agent/module_${n}.py", line ${n + 10}, in <module>`,
        `    from .module_${n + 1} import run`,
      ]).flat(),
      TRACEBACK_ERROR,
      '',
    ].join('\n'),
  );
  process.exit(1);
}

if (START_FAILS === 'stdout') {
  process.stdout.write(
    'fake-agent is no longer maintained. Please use its successor.\n',
  );
  process.exit(0);
}

/**
 * Refuses a session request as an agent that cannot open one under
 * `--start-fails` does: one with no ACP sessions at all, every request
 * not found; one that needs an agent alias it was not given, `session/new`.
 */
function refuseSession(method: string): void {
  if (START_FAILS === 'notacp') {
    throw new acp.RequestError(-32601, `Method not found: ${method}`);
  }

  if (START_FAILS === 'alias' && method === 'session/new') {
    throw new acp.RequestError(
      -32602,
      'session/new requires `agentAlias` (alias of a configured [agents.<alias>] entry)',
    );
  }
}

const connection = acp
  .agent({ name: 'chord-fake-agent' })
  .onRequest('initialize', ({ params }) => {
    readCapabilities(params);

    return HANG === 'start'
      ? never()
      : {
          protocolVersion: acp.PROTOCOL_VERSION,
          ...(AUTH_REQUIRED === 'methods' ? { authMethods: AUTH_METHODS } : {}),
          agentCapabilities: {
            loadSession: !NO_LOAD,
            mcpCapabilities: MCP_TRANSPORTS,
            promptCapabilities: { image: !NO_IMAGES },
            sessionCapabilities: {
              list: {},
              ...(RESUME_ONLY ? { resume: {} } : {}),
            },
          },
          // Steering as Claude's adapter, it names itself as that adapter does,
          // whose steer cuts the turn's open calls off.
          agentInfo: {
            name:
              STEERING === 'claude' || ADAPTER === 'claude'
                ? '@agentclientprotocol/claude-agent-acp'
                : 'chord-fake-agent',
            version: '0.0.0',
          },
          ...(STEERING === undefined
            ? {}
            : { _meta: { steering: { supported: true } } }),
        };
  })
  .onRequest('authenticate', () => ({}))
  .onRequest('session/new', async ({ params, client, requestId }) => {
    refuseSession('session/new');
    await refuseUnsigned(client, requestId);

    const sessionId = crypto.randomUUID();

    modes.set(sessionId, 'default');
    mcpServers.set(sessionId, params.mcpServers);
    openedWith.set(sessionId, opened('session/new', params._meta));
    cwds.set(sessionId, params.cwd);
    created.push({ sessionId, cwd: params.cwd });
    // The client hears of the commands only once the session is already up.
    advertiseCommands(client, sessionId);

    return {
      sessionId,
      ...sessionModes(),
      configOptions: configOptions(sessionId),
    };
  })
  // The sessions this process created, newest first, in the directory asked
  // for or in all of them.
  .onRequest('session/list', ({ params }) => ({
    sessions: created
      .filter((session) => !params.cwd || session.cwd === params.cwd)
      .toReversed(),
  }))
  .onRequest('session/load', async ({ params, client, requestId }) => {
    const { sessionId } = params;

    refuseSession('session/load');
    await refuseUnsigned(client, requestId);

    if (process.env.CHORD_FAKE_REFUSE_LOAD === '1' || !UUID.test(sessionId)) {
      throw acp.RequestError.resourceNotFound(sessionId);
    }

    modes.set(sessionId, 'default');
    mcpServers.set(sessionId, params.mcpServers);
    openedWith.set(sessionId, opened('session/load', params._meta));
    cwds.set(sessionId, params.cwd);
    loadMarks.set(sessionId, crypto.randomUUID().slice(0, 8));

    // The whole past goes out before the reply, so the client has it all
    // once the load returns.
    for (const update of HISTORY) {
      await client.notify('session/update', { sessionId, update });
    }

    advertiseCommands(client, sessionId);

    return {
      ...sessionModes(),
      configOptions: configOptions(sessionId),
    };
  })
  .onRequest('session/resume', async ({ params, client, requestId }) => {
    const { sessionId } = params;

    refuseSession('session/resume');
    await refuseUnsigned(client, requestId);

    if (
      !RESUME_ONLY ||
      process.env.CHORD_FAKE_REFUSE_LOAD === '1' ||
      !UUID.test(sessionId)
    ) {
      throw acp.RequestError.resourceNotFound(sessionId);
    }

    modes.set(sessionId, 'default');
    mcpServers.set(sessionId, params.mcpServers ?? []);
    openedWith.set(sessionId, opened('session/resume', params._meta));
    cwds.set(sessionId, params.cwd);
    loadMarks.set(sessionId, crypto.randomUUID().slice(0, 8));
    advertiseCommands(client, sessionId);

    if (CYCLE_ON_RESUME) {
      runCycle(client, sessionId);
    }

    return {
      ...sessionModes(),
      configOptions: configOptions(sessionId),
    };
  })
  // Answered as Claude's adapter answers it: the new mode goes out in the
  // config options before the reply, and no `current_mode_update` is sent.
  .onRequest('session/set_mode', async ({ params, client }) => {
    if (HANG === 'config') {
      await never();
    }

    if (NO_MODES) {
      throw acp.RequestError.methodNotFound('session/set_mode');
    }

    if (!AVAILABLE_MODES.some((mode) => mode.id === params.modeId)) {
      throw acp.RequestError.invalidParams(
        undefined,
        `Mode ${params.modeId} is not available in this session`,
      );
    }

    if (locked.has(params.sessionId)) {
      throw new acp.RequestError(-32603, 'The fake agent holds its mode.');
    }

    modes.set(params.sessionId, params.modeId);

    if (SILENT_SET_MODE) {
      return {};
    }

    await client.notify('session/update', {
      sessionId: params.sessionId,
      update: {
        sessionUpdate: 'config_option_update',
        configOptions: configOptions(params.sessionId),
      },
    });

    return {};
  })
  // A model, a mode or an effort is chosen through its config option, and the
  // answer carries every option as it now stands, as ACP asks.
  .onRequest('session/set_config_option', async ({ params }) => {
    if (HANG === 'config') {
      await never();
    }

    const value = String(params.value);
    const offered =
      params.configId === 'model'
        ? AVAILABLE_MODELS
        : params.configId === 'mode' && !NO_MODES
          ? AVAILABLE_MODES.map(({ id }) => ({ value: id }))
          : params.configId === 'effort' && !NO_CONFIG
            ? AVAILABLE_EFFORTS
            : params.configId === 'permission' &&
                DIMCODE_PERMISSION !== undefined
              ? DIMCODE_PERMISSIONS
              : [];

    if (!offered.some((entry) => entry.value === value)) {
      throw acp.RequestError.invalidParams(
        undefined,
        `${params.configId} cannot be ${value}`,
      );
    }

    if (params.configId === 'effort' && REFUSE_CONFIG) {
      throw new acp.RequestError(-32603, 'The fake agent holds its effort.');
    }

    if (params.configId === 'mode' && locked.has(params.sessionId)) {
      throw new acp.RequestError(-32603, 'The fake agent holds its mode.');
    }

    const chosen =
      params.configId === 'model'
        ? models
        : params.configId === 'mode'
          ? modes
          : params.configId === 'permission'
            ? permissions
            : efforts;

    chosen.set(params.sessionId, value);

    // Codex's adapter says nothing of the mode it moved to.
    if (params.configId === 'mode' && SILENT_SET_MODE) {
      return {} as acp.SetSessionConfigOptionResponse;
    }

    return { configOptions: configOptions(params.sessionId) };
  })
  // The older way to pick a model, which Claude's adapter still answers.
  .onRequest(
    'session/set_model',
    (params) => params as { sessionId: string; modelId: string },
    async ({ params }) => {
      if (HANG === 'config') {
        await never();
      }

      if (!AVAILABLE_MODELS.some((model) => model.value === params.modelId)) {
        throw acp.RequestError.invalidParams(
          undefined,
          `Model ${params.modelId} is not available`,
        );
      }

      models.set(params.sessionId, params.modelId);

      return {};
    },
  )
  .onRequest('session/prompt', async ({ params, client }) => {
    const held = heldCosts.get(params.sessionId);

    // The last turn's cost, held for this one, which has now begun.
    if (held !== undefined) {
      heldCosts.delete(params.sessionId);
      await client.notify('session/update', {
        sessionId: params.sessionId,
        update: held,
      });
    }

    const answered = playPrompt(client, params);

    prompted.set(params.sessionId, answered);

    try {
      return await answered;
    } finally {
      if (prompted.get(params.sessionId) === answered) {
        prompted.delete(params.sessionId);
      }
    }
  })
  // Steering as `--steering` names the adapter: into the turn playing, or,
  // with none, Claude's `promptRequired` where asked, else a turn of the
  // agent's own, which Codex's adapter starts whatever it was asked.
  .onRequest(
    '_session/steering',
    (params) => params as SteerRequest,
    async ({ params, client }) => {
      if (STEERING === undefined) {
        throw acp.RequestError.methodNotFound('_session/steering');
      }

      steers.emit(params.sessionId);

      const late = STEER_LATE ? prompted.get(params.sessionId) : undefined;

      if (late !== undefined) {
        await late.catch(() => {});
      }

      const turn = playing.get(params.sessionId);

      if (turn !== undefined) {
        heard(params.sessionId, promptText(params.prompt));
        turn.steer(promptText(params.prompt));

        return { outcome: 'injected' };
      }

      if (
        STEERING === 'claude' &&
        params._meta?.steering?.idleBehavior === 'promptRequired'
      ) {
        return { outcome: 'promptRequired', reason: 'noRunningTurn' };
      }

      // Codex's answers once the turn it started is running, before it says
      // anything, here a while after the turn the steer missed has answered.
      const answering =
        late === undefined ? Promise.resolve() : delay(STEP_MS * 20);

      void playPrompt(client, params, answering).catch(() => {});

      await answering;

      return { outcome: 'startedNewTurn' };
    },
  )
  .onNotification('session/cancel', ({ params, client }) => {
    // A Claude subagent's own id stops that one alone.
    void claudeChildren
      .get(params.sessionId)?.()
      .catch(() => {});

    const turn = turns.get(params.sessionId);

    if (turn === undefined && !claudeChildren.has(params.sessionId)) {
      strayCancels.set(
        params.sessionId,
        (strayCancels.get(params.sessionId) ?? 0) + 1,
      );

      if (SAY_CANCELS) {
        void client
          .notify('session/update', {
            sessionId: params.sessionId,
            update: {
              sessionUpdate: 'agent_message_chunk',
              content: { type: 'text', text: 'Cancel heard with no turn.' },
            },
          })
          .catch(() => {});
      }
    }

    turn?.abort();
  })
  .connect(
    acp.ndJsonStream(
      Writable.toWeb(process.stdout),
      Readable.toWeb(process.stdin) as unknown as ReadableStream<Uint8Array>,
    ),
  );

// The client closing stdin is how an ACP agent is told to go: stop any turn
// still playing so no timer keeps the process alive after its client left.
await connection.closed;

for (const turn of turns.values()) {
  turn.abort();
}

lifetime.abort();
