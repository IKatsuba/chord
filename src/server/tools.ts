/**
 * The tools chord's MCP server offers, by the role of the session that calls:
 * every agent chord opens but a task lists the runtimes chord knows and
 * starts task agents of its own; a session the person opened also lists the
 * window's open sessions and the saved teams, opens, messages and closes
 * long-lived agents, and hands a team a job; a child, of either kind, sends
 * messages to its parent alone, but a team's lead opens, messages and closes
 * its file's members and messages main and the other runs' leads, and a
 * member messages its lead and the team's other open members; and the
 * person's sessions and long-lived children start, stop and list monitors of
 * their own, which a task, gone after its first turn, does not. Each answer
 * is worked out here from what the window reads of itself, so it is tested
 * without a server.
 */
import type { Budgets } from '../session/budgets.ts';
import {
  RunSelection,
  type SelectionReceipt,
} from '../session/team_selection.ts';
import type { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { z } from '@zod/zod';
import { formatElapsed } from '../session/elapsed.ts';
import type {
  MonitorStarted,
  MonitorStopped,
} from '../session/conversation.ts';
import type { AgentEffort } from '../session/efforts.ts';
import type { AgentModel } from '../session/models.ts';
import type { AgentMode } from '../session/modes.ts';
import {
  BATCH_MS,
  EVENT_LINES,
  FLOOD_BYTES,
  FLOOD_LINES,
  FLOOD_MS,
  type MonitorArgs,
  type RunningMonitor,
  timeoutWords,
} from '../session/monitors.ts';
import type {
  ChordCall,
  ChordTool,
  PermissionWait,
} from '../session/transcript/types.ts';
import {
  saveSettingAt,
  type SettingChange,
  shownSettingPath,
} from '../settings.ts';
import {
  changeWord,
  plannedSetting,
  readSettingsTool,
  saveFailure,
  type SettingsChanged,
  shownHome,
  type SettingsWhere,
} from '../settings_tool.ts';
import {
  checkProposal,
  type FoundTeam,
  proposalShape,
  saveTeam,
  type Team,
} from '../teams.ts';

/**
 * Who a session is to chord, which says what it may call: one the person
 * opened, or a child one of those started, a task agent or a long-lived one.
 */
export type Role = 'person' | 'child';

/** What a session's token says of it. */
export interface Caller {
  /** One admission generation; old tokens cannot borrow a replacement's state. */
  readonly launch?: {
    readonly valid: () => boolean;
    readonly signal: () => AbortSignal;
  };
  /** The SDK cancels this request on cancellation or transport close. */
  readonly signal?: AbortSignal;
  readonly role: Role;
  /** The main session's key; a child's parent's, which is the main session's. */
  readonly key: number;
  /** A child's task id, as `spawn_task` answered it. */
  readonly task?: string;
  /** A long-lived child's id, as `open_agent` answered it. */
  readonly agent?: string;
  /**
   * The long-lived child that started a task, by its id; none for a task the
   * main session started.
   */
  readonly by?: string;
  /** A long-lived child that is a team's lead or one of its members. */
  readonly team?: 'lead' | 'member';
  /**
   * A fork's session, the person's but of no one: main's tools, but none that
   * opens, runs or closes agents of its own yet (CHD-101).
   */
  readonly fork?: true;
  readonly window: WindowView;
}

/** What `spawn_task` was asked. */
export interface SpawnArgs {
  readonly agent: string;
  readonly model?: string | undefined;
  /** Never refuses the start: a runtime that does not take it runs on its own. */
  readonly effort?: string | undefined;
  readonly prompt: string;
  readonly name?: string | undefined;
}

/**
 * Where an agent asked for an effort started: on the effort it is on, and,
 * when that is not the one asked for, the refusal as the transcript says it.
 */
export interface EffortStarted {
  readonly effort?: string;
  readonly note?: string;
}

/** A task started, by chord's id for it, or why it was not. */
export type SpawnAnswer =
  | ({
      readonly id: string;
      readonly name: string;
      readonly agent: string;
      readonly model?: string;
    } & EffortStarted)
  | { readonly error: string };

/** What `open_agent` was asked; a team's lead and member set `mode`. */
export interface OpenArgs extends SpawnArgs {
  readonly mode?: string | undefined;
}

/**
 * A long-lived agent opened, by chord's id for it, or why it was not; a
 * team agent's with the mode its file set.
 */
export type OpenAnswer =
  | ({
      readonly id: string;
      readonly name: string;
      readonly agent: string;
      readonly model?: string;
      readonly mode?: string;
    } & EffortStarted)
  | { readonly error: string };

/** What a lead's `open_agent` was asked: a member of its file, by name. */
export interface MemberArgs {
  readonly member: string;
  readonly prompt: string;
}

/** What `run_team` was asked. */
export interface RunTeamArgs {
  readonly team: string;
  readonly job: string;
  readonly selection?: RunSelection | undefined;
}

/**
 * A team's run started, by its lead's name and chord's id for it, on the
 * lead's runtime, model, effort and mode, or why it was not.
 */
export type RunTeamAnswer =
  | ({
      readonly id: string;
      readonly name: string;
      readonly team: string;
      readonly agent: string;
      readonly model?: string;
      readonly mode?: string;
      readonly receipt?: SelectionReceipt;
    } & EffortStarted)
  | {
      readonly error: string;
      readonly id?: string;
      readonly receipt?: SelectionReceipt;
    };

/**
 * How a message went: straight to its recipient, queued, or refused; `to`
 * is the recipient's name, for a message the parent sent.
 */
export type MessageAnswer =
  | { readonly delivered: 'sent' | 'queued'; readonly to?: string }
  | { readonly error: string };

/** A long-lived agent closed, by its name, or why it was not. */
export type CloseAnswer =
  { readonly closed: string } | { readonly error: string };

/** What `clear_agent` answers: the child cleared, once its fresh session is up. */
export type ClearAnswer =
  | {
      readonly cleared: string;
      readonly id: string;
      /** The messages queued to it that were not delivered, said so. */
      readonly dropped?: string;
    }
  | { readonly error: string };

/** A long-lived agent open in a session, as `list_sessions` gives it. */
export interface ChildView {
  readonly id: string;
  readonly name: string;
  readonly runtime: string;
  readonly model: string | undefined;
}

/** The window's session, as the tools read it. */
export interface OpenSessionView {
  readonly key: number;
  readonly runtime: string;
  /** The agent's id for it; none while it still starts. */
  readonly id: string | undefined;
  /** The model it uses, by the agent's id; none until the agent names one. */
  readonly model: string | undefined;
  /** Its long-lived agents, in the order they opened. */
  readonly children: readonly ChildView[];
}

/**
 * A model as `list_agents` gives it: with its efforts and the one it is on,
 * where they were read. Agents offer each model's own efforts, and only for
 * the model a session is on.
 */
export interface OfferedModel extends AgentModel {
  readonly efforts?: readonly AgentEffort[];
  readonly effort?: string;
}

/**
 * A runtime's models, efforts and modes, which ACP gives together in a
 * session's answer, or why they could not be read.
 */
export type RuntimeOffer =
  | {
      readonly models: readonly OfferedModel[];
      /**
       * The model in use in the session they were read from: a new session's,
       * for one opened only to read them.
       */
      readonly current?: string | undefined;
      /** Its modes; none for a runtime that offers none. */
      readonly modes?: readonly AgentMode[];
      /** The mode that session started in. */
      readonly currentMode?: string | undefined;
      /**
       * The efforts of a runtime that names no model to hang them on, and
       * the one that session started on.
       */
      readonly efforts?: readonly AgentEffort[];
      readonly currentEffort?: string | undefined;
    }
  | { readonly error: string };

/** What the tools read of the window. */
export interface WindowView {
  /** The providers' limits, read now; omitted, an injected window reads none. */
  budgets?(caller: Caller, agents?: readonly string[]): Promise<Budgets>;
  /** The sessions open in the window, in the strip's order. */
  sessions(): readonly OpenSessionView[];
  /** Every runtime chord can start, by the name a session is opened with. */
  runtimes(): readonly string[];
  /**
   * A runtime's models and modes: from a session of it, open or read
   * earlier, or, when `probe` is set, from one opened for the purpose and
   * closed. Undefined when none is known and `probe` is not set.
   */
  offer(
    runtime: string,
    probe: boolean,
    /**
     * The session asking, by its key: the directory it works in decides
     * how the runtime starts, or that it does not (CHD-466).
     */
    key?: number,
  ): Promise<RuntimeOffer | undefined>;
  /** Starts a task agent for the caller: the main session or its child. */
  spawn(caller: Caller, args: SpawnArgs): Promise<SpawnAnswer>;
  /**
   * Opens a long-lived agent for the main session, `key`; `caller`, when
   * given, is refused once its session has been let go (CHD-476).
   */
  open(key: number, args: OpenArgs, caller?: Caller): Promise<OpenAnswer>;
  /**
   * The teams saved for the caller's directory, and the leads of the runs
   * open in its session, by team.
   */
  teams(caller: Caller): Promise<TeamsFound>;
  /**
   * Where a team named `name` is saved for the caller's directory, and the
   * team saved under that name now, which a proposal would replace.
   */
  teamPlaces(caller: Caller, name: string): Promise<TeamPlaces>;
  /**
   * Asks the person in the main session's permission box: the option
   * they picked, by its id, or undefined once the question is withdrawn.
   */
  askPerson(
    caller: Caller,
    wait: Omit<PermissionWait, 'id'>,
    signal: AbortSignal,
  ): Promise<string | undefined>;
  /**
   * Where the caller's settings files are and how the window shows them, and
   * the runtime of the session that asks, which the box names.
   */
  settingsWhere(caller: Caller): SettingsWhere & { readonly agent: string };
  /** A `settings` write was saved: the window takes up what it can at once. */
  settingSaved(path: readonly string[], change: SettingChange): void;
  /** Hands a team a job: its lead opened as a child of the caller's. */
  runTeam(caller: Caller, args: RunTeamArgs): Promise<RunTeamAnswer>;
  /** A lead opens a member its team's file has. */
  openMember(caller: Caller, args: MemberArgs): Promise<OpenAnswer>;
  /**
   * A child's message to its parent; `queued` is called if one sent into
   * its running turn goes as the next turn after all.
   */
  message(caller: Caller, text: string, queued: () => void): MessageAnswer;
  /**
   * A message to `to`, by id or name: a parent's to its child, a lead's to
   * main, a member or another run's lead, a member's to its lead or another
   * member of its team; `queued` is called if one sent into its recipient's
   * running turn goes as the next turn after all.
   */
  tell(
    caller: Caller,
    to: string,
    text: string,
    queued: () => void,
  ): MessageAnswer;
  /** Closes the caller's child `to`, by id or name: a lead's, a member. */
  close(caller: Caller, to: string): CloseAnswer;
  /** `clear_agent`: a child of the caller's cleared; see `useSessions`. */
  clear(caller: Caller, to: string): Promise<ClearAnswer>;
  /** Starts a monitor for the caller, as `monitor` asks. */
  monitor(caller: Caller, args: MonitorArgs): MonitorAnswer;
  /** Stops the caller's own monitor `id`. */
  stopMonitor(caller: Caller, id: string): StopMonitorAnswer;
  /** The caller's own monitors still running. */
  monitors(caller: Caller): readonly RunningMonitor[];
  /** Tells the caller's session a tool was served to it, as it answered. */
  served(caller: Caller, call: ChordCall): void;
  /**
   * Where a call the caller is served again later goes, found now: a task
   * may have ended by then, and its row is still to be told.
   */
  servedLater(caller: Caller): (call: ChordCall) => void;
}

/** The team files found, and the runs open, as `list_teams` reads them. */
export interface TeamsFound {
  readonly found: readonly FoundTeam[];
  /** Each open run's lead, by its name, with its team's. */
  readonly runs: readonly {
    readonly team: string;
    readonly name: string;
    readonly id?: string;
  }[];
}

/** `list_teams`' answer: each team, or why its file cannot be run. */
export interface TeamsAnswer {
  readonly runs?: TeamsFound['runs'];
  readonly teams: readonly (
    | {
        readonly name: string;
        readonly description: string;
        readonly body: string;
        readonly lead: TeamAgentRow;
        readonly members: readonly (TeamAgentRow & {
          readonly name: string;
          readonly role: string;
          readonly instructions: string;
        })[];
        /** Its runs open in this session, by their leads' names. */
        readonly runs: readonly string[];
      }
    | { readonly name: string; readonly problem: string }
  )[];
}

interface TeamAgentRow {
  readonly agent: string;
  readonly model?: string;
  readonly effort?: string;
  readonly mode?: string;
  readonly instructions?: string;
}

function agentRow({
  agent,
  model,
  effort,
  mode,
  instructions,
}: Team['lead']): TeamAgentRow {
  return {
    agent,
    ...(model === undefined ? {} : { model }),
    ...(effort === undefined ? {} : { effort }),
    ...(mode === undefined ? {} : { mode }),
    ...(instructions === undefined ? {} : { instructions }),
  };
}

export function teamsAnswer({ found, runs }: TeamsFound): TeamsAnswer {
  return {
    runs: runs.map((run) => ({
      team: run.team,
      name: run.name,
      ...(run.id === undefined ? {} : { id: run.id }),
    })),
    teams: found.map((one) =>
      'problem' in one
        ? {
            name: one.name,
            problem: `${one.problem}; it cannot run until its file is fixed`,
          }
        : {
            name: one.name,
            description: one.team.description,
            body: one.team.body,
            lead: agentRow(one.team.lead),
            members: one.team.members.map((member) => ({
              name: member.name,
              ...agentRow(member),
              role: member.role,
              instructions: member.instructions,
            })),
            runs: runs
              .filter((run) => run.team === one.name)
              .map((run) => run.name),
          },
    ),
  };
}

/** A file, whole and as the window shows it. */
export interface PlacedFile {
  readonly file: string;
  readonly shown: string;
}

/** What `propose_team` reads of where a team goes. */
export interface TeamPlaces {
  /** The runtime of the session that proposes, which the box names. */
  readonly agent: string;
  readonly project: PlacedFile;
  /** None for a person without a home, who has no config directory. */
  readonly user?: PlacedFile;
  /**
   * The team saved under the name, project's over user's: its file, and the
   * team, none where the file fails its check.
   */
  readonly saved?: PlacedFile & { readonly team?: Team };
}

/**
 * What `propose_team` serves while the save box is open, and with the
 * person's answer: a new team or a change to one saved, the files each
 * choice writes, as shown, the team it changes, and once answered where it
 * was saved, or `false` when the person will say what to change.
 */
export type ProposeAnswer =
  | {
      readonly proposal: 'new' | 'change';
      readonly files: { readonly project?: string; readonly user?: string };
      readonly before?: Team;
      readonly saved?: string | false;
    }
  | { readonly error: string };

/** The save box's choices, by their ids. */
const SAVE = {
  project: 'project',
  user: 'user',
  replace: 'replace',
  change: 'change',
} as const;

/**
 * `propose_team`: the proposal checked as a team file is, drawn as it waits
 * (`shown`), the save box's question asked, and the file chord writes on a
 * yes, the agent never writing it. A refusal is the check's first problem,
 * or a write that failed.
 */
export async function proposeTeam(
  caller: Caller,
  input: unknown,
  signal: AbortSignal,
  shown: (answer: ProposeAnswer) => void,
): Promise<ProposeAnswer> {
  const checked = checkProposal(input, caller.window.runtimes());

  if ('problem' in checked) {
    return { error: checked.problem };
  }

  const { name, team } = checked;
  const places = await caller.window.teamPlaces(caller, name);
  const { agent, saved } = places;
  const proposal: ProposeAnswer =
    saved === undefined
      ? {
          proposal: 'new',
          files: {
            project: places.project.shown,
            ...(places.user === undefined ? {} : { user: places.user.shown }),
          },
        }
      : {
          proposal: 'change',
          files: {
            [saved.file === places.project.file ? 'project' : 'user']:
              saved.shown,
          },
          ...(saved.team === undefined ? {} : { before: saved.team }),
        };
  const change = `tell ${agent} what to change`;

  shown(proposal);

  const picked = await caller.window.askPerson(
    caller,
    {
      title: `Team(${name})`,
      options:
        saved === undefined
          ? [
              {
                optionId: SAVE.project,
                name: 'Yes, for this project',
                kind: 'allow_once',
              },
              ...(places.user === undefined
                ? []
                : [
                    {
                      optionId: SAVE.user,
                      name: 'Yes, for every project',
                      kind: 'allow_always' as const,
                    },
                  ]),
              {
                optionId: SAVE.change,
                name: `No, ${change}`,
                kind: 'reject_once',
              },
            ]
          : [
              {
                optionId: SAVE.replace,
                name: `Yes, in ${saved.shown}`,
                kind: 'allow_once',
              },
              {
                optionId: SAVE.change,
                name: `No, ${change}`,
                kind: 'reject_once',
              },
            ],
      save: {
        question: `${saved === undefined ? 'Save' : 'Replace'} team ${name}?`,
        files:
          saved === undefined
            ? {
                [SAVE.project]: places.project.shown,
                ...(places.user === undefined
                  ? {}
                  : { [SAVE.user]: places.user.shown }),
              }
            : {},
        escape: change,
      },
    },
    signal,
  );

  if (picked === undefined) {
    return { error: 'The person was not asked to the end; nothing was saved' };
  }

  if (picked === SAVE.change) {
    return { ...proposal, saved: false };
  }

  const target =
    picked === SAVE.replace
      ? saved
      : picked === SAVE.user
        ? places.user
        : places.project;

  if (target === undefined) {
    return { error: 'Nowhere to save it; nothing was saved' };
  }

  try {
    await saveTeam(target.file, team);
  } catch (error) {
    return {
      error: `${target.shown} was not saved: ${
        error instanceof Error ? error.message : String(error)
      }`,
    };
  }

  return { ...proposal, saved: target.shown };
}

/** What `propose_team` says to the agent, once the person answered. */
export function proposeText(
  answer: Exclude<ProposeAnswer, { readonly error: string }>,
): string {
  return typeof answer.saved === 'string'
    ? `Saved to ${answer.saved}.`
    : 'The person did not save it; they will say what to change.';
}

/** The settings box's choices, by their ids. */
const SETTING = { yes: 'yes', no: 'no' } as const;

/**
 * A `settings` `set` or `remove`: checked, drawn as it waits (`shown`), asked
 * in chord's box whatever mode the runtime is in, and written on a yes by
 * chord, the agent never writing it.
 */
export async function changeSetting(
  caller: Caller,
  path: readonly string[],
  change: SettingChange,
  signal: AbortSignal,
  shown: (answer: SettingsChanged) => void,
  asked: string,
): Promise<SettingsChanged | { readonly error: string }> {
  const where = caller.window.settingsWhere(caller);
  const planned = await plannedSetting(
    where,
    path,
    change,
    caller.window.runtimes(),
  );

  if ('error' in planned || planned.answer.unchanged === true) {
    return 'error' in planned ? planned : planned.answer;
  }

  const { answer, file } = planned;
  const shownKey = shownSettingPath(path);
  const word = changeWord(answer);
  const escape = `tell ${where.agent} what to change`;

  shown(answer);

  const picked = await caller.window.askPerson(
    caller,
    {
      title: `Settings(${shownKey})`,
      options: [
        {
          optionId: SETTING.yes,
          name: `Yes, in ${answer.file}`,
          kind: 'allow_once',
        },
        { optionId: SETTING.no, name: `No, ${escape}`, kind: 'reject_once' },
      ],
      save: {
        question: `${word[0]!.toUpperCase()}${word.slice(1)} ${shownKey}?`,
        files: {},
        escape,
        asked,
      },
    },
    signal,
  );

  if (picked === undefined) {
    return { error: 'The person was not asked to the end; nothing was saved' };
  }

  if (picked === SETTING.no) {
    return { ...answer, saved: false };
  }

  try {
    await saveSettingAt(file, path, change);
  } catch (error) {
    return { error: saveFailure(answer.file, error, shownHome(where)) };
  }

  caller.window.settingSaved(path, change);

  return { ...answer, saved: true };
}

/** A monitor started, by its id, or why it was not. */
export type MonitorAnswer = MonitorStarted | { readonly error: string };

/** A monitor stopped, or why it was not. */
export type StopMonitorAnswer = MonitorStopped | { readonly error: string };

/** `list_monitors`'s answer: the caller's own running monitors. */
export interface MonitorsAnswer {
  readonly monitors: readonly {
    readonly id: string;
    readonly description: string;
    readonly command: string;
    /** When it started, as an ISO 8601 time. */
    readonly started_at: string;
    readonly events: number;
    readonly timeout_ms: number;
  }[];
}

export function monitorsAnswer(
  monitors: readonly RunningMonitor[],
): MonitorsAnswer {
  return {
    monitors: monitors.map((monitor) => ({
      id: monitor.id,
      description: monitor.description,
      command: monitor.command,
      started_at: new Date(monitor.startedAt).toISOString(),
      events: monitor.events,
      timeout_ms: monitor.timeoutMs,
    })),
  };
}

function events(count: number): string {
  return count === 0
    ? 'no events'
    : `${count} ${count === 1 ? 'event' : 'events'}`;
}

/** What the model reads of a monitor started. */
export function monitorText(started: MonitorStarted): string {
  return (
    `Started monitor ${started.id} (${started.description}); it times ` +
    `out in ${timeoutWords(started.timeout_ms)}. Its output does not come ` +
    `in this answer: each batch of lines (up to ${EVENT_LINES}, gathered ` +
    `over ${BATCH_MS} ms) reaches you later as a message from ` +
    `"${started.description} · monitor", and so does its end. Keep ` +
    `working. stop_monitor with id "${started.id}" stops it.`
  );
}

/** What the model reads of a monitor it stopped. */
export function stopMonitorText(stopped: MonitorStopped): string {
  return `Stopped ${stopped.id} (${stopped.description}) after ${formatElapsed(
    stopped.ran_ms,
  )} and ${events(stopped.events)}.`;
}

/** What the model reads of its running monitors, `now` epoch milliseconds. */
export function monitorsText(
  monitors: readonly RunningMonitor[],
  now: number,
): string {
  return monitors.length === 0
    ? 'No monitors running'
    : `${monitors.length} running: ${monitors
        .map(
          (monitor) =>
            `${monitor.id} ${monitor.description} (${
              formatElapsed(now - monitor.startedAt).split(' ')[0]
            }, ${events(monitor.events)})`,
        )
        .join(', ')}`;
}

/** `list_agents`'s answer: every runtime, or the one asked about. */
export interface AgentsAnswer {
  readonly agents: readonly AgentRow[];
}

export interface AgentRow {
  readonly name: string;
  readonly models?: readonly OfferedModel[];
  readonly current?: string;
  readonly modes?: readonly AgentMode[];
  readonly currentMode?: string;
  readonly efforts?: readonly AgentEffort[];
  readonly currentEffort?: string;
  /** Why its models and modes could not be read, or how to read them. */
  readonly note?: string;
}

/**
 * Every runtime with the models and modes known without starting anything,
 * or, for `agent`, that runtime's, a session started to read them if need
 * be. Probing every runtime unasked would install and start each of the
 * registry's agents on the person's machine.
 */
export async function agentsAnswer(
  window: WindowView,
  agent?: string,
  key?: number,
): Promise<AgentsAnswer> {
  const runtimes = window.runtimes();

  if (agent !== undefined) {
    if (!runtimes.includes(agent)) {
      return {
        agents: [
          {
            name: agent,
            note:
              `chord knows no runtime named ${agent}; list_agents without ` +
              'an agent names every one',
          },
        ],
      };
    }

    return { agents: [row(agent, await window.offer(agent, true, key))] };
  }

  return {
    agents: await Promise.all(
      runtimes.map(async (name) =>
        row(name, await window.offer(name, false, key)),
      ),
    ),
  };
}

function row(name: string, offer: RuntimeOffer | undefined): AgentRow {
  if (offer === undefined) {
    return {
      name,
      note:
        `models and modes not read yet; list_agents with agent "${name}" ` +
        'reads them',
    };
  }

  if ('error' in offer) {
    return {
      name,
      note: `models and modes could not be read: ${offer.error}`,
    };
  }

  return {
    name,
    models: offer.models,
    ...(offer.current === undefined ? {} : { current: offer.current }),
    ...(offer.modes === undefined ? {} : { modes: offer.modes }),
    ...(offer.currentMode === undefined
      ? {}
      : { currentMode: offer.currentMode }),
    ...(offer.efforts === undefined ? {} : { efforts: offer.efforts }),
    ...(offer.currentEffort === undefined
      ? {}
      : { currentEffort: offer.currentEffort }),
  };
}

/** `list_sessions`'s answer: the window's session, the caller's marked. */
export interface SessionsAnswer {
  readonly sessions: readonly SessionRow[];
}

export interface SessionRow {
  readonly id: string | null;
  readonly runtime: string;
  readonly model: string | null;
  /** Set on the caller's own session. */
  readonly you?: true;
  /** Its long-lived agents, by chord's id for each; none when it has none. */
  readonly agents?: readonly AgentOpen[];
}

export interface AgentOpen {
  readonly id: string;
  readonly name: string;
  readonly runtime: string;
  readonly model: string | null;
}

export function sessionsAnswer(caller: Caller): SessionsAnswer {
  return {
    sessions: caller.window.sessions().map((open) => ({
      id: open.id ?? null,
      runtime: open.runtime,
      model: open.model ?? null,
      ...(open.key === caller.key && caller.role === 'person'
        ? { you: true as const }
        : {}),
      ...(open.children.length === 0
        ? {}
        : {
            agents: open.children.map((child) => ({
              id: child.id,
              name: child.name,
              runtime: child.runtime,
              model: child.model ?? null,
            })),
          }),
    })),
  };
}

function answer(value: unknown) {
  return {
    content: [{ type: 'text' as const, text: JSON.stringify(value, null, 2) }],
  };
}

/** A refusal, which the agent reads as the call's failure. */
function refusal(message: string) {
  return { content: [{ type: 'text' as const, text: message }], isError: true };
}

/**
 * The answer, after the caller's session hears what was served: the value
 * as JSON, or, given `said`, what it says for the model, with the value as
 * `structuredContent`.
 */
function serve<T>(
  caller: Caller,
  tool: ChordTool,
  input: unknown,
  value: T,
  said?: (value: Exclude<T, { readonly error: string }>) => string,
  asked?: string,
) {
  const error =
    typeof value === 'object' &&
    value !== null &&
    'error' in value &&
    typeof value.error === 'string'
      ? value.error
      : undefined;
  const task =
    tool === 'spawn_task' &&
    typeof value === 'object' &&
    value !== null &&
    'id' in value &&
    typeof value.id === 'string'
      ? value.id
      : undefined;

  caller.window.served(caller, {
    tool,
    input,
    ...(error === undefined ? { answer: value } : { error }),
    ...(task === undefined ? {} : { task }),
    ...(asked === undefined ? {} : { asked }),
    ...(tool === 'send_message' &&
    typeof value === 'object' &&
    value !== null &&
    'delivered' in value &&
    value.delivered === 'queued'
      ? { queued: true }
      : {}),
  });

  if (error !== undefined) {
    return refusal(error);
  }

  return said === undefined
    ? answer(value)
    : {
        content: [
          {
            type: 'text' as const,
            text: said(value as Exclude<T, { readonly error: string }>),
          },
        ],
        structuredContent: value as Record<string, unknown>,
      };
}

/**
 * `send_message` served. A message sent into its recipient's running turn
 * that goes as the next turn after all, as when the turn ended on the way,
 * is served again as queued in place of the first, so the sender's row
 * says it waited; the agent's answer, given already, stays as it was.
 */
function sendMessage(
  caller: Caller,
  input: unknown,
  send: (queued: () => void) => MessageAnswer,
) {
  const asked = crypto.randomUUID();
  const later = caller.window.servedLater(caller);
  const value = send(() =>
    later({
      tool: 'send_message',
      input,
      answer: value,
      queued: true,
      asked,
    }),
  );

  return serve(caller, 'send_message', input, value, undefined, asked);
}

type Register = (server: McpServer, caller: Caller) => void;

const listAgents: Register = (server, caller) =>
  server.registerTool(
    'list_agents',
    {
      description:
        'The agent runtimes chord can start, and the models and modes each ' +
        'offers, with the efforts of the model a session of it was read on ' +
        '(`efforts`, and `effort` for the one it is on), as agents offer ' +
        "each model's own. Without `agent`, they are given for runtimes " +
        'already read; name one to read its models and modes, which may ' +
        'start it briefly.',
      inputSchema: {
        agent: z
          .string()
          .optional()
          .describe(
            'A runtime to read the models and modes of, as list_agents names it',
          ),
      },
    },
    async (input) =>
      serve(
        caller,
        'list_agents',
        input,
        await agentsAnswer(caller.window, input.agent, caller.key),
      ),
  );

const getBudgets: Register = (server, caller) =>
  server.registerTool(
    'get_budgets',
    {
      description:
        "Reads each provider's usage limits now: per window, the percent " +
        'used and when it resets, or why the provider could not be read. ' +
        'Providers are read in parallel, waiting up to 10 s each. Omit ' +
        'agents to read claude and codex; [] reads none.',
      inputSchema: {
        agents: z
          .array(z.string().min(1).max(128))
          .max(128)
          .optional()
          .describe('Runtime IDs from list_agents to read only those'),
      },
    },
    async (input, extra) => {
      const request = { ...caller, signal: extra.signal };
      let budgets: Budgets | undefined;

      try {
        budgets = await caller.window.budgets?.(request, input.agents);
      } catch {
        budgets = undefined;
      }

      if (budgets === undefined) {
        return serve(request, 'get_budgets', input, {
          error: 'The limits could not be read.',
        });
      }

      return serve(request, 'get_budgets', input, budgets, (value) =>
        JSON.stringify(value, null, 2),
      );
    },
  );

const listSessions: Register = (server, caller) =>
  server.registerTool(
    'list_sessions',
    {
      description:
        'The session chord runs: its id, runtime and model, and the ' +
        'long-lived agents open in it, by id and name; yours marked `you`.',
    },
    () => serve(caller, 'list_sessions', {}, sessionsAnswer(caller)),
  );

const spawnTask: Register = (server, caller) =>
  server.registerTool(
    'spawn_task',
    {
      description:
        'Starts a task agent: another agent, on any runtime ' +
        'list_agents names and any model it offers, does one job in this ' +
        'directory and reports. The answer is its id at once, or, given an ' +
        'effort, once it has started on it or been refused it; its report ' +
        'comes to you later as a message, <message from="…">…</message>, ' +
        'once its first turn ends.',
      inputSchema: {
        agent: z.string().describe('The runtime, as list_agents names it'),
        model: z
          .string()
          .optional()
          .describe(
            "A model the runtime offers, by its id; the runtime's own if left " +
              'out',
          ),
        effort: z
          .string()
          .optional()
          .describe(
            'An effort the runtime offers for that model, by its id, as ' +
              "list_agents lists them (`efforts`); the runtime's own if left " +
              'out. One it does not take starts it on its own, and the ' +
              'answer says so',
          ),
        prompt: z.string().describe('The job, in full'),
        name: z
          .string()
          .optional()
          .describe(
            "A short name for it on screen; the prompt's first line if left out",
          ),
      },
    },
    async (input) =>
      serve(
        caller,
        'spawn_task',
        input,
        await caller.window.spawn(caller, input),
      ),
  );

/** What a tool that opens, runs or closes agents answers a fork (CHD-101). */
const FORK_REFUSED =
  'This tool works only from main and its agents, not from a fork.';

const openAgent: Register = (server, caller) =>
  server.registerTool(
    'open_agent',
    {
      description:
        'Opens a long-lived agent: another agent, on any runtime ' +
        'list_agents names and any model it offers, in this directory, with ' +
        'the prompt as its first turn. It stays open: you and the person can ' +
        'both talk to it, send_message reaches it and close_agent ends it. ' +
        'The answer is its id at once, or, given an effort, once it has ' +
        'started on it or been refused it; what it sends you comes later ' +
        'as a message, <message from="…">…</message>.',
      inputSchema: {
        agent: z.string().describe('The runtime, as list_agents names it'),
        model: z
          .string()
          .optional()
          .describe(
            "A model the runtime offers, by its id; the runtime's own if left " +
              'out',
          ),
        effort: z
          .string()
          .optional()
          .describe(
            'An effort the runtime offers for that model, by its id, as ' +
              "list_agents lists them (`efforts`); the runtime's own if left " +
              'out. One it does not take starts it on its own, and the ' +
              'answer says so',
          ),
        prompt: z.string().describe('Its first prompt, in full'),
        name: z
          .string()
          .optional()
          .describe(
            'A short name for it, which messages and the screen use; the ' +
              'runtime if left out',
          ),
      },
    },
    async (input) =>
      serve(
        caller,
        'open_agent',
        input,
        caller.fork
          ? { error: FORK_REFUSED }
          : await caller.window.open(caller.key, input, caller),
      ),
  );

const tellAgent: Register = (server, caller) =>
  server.registerTool(
    'send_message',
    {
      description:
        'Sends a message to a long-lived agent you opened. While it ' +
        'works, the message goes into the turn it is in, where its runtime ' +
        'takes that, after any question it waits on is answered; otherwise ' +
        'it reaches it as a turn of its own, queued behind that turn. The ' +
        'answer says it was delivered, not what it replied, which comes to ' +
        'you as a message.',
      inputSchema: {
        to: z
          .string()
          .describe('The agent, by the id open_agent answered or by its name'),
        text: z.string().describe('What to tell it'),
      },
    },
    (input) =>
      sendMessage(caller, input, (queued) =>
        caller.window.tell(caller, input.to, input.text, queued),
      ),
  );

const closeAgent: Register = (server, caller) =>
  server.registerTool(
    'close_agent',
    {
      description:
        'Closes a long-lived agent you opened, stopping what it ' +
        'is doing; it takes no more messages.',
      inputSchema: {
        to: z
          .string()
          .describe('The agent, by the id open_agent answered or by its name'),
      },
    },
    (input) =>
      serve(
        caller,
        'close_agent',
        input,
        caller.fork
          ? { error: FORK_REFUSED }
          : caller.window.close(caller, input.to),
      ),
  );

const clearAgent: Register = (server, caller) =>
  server.registerTool(
    'clear_agent',
    {
      description:
        'Clears a long-lived agent you opened: its turn stops and it gets a ' +
        'fresh session that knows nothing of earlier turns, with the same ' +
        "id and name. Your next message is its first; a team member's " +
        "carries its instructions, as open_agent's first message does. The " +
        'answer comes once the fresh session is up.',
      inputSchema: {
        to: z
          .string()
          .describe('The agent, by the id open_agent answered or by its name'),
      },
    },
    async (input) =>
      serve(
        caller,
        'clear_agent',
        input,
        caller.fork
          ? { error: FORK_REFUSED }
          : await caller.window.clear(caller, input.to),
        clearedText,
      ),
  );

/** `clear_agent`'s answer for the model (CHD-476). */
function clearedText(
  answer: Exclude<ClearAnswer, { readonly error: string }>,
): string {
  return `${answer.cleared} (id ${answer.id}) has a fresh session; it knows nothing of earlier turns.${
    answer.dropped === undefined ? '' : ` ${answer.dropped}`
  }`;
}

const messageParent: Register = (server, caller) =>
  server.registerTool(
    'send_message',
    {
      description:
        'Sends a message to the agent that started you, while ' +
        'you work. It goes into the turn that agent is in, where its runtime ' +
        'takes that, or else reaches it as a turn of its own; your last ' +
        'message when you finish is your report and goes to it without this.',
      inputSchema: {
        text: z.string().describe('What to tell it'),
      },
    },
    (input) =>
      sendMessage(caller, input, (queued) =>
        caller.window.message(caller, input.text, queued),
      ),
  );

const startMonitor: Register = (server, caller) =>
  server.registerTool(
    'monitor',
    {
      description:
        'Run a shell command in the background and hear from it ' +
        'later. Each line it prints to stdout is an event; lines within ' +
        `${BATCH_MS} ms come together, up to ${EVENT_LINES}, as one message ` +
        'from "<description> · monitor", which starts a new turn after the ' +
        "current one. This answer only gives the monitor's id. Use it to " +
        'wait on something without polling: a log (`tail -n 0 -f app.log | ' +
        'grep --line-buffered ERROR`), a poll loop, a CI run. Print only ' +
        'what you need to hear: a monitor printing more than ' +
        `${FLOOD_LINES.toLocaleString('en-US')} lines or ${
          FLOOD_BYTES / 1024
        } KiB within ${FLOOD_MS / 1000} s is stopped. stderr is dropped ` +
        'unless you merge it (`2>&1`). It ends when the command exits, when ' +
        'timeout_ms passes, or with stop_monitor; you get a message when it ' +
        'ends on its own.',
      inputSchema: {
        command: z
          .string()
          .describe(
            "Run through the person's shell in this session's directory",
          ),
        description: z
          .string()
          .describe(
            'What it watches, at most 60 characters on one line; shown on ' +
              'every event',
          ),
        timeout_ms: z
          .number()
          .optional()
          .describe(
            // An agent once set it to a timer loop's length, so every
            // heartbeat was cut off as it came (CHD-482, Q87).
            'A hard stop: chord stops the command when it passes, whatever ' +
              'it is doing, so make it longer than the command is meant to ' +
              "run (a loop's whole length and a margin). 1000 to 3600000; " +
              '600000 (10 minutes) if left out',
          ),
      },
    },
    (input) =>
      serve(
        caller,
        'monitor',
        input,
        caller.window.monitor(caller, {
          command: input.command,
          description: input.description,
          timeoutMs: input.timeout_ms,
        }),
        monitorText,
      ),
  );

const stopMonitor: Register = (server, caller) =>
  server.registerTool(
    'stop_monitor',
    {
      description:
        'Stops a monitor you started, and what its command ' +
        'started; no message follows.',
      inputSchema: {
        id: z.string().describe('The id monitor answered, such as m1'),
      },
    },
    (input) =>
      serve(
        caller,
        'stop_monitor',
        input,
        caller.window.stopMonitor(caller, input.id),
        stopMonitorText,
      ),
  );

const listMonitors: Register = (server, caller) =>
  server.registerTool(
    'list_monitors',
    {
      description:
        "Your monitors still running: each one's id, " +
        'description, command, when it started and how many events it sent.',
    },
    () => {
      const monitors = caller.window.monitors(caller);

      return serve(caller, 'list_monitors', {}, monitorsAnswer(monitors), () =>
        monitorsText(monitors, Date.now()),
      );
    },
  );

const listTeams: Register = (server, caller) =>
  server.registerTool(
    'list_teams',
    {
      description:
        'The teams saved for this project and every project: ' +
        "each one's description, shared body, lead/member instructions, " +
        'configuration including effort, roles, and open runs. Read these ' +
        'stored instructions before run_team. When the instructions or job ' +
        'make resources relevant, read get_budgets and list_agents before ' +
        'choosing per-run settings. Otherwise selection is not required.',
    },
    async () =>
      serve(
        caller,
        'list_teams',
        {},
        teamsAnswer(await caller.window.teams(caller)),
      ),
  );

const runTeam: Register = (server, caller) =>
  server.registerTool(
    'run_team',
    {
      description:
        'Hands a saved team a job. chord opens its lead as a ' +
        'long-lived agent of yours, named after the team (a second run of ' +
        "a running team is `<team> 2`), with the team's instructions and " +
        'the job as your message; the lead opens the members it needs. The ' +
        "answer is the lead's name at once, or, where the team gives the " +
        'lead an effort, once it has started on it or been refused it; its ' +
        'reports come to you later as messages, send_message reaches it, and close_agent closes it ' +
        'with its members. Read list_teams instructions first. Omit selection ' +
        'to run saved composition. Optional selection changes this run only, ' +
        'preserving every saved role and instruction; provide a reason that ' +
        'preserves their requirements and explains uncertainty. Call get_budgets ' +
        'when instructions or the job make resources matter. There is no ' +
        'automatic retry, substitution or saved-team rewrite.',
      inputSchema: z
        .looseObject({
          team: z.string().describe('The team, as list_teams names it'),
          job: z
            .string()
            .describe(
              'The job, in full: what to do, where, and when to report',
            ),
          selection: RunSelection.optional(),
        })
        .superRefine((input, context) => {
          if (input.selection !== undefined) {
            const strict = z
              .strictObject({
                team: z.string(),
                job: z.string(),
                selection: RunSelection,
              })
              .safeParse(input);

            if (!strict.success) {
              for (const issue of strict.error.issues) {
                context.addIssue({ ...issue });
              }
            }
          }
        }),
    },
    async (input, extra) => {
      if (caller.fork) {
        return serve(caller, 'run_team', input, { error: FORK_REFUSED });
      }

      const request = { ...caller, signal: extra.signal };
      // Records keep our declared domain fields; SDK input stays untouched.
      const recordedInput: RunTeamArgs = {
        team: input.team,
        job: input.job,
        ...(input.selection === undefined
          ? {}
          : { selection: input.selection }),
      };
      const result = await caller.window.runTeam(request, input);

      if (result.receipt !== undefined) {
        caller.window.served(request, {
          tool: 'run_team',
          input: recordedInput,
          asked: result.receipt.runId,
          answer: result,
          ...('error' in result ? { error: result.error } : {}),
        });

        return {
          ...answer(result),
          structuredContent: { ...result },
          ...('error' in result ? { isError: true } : {}),
        };
      }

      return serve(request, 'run_team', recordedInput, result);
    },
  );

const proposeTeamTool: Register = (server, caller) =>
  server.registerTool(
    'propose_team',
    {
      description:
        'Proposes a team for the person to save: a lead and its ' +
        'members, each on a runtime, model, effort and mode list_agents ' +
        'gives, and how the team works. chord draws it and asks the person ' +
        'to save it for this project, for every project, or to tell you ' +
        'what to change; chord writes the file, not you. Proposing a team under a ' +
        "saved team's name proposes a change to it. The answer says where " +
        'it was saved, or that the person will say what to change: then end ' +
        'your turn and wait for their words. A team that fails the check is ' +
        'refused with its first problem; correct it and call again.',
      inputSchema: proposalShape(),
    },
    async (input, extra) => {
      if (caller.fork) {
        return serve(caller, 'propose_team', input, { error: FORK_REFUSED });
      }

      const asked = crypto.randomUUID();
      const answer = await proposeTeam(caller, input, extra.signal, (shown) =>
        caller.window.served(caller, {
          tool: 'propose_team',
          input,
          answer: shown,
          pending: true,
          asked,
        }),
      );

      return serve(caller, 'propose_team', input, answer, proposeText, asked);
    },
  );

const settingsTool: Register = (server, caller) =>
  server.registerTool(
    'settings',
    {
      description:
        "Reads and edits chord's settings. `read` gives the user's file and " +
        "the project's as written, and the merged, checked settings that " +
        "take effect, with any problems; values under an MCP server's env " +
        'and headers read "***". `set` and `remove` change one key in the ' +
        "user's file, after chord asks the person, whatever mode you run " +
        'in; chord writes the file, not you. A path is a list of keys, as ' +
        "an agent's name may hold a dot. The keys chord writes are theme, " +
        'editorMode, mouse, copyOnSelect, offeredAgents, ' +
        'preferredNotifChannel, agent, agents.<name>.model and .effort, ' +
        'teamSelection.intent and teamSelection.prefer.agent and .model; ' +
        'the person edits any other by hand. The answer says what changed ' +
        'and when it takes effect. When `saved` is false and `unchanged` ' +
        'is not set, the person will say what to change: end your turn and ' +
        'wait for their words.',
      inputSchema: {
        action: z.enum(['read', 'set', 'remove']).describe('What to do'),
        path: z
          .array(z.string())
          .optional()
          .describe(
            'The key, as a list of keys; for a read, every key if left out',
          ),
        value: z.unknown().optional().describe('What `set` sets it to'),
      },
    },
    async (input, extra) => {
      if (caller.fork) {
        return serve(caller, 'settings', input, { error: FORK_REFUSED });
      }

      if (input.action !== 'read') {
        const asked = crypto.randomUUID();
        const changed = await changeSetting(
          caller,
          input.path ?? [],
          input.action === 'set' ? { set: input.value } : { remove: true },
          extra.signal,
          (shown) =>
            caller.window.served(caller, {
              tool: 'settings',
              input,
              answer: shown,
              pending: true,
              asked,
            }),
          asked,
        );

        return serve(caller, 'settings', input, changed, undefined, asked);
      }

      const read = await readSettingsTool(
        caller.window.settingsWhere(caller),
        input.path,
      );

      if ('error' in read) {
        return serve(caller, 'settings', input, read);
      }

      caller.window.served(caller, {
        tool: 'settings',
        input,
        answer: read.answer,
        settingsFiles: read.files,
      });

      return answer(read.answer);
    },
  );

const openMember: Register = (server, caller) =>
  server.registerTool(
    'open_agent',
    {
      description:
        "Opens one of your team's members, by its name in the team, on " +
        'the runtime, model, effort and mode the team gives it, with the ' +
        "team's instructions and your prompt as its first message. It " +
        'stays open: send_message reaches it, and close_agent closes it. ' +
        'The answer is its id at once, or, where the team gives it an ' +
        'effort, once it has started on it or been refused it; what it ' +
        'sends you comes later as a message.',
      inputSchema: {
        member: z.string().describe('The member, by its name in the team'),
        prompt: z.string().describe('Its first message from you, in full'),
      },
    },
    async (input, extra) =>
      serve(
        caller,
        'open_agent',
        input,
        await caller.window.openMember(
          { ...caller, signal: extra.signal },
          input,
        ),
      ),
  );

const tellTeam: Register = (server, caller) =>
  server.registerTool(
    'send_message',
    {
      description:
        caller.team === 'lead'
          ? 'Sends a message to main, to one of your open members, or to the ' +
            "lead of another team's run open in this session, by name. It " +
            'goes into the turn its recipient is in, where the runtime takes ' +
            'that, or else reaches it as a turn of its own; to an idle main, ' +
            "it starts main's turn. The answer says it was delivered, not " +
            'what it replied, which comes to you as a message.'
          : 'Sends a message to your lead, or to another open member of your ' +
            'team, by name, directly: the lead does not see it. It goes into ' +
            'the turn its recipient is in, where the runtime takes that, or ' +
            'else reaches it as a turn of its own; the answer says it was ' +
            'delivered, not what it replied, which comes to you as a message.',
      inputSchema: {
        to: z
          .string()
          .describe(
            caller.team === 'lead'
              ? "`main`, a member, or another run's lead, by name"
              : 'Your lead or another member, by name',
          ),
        text: z.string().describe('What to tell it'),
      },
    },
    (input) =>
      sendMessage(caller, input, (queued) =>
        caller.window.tell(caller, input.to, input.text, queued),
      ),
  );

const MONITORS: readonly Register[] = [startMonitor, stopMonitor, listMonitors];

/**
 * The tools a caller is given, registered on the MCP server it talks to; a
 * new tool or role is a line here.
 */
function toolsOf(caller: Caller): readonly Register[] {
  switch (caller.role) {
    case 'person':
      return [
        listAgents,
        getBudgets,
        listSessions,
        listTeams,
        spawnTask,
        openAgent,
        runTeam,
        proposeTeamTool,
        settingsTool,
        tellAgent,
        closeAgent,
        clearAgent,
        ...MONITORS,
      ];
    case 'child':
      // A task ends with its first turn: a later event would reach nobody,
      // and a task of its own would outlive it.
      return caller.agent === undefined
        ? [messageParent]
        : caller.team === 'lead'
          ? [
              listAgents,
              getBudgets,
              spawnTask,
              openMember,
              tellTeam,
              closeAgent,
              clearAgent,
              ...MONITORS,
            ]
          : caller.team === 'member'
            ? [listAgents, getBudgets, spawnTask, tellTeam, ...MONITORS]
            : [listAgents, getBudgets, spawnTask, messageParent, ...MONITORS];
  }
}

/** The monitor tools, which a person's session and a long-lived child get. */
export const MONITOR_TOOLS: readonly ChordTool[] = [
  'monitor',
  'stop_monitor',
  'list_monitors',
];

/**
 * The tools a session of `role` is given, by name, as `/mcp` lists them; a
 * child's are a long-lived one's, as only those are picked in the window.
 */
export function toolNames(role: Role): readonly ChordTool[] {
  return role === 'person'
    ? [
        'list_agents',
        'get_budgets',
        'list_sessions',
        'list_teams',
        'spawn_task',
        'open_agent',
        'run_team',
        'propose_team',
        'settings',
        'send_message',
        'close_agent',
        'clear_agent',
        ...MONITOR_TOOLS,
      ]
    : [
        'list_agents',
        'get_budgets',
        'spawn_task',
        'send_message',
        ...MONITOR_TOOLS,
      ];
}

export function registerTools(server: McpServer, caller: Caller): void {
  for (const register of toolsOf(caller)) {
    register(server, caller);
  }
}
