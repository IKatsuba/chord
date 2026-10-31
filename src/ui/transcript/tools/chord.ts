/**
 * chord's own tools as calls, kept out of the component: a verb in the
 * `Read(path)` style for each, and what was said or answered under `⎿`, read
 * from the request chord served rather than from the adapter's title
 * (`mcp__chord__spawn_task`) or the answer's JSON, which ctrl+o still shows.
 */
import { formatElapsed } from '../../../session/elapsed.ts';
import { settingsHeadline } from './settings_row.ts';
import { timeoutWords } from '../../../session/monitors.ts';
import type {
  ChordCall,
  ChordTool,
} from '../../../session/transcript/types.ts';
import { resourceLines } from './resource_lines.ts';
import { selectionLines } from './selection_lines.ts';
import { MESSAGE_LINES } from '../message.ts';
import type { Headline } from './tools.ts';

/** How many names a list of runtimes or models gives before `+N more`. */
const NAMED = 4;

function record(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null
    ? (value as Record<string, unknown>)
    : {};
}

function text(value: unknown): string | undefined {
  return typeof value === 'string' && value.trim() !== ''
    ? value.trim()
    : undefined;
}

/**
 * `List agents(codex)`, `→ to @main · queued`, `Agent(name) · codex`; a
 * message's recipient bare, as its colour is looked up by, and drawn `@main`.
 */
export function chordHeadline(call: ChordCall): Headline {
  const input = record(call.input);
  // The name chord answered with, whatever the agent called it by.
  const answered =
    text(record(call.answer).name) ??
    text(record(call.answer).to) ??
    text(record(call.answer).closed) ??
    text(record(call.answer).cleared);
  const named = (name: string, arg: string | undefined, note?: string) => ({
    name,
    ...(arg === undefined ? {} : { arg }),
    ...(note === undefined ? {} : { note }),
  });
  // The effort asked for until chord answers with the one it started on,
  // which a refusal leaves at the runtime's own.
  const effort =
    call.answer === undefined
      ? text(input.effort)
      : text(record(call.answer).effort);
  const runtime = [text(input.agent), text(input.model), effort].filter(
    (part) => part !== undefined,
  );
  const after = runtime.length === 0 ? undefined : ` · ${runtime.join(' · ')}`;
  // A team agent's runtime, model and mode are its file's, which chord
  // answered with; the mode only on a member's row, where the file set it.
  const opened = (mode: boolean) => {
    const parts = [
      text(record(call.answer).agent),
      text(record(call.answer).model),
      text(record(call.answer).effort),
      ...(mode ? [text(record(call.answer).mode)] : []),
    ].filter((part) => part !== undefined);

    return parts.length === 0 ? after : ` · ${parts.join(' · ')}`;
  };

  switch (call.tool) {
    case 'get_budgets':
      return named('Resources', undefined);
    case 'list_agents':
      return named('List agents', text(input.agent));
    case 'list_sessions':
      return named('List sessions', undefined);
    case 'spawn_task':
      return named(
        'Agent',
        text(input.name) ?? text(input.prompt)?.split('\n')[0],
        after,
      );
    case 'open_agent':
      return text(input.member) === undefined
        ? named(
            'Open',
            answered ?? text(input.name) ?? text(input.agent),
            after,
          )
        : named('Open', answered ?? text(input.member), opened(true));
    case 'run_team':
      return named('Team', answered ?? text(input.team), opened(false));
    case 'list_teams':
      return named('List teams', undefined);
    // The proposal or change is named once chord has served it.
    case 'propose_team':
      return named(
        'Team',
        text(input.name),
        call.answer === undefined
          ? undefined
          : record(call.answer).proposal === 'change'
            ? ' · change'
            : ' · proposal',
      );
    case 'settings':
      return settingsHeadline(call);
    case 'send_message':
      return {
        name: answered ?? text(input.to) ?? 'main',
        sent: true,
        ...(call.queued ? { note: ' · queued' } : {}),
      };
    case 'close_agent':
      return named('Close', answered ?? text(input.to) ?? text(input.id));
    case 'clear_agent':
      return named('Clear', answered ?? text(input.to));
    case 'monitor':
      return named('Monitor', text(input.description));
    case 'stop_monitor':
      return named(
        'Stop monitor',
        text(record(call.answer).description) ?? text(input.id),
      );
    case 'list_monitors':
      return named('List monitors', undefined);
  }
}

/**
 * What a call of chord's that the agent cut off before it reached chord
 * says after its body: that it did nothing, and that chord tells the agent
 * (docs/design/CHD-417.md).
 */
export function cutLine(tool: ChordTool): string {
  return tool === 'send_message'
    ? 'Not delivered: cut off before it reached chord. chord tells the agent at its next turn.'
    : 'Cut off before it reached chord, so it did nothing. chord tells the agent at its next turn.';
}

/**
 * What a `send_message` sent, as it was sent, so its markdown reads as a
 * received message's does, a leading indent's code block included; none
 * for another call or an empty text.
 */
export function sentText(
  call: Pick<ChordCall, 'tool' | 'input'>,
): string | undefined {
  const sent =
    call.tool === 'send_message' ? record(call.input).text : undefined;

  return typeof sent === 'string' && text(sent) !== undefined
    ? sent
    : undefined;
}

/** `a, b, c, d, +3 more`. */
function names(all: readonly string[]): string {
  const shown = all.slice(0, NAMED);
  const more = all.length - shown.length;

  return [...shown, ...(more > 0 ? [`+${more} more`] : [])].join(', ');
}

function plural(count: number, one: string, many: string): string {
  return `${count} ${count === 1 ? one : many}`;
}

/**
 * The lines under the call, before folding: chord's refusal, what was
 * sent, or what the answer comes to. None while it has no answer.
 */
export function chordLines(call: ChordCall, expanded = false): string[] {
  if (call.error !== undefined) {
    return [
      call.error,
      ...(call.tool === 'run_team'
        ? selectionLines(record(call.answer).receipt, expanded)
        : []),
    ];
  }

  const input = record(call.input);
  const answer = record(call.answer);
  const listing =
    call.tool === 'get_budgets' ||
    call.tool === 'list_agents' ||
    call.tool === 'list_sessions' ||
    call.tool === 'list_monitors' ||
    call.tool === 'list_teams';

  if (listing && call.answer === undefined) {
    return [];
  }

  switch (call.tool) {
    case 'get_budgets':
      return resourceLines(call.answer);
    case 'list_agents': {
      const agents = Array.isArray(answer.agents)
        ? answer.agents.map(record)
        : [];

      if (text(input.agent) !== undefined) {
        const [row] = agents;
        const models = Array.isArray(row?.models)
          ? row.models.map((model) => String(record(model).id ?? ''))
          : undefined;

        return models === undefined
          ? [text(row?.note) ?? 'No models']
          : [`${plural(models.length, 'model', 'models')} · ${names(models)}`];
      }

      const runtimes = agents.map((row) => String(row.name ?? ''));

      return [
        `${plural(runtimes.length, 'runtime', 'runtimes')} · ${names(
          runtimes,
        )}`,
      ];
    }
    case 'list_sessions': {
      const sessions = Array.isArray(answer.sessions)
        ? answer.sessions.map(record)
        : [];

      // By runtime, and its agents counted: an answer from 0.57.0 has a
      // `tab` too, which says nothing now (CHD-493).
      return [
        `${sessions.length} open · ${sessions
          .map((session) => {
            const agents = Array.isArray(session.agents)
              ? session.agents.length
              : 0;

            return `${String(session.runtime)}${session.you ? ' (you)' : ''}${
              agents === 0 ? '' : `, ${plural(agents, 'agent', 'agents')}`
            }`;
          })
          .join(', ')}`,
      ];
    }
    case 'spawn_task':
      return (text(input.prompt) ?? '').split('\n').slice(0, MESSAGE_LINES);
    // Whole, as ctrl+o shows what was handed over; the row folds it. One
    // the person opened with /new was handed nothing (Q187).
    case 'open_agent':
      return text(input.typed) === undefined
        ? (text(input.prompt) ?? '').split('\n')
        : [`opened with ${text(input.typed)}`];
    case 'run_team':
      return [
        ...(text(input.job) ?? '').split('\n'),
        ...selectionLines(answer.receipt, expanded),
      ];
    case 'list_teams': {
      const teams = Array.isArray(answer.teams)
        ? answer.teams.map((team) => String(record(team).name ?? ''))
        : [];

      return [`${plural(teams.length, 'team', 'teams')} · ${names(teams)}`];
    }
    // None for an empty text, so the row says the call's state instead.
    case 'send_message':
      return text(input.text)?.split('\n') ?? [];
    // Drawn as a table by its own component once served.
    case 'propose_team':
      return [];
    // Drawn in rows of its own once served, as a value is never folded.
    case 'settings':
      return [];
    case 'close_agent':
      return ['Closed'];
    // The id it keeps, and the messages to it that were dropped (CHD-476).
    case 'clear_agent':
      return [
        `Fresh session${text(answer.id) === undefined ? '' : ` · id ${text(answer.id)!}`}`,
        ...(text(answer.dropped) === undefined ? [] : [text(answer.dropped)!]),
      ];
    case 'monitor': {
      const timeout = answer.timeout_ms;

      return [
        `$ ${text(input.command) ?? ''}`,
        ...(typeof answer.id === 'string' && typeof timeout === 'number'
          ? [`${answer.id} · times out after ${timeoutWords(timeout)}`]
          : []),
      ];
    }
    case 'stop_monitor': {
      const { ran_ms: ran, events } = answer;

      return typeof ran === 'number' && typeof events === 'number'
        ? [
            `Stopped after ${formatElapsed(ran)} · ${
              events === 0 ? 'no events' : plural(events, 'event', 'events')
            }`,
          ]
        : [];
    }
    case 'list_monitors': {
      const monitors = Array.isArray(answer.monitors)
        ? answer.monitors.map(record)
        : [];

      return monitors.length === 0
        ? ['None running']
        : [
            `${monitors.length} running · ${names(
              monitors.map((monitor) => String(monitor.description ?? '')),
            )}`,
          ];
    }
  }
}
