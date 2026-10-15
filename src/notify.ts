import { beep } from 'ansi-escapes';
import type { ConversationEvent } from './session/conversation.ts';

/**
 * How chord tells the terminal it is waiting on the person: `auto` picks for
 * the terminal it runs in, `bell` is BEL, `osc9` and `osc777` the two desktop
 * notification escapes, `off` nothing.
 */
export const NOTIF_CHANNELS = [
  'auto',
  'bell',
  'osc9',
  'osc777',
  'off',
] as const;

export type NotifChannel = (typeof NOTIF_CHANNELS)[number];

/** What of the environment says which terminal chord is drawing in. */
export interface TerminalEnv {
  readonly termProgram?: string | undefined;
  readonly term?: string | undefined;
  /** Inside tmux, which swallows an OSC it does not know. */
  readonly tmux: boolean;
}

export function terminalEnv(
  get: (name: string) => string | undefined,
): TerminalEnv {
  return {
    termProgram: get('TERM_PROGRAM'),
    term: get('TERM'),
    tmux: (get('TMUX') ?? '') !== '',
  };
}

/** Why chord started waiting on the person. */
export type Wait =
  | { readonly kind: 'turn_ended' }
  | { readonly kind: 'permission'; readonly title?: string | undefined }
  /** A form to fill in or a link to open; `message` is the agent's. */
  | { readonly kind: 'input'; readonly message: string };

/**
 * What the events so far say about waiting: whether the session is live
 * rather than replaying its past, the turns Esc cancelled, the prompts queued
 * to run next, the turns a monitor's event started, and the permission
 * requests and forms still open.
 */
export interface Watch {
  readonly live: boolean;
  readonly cancelled: ReadonlySet<string>;
  readonly queued: ReadonlySet<string>;
  readonly events: ReadonlySet<string>;
  readonly asking: ReadonlySet<string>;
}

export const emptyWatch: Watch = {
  live: false,
  cancelled: new Set(),
  queued: new Set(),
  events: new Set(),
  asking: new Set(),
};

function adding(set: ReadonlySet<string>, item: string): Set<string> {
  return new Set(set).add(item);
}

function removing(set: ReadonlySet<string>, item: string): Set<string> {
  const left = new Set(set);

  left.delete(item);

  return left;
}

/**
 * Folds one event into the watch, and says whether it starts a wait. A turn
 * the person cancelled is not a wait they need telling of, nor is one a
 * queued prompt follows at once, nor the turns a resumed session replays,
 * nor one a monitor's event started, as a busy log would ring all day (its
 * end's turn does ring); a second permission request or form while one is
 * open is the same wait.
 */
export function watchWaits(
  watch: Watch,
  event: ConversationEvent,
): { watch: Watch; wait?: Wait } {
  switch (event.type) {
    case 'connected':
      return { watch: { ...watch, live: true } };
    case 'cleared':
      return { watch: emptyWatch };
    case 'cancel':
      return {
        watch: { ...watch, cancelled: adding(watch.cancelled, event.turnId) },
      };
    case 'queued':
      return {
        watch: { ...watch, queued: adding(watch.queued, event.turnId) },
      };
    case 'prompt': {
      const monitor = event.from?.monitor;

      return {
        watch: {
          ...watch,
          queued: removing(watch.queued, event.turnId),
          ...(monitor !== undefined && monitor.end === undefined
            ? { events: adding(watch.events, event.turnId) }
            : {}),
        },
      };
    }
    case 'queue_withdrawn':
      return { watch: { ...watch, queued: new Set() } };
    case 'permission_requested': {
      const wasAsking = watch.asking.size > 0;
      const next = {
        ...watch,
        asking: adding(watch.asking, event.permission.id),
      };

      return !watch.live || wasAsking
        ? { watch: next }
        : {
            watch: next,
            wait: { kind: 'permission', title: event.permission.title },
          };
    }
    case 'elicitation_requested': {
      const wasAsking = watch.asking.size > 0;
      const next = {
        ...watch,
        asking: adding(watch.asking, event.elicitation.id),
      };

      return !watch.live || wasAsking
        ? { watch: next }
        : {
            watch: next,
            wait: { kind: 'input', message: event.elicitation.message },
          };
    }
    case 'permission_settled':
    case 'elicitation_settled':
      return {
        watch: { ...watch, asking: removing(watch.asking, event.id) },
      };
    case 'result': {
      const next = {
        ...watch,
        cancelled: removing(watch.cancelled, event.turnId),
        events: removing(watch.events, event.turnId),
        asking: new Set<string>(),
      };
      const waits =
        watch.live &&
        !watch.cancelled.has(event.turnId) &&
        !watch.events.has(event.turnId) &&
        event.result.status !== 'cancelled' &&
        watch.queued.size === 0;

      return waits
        ? { watch: next, wait: { kind: 'turn_ended' } }
        : {
            watch: next,
          };
    }
    default:
      return { watch };
  }
}

/** Terminals that show OSC 9 as a desktop notification. */
function speaksOsc9({ termProgram, term }: TerminalEnv): boolean {
  return (
    ['iTerm.app', 'WezTerm', 'ghostty'].includes(termProgram ?? '') ||
    ['xterm-kitty', 'xterm-ghostty'].includes(term ?? '')
  );
}

/** Terminals that show OSC 777 but not OSC 9. */
function speaksOsc777({ term }: TerminalEnv): boolean {
  return term?.startsWith('foot') ?? false;
}

/**
 * The channel `auto` stands for. Inside tmux it is BEL: tmux drops an OSC it
 * does not know unless `allow-passthrough` is on, which it is not by default,
 * and the terminal outside it cannot be told from the environment.
 */
export function resolveChannel(
  channel: NotifChannel,
  env: TerminalEnv,
): Exclude<NotifChannel, 'auto'> {
  if (channel !== 'auto') {
    return channel;
  }

  if (env.tmux) {
    return 'bell';
  }

  return speaksOsc9(env) ? 'osc9' : speaksOsc777(env) ? 'osc777' : 'bell';
}

/**
 * Text safe inside an OSC: no control character can end it early or start
 * another sequence, and for OSC 777 no `;` can start another field.
 */
function clean(text: string, separator: boolean): string {
  // eslint-disable-next-line no-control-regex
  const flat = text.replace(/[\u0000-\u001f\u007f-\u009f]/g, ' ');

  return separator ? flat.replaceAll(';', ',') : flat;
}

/** What the notification says. */
export function waitMessage(wait: Wait, agent: string): string {
  if (wait.kind === 'turn_ended') {
    return `${agent} is waiting for your input`;
  }

  if (wait.kind === 'input') {
    return `${agent} asks for input: ${wait.message}`;
  }

  return wait.title === undefined
    ? `${agent} needs your permission`
    : `${agent} needs your permission: ${wait.title}`;
}

/**
 * tmux's passthrough: the sequence inside a DCS, each ESC doubled, so tmux
 * hands it to the terminal outside when `allow-passthrough` is on.
 */
function throughTmux(sequence: string): string {
  return `\x1bPtmux;${sequence.replaceAll('\x1b', '\x1b\x1b')}\x1b\\`;
}

/** The bytes that tell the terminal of `wait`, or none for `off`. */
export function notificationBytes(
  wait: Wait,
  channel: NotifChannel,
  env: TerminalEnv,
  agent: string,
): string | undefined {
  const resolved = resolveChannel(channel, env);

  if (resolved === 'off') {
    return undefined;
  }

  if (resolved === 'bell') {
    return beep;
  }

  const message = waitMessage(wait, agent);
  const sequence =
    resolved === 'osc9'
      ? `\x1b]9;${clean(message, false)}\x07`
      : `\x1b]777;notify;chord;${clean(message, true)}\x07`;

  return env.tmux ? throughTmux(sequence) : sequence;
}

/** How the window notifies: the channel settings chose, and the terminal. */
export interface Notifications {
  readonly channel: NotifChannel;
  readonly env: TerminalEnv;
}

/**
 * One event in, the watch after it and the bytes to write for it, if any:
 * `watchWaits` and `notificationBytes` together.
 */
export function notify(
  watch: Watch,
  event: ConversationEvent,
  { channel, env }: Notifications,
  agent: string,
): { watch: Watch; bytes?: string } {
  const seen = watchWaits(watch, event);

  if (seen.wait === undefined) {
    return { watch: seen.watch };
  }

  const bytes = notificationBytes(seen.wait, channel, env, agent);

  return bytes === undefined
    ? { watch: seen.watch }
    : {
        watch: seen.watch,
        bytes,
      };
}
