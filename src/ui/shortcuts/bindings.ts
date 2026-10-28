/**
 * Which key does what: every action chord lets a person rebind, its default
 * keys, and the keybindings file that changes them. The file has Claude
 * Code's shape (`{ "bindings": [{ "context", "bindings": { key: action } }] }`)
 * and its names for the actions it shares, so a block copied from
 * `~/.claude/keybindings.json` means the same here. Keys are matched against
 * chord's key presses (`press.ts`), so nothing here reads a terminal byte.
 */
import ru from 'convert-layout/ru.js';
import type { KeyPress } from './state.ts';

/**
 * Where an action applies, by Claude Code's names for its contexts, and
 * chord's `Agents` for the list of a session's agents, `Selection` for a
 * selection shown and `CodeBlock` for a code block picked, which it has
 * not.
 */
export const CONTEXTS = [
  'Global',
  'Chat',
  'Autocomplete',
  'Confirmation',
  'Help',
  'HistorySearch',
  'Select',
  'Scroll',
  'Agents',
  'Selection',
  'CodeBlock',
] as const;

export type Context = (typeof CONTEXTS)[number];

interface ActionSpec {
  readonly context: Context;
  /** Its keys with no file, as the file spells them. */
  readonly keys: readonly string[];
}

/**
 * Every action a key can be bound to, by Claude Code's name where Claude Code
 * has the action, and chord's for those it binds no name to: `help:toggle`,
 * `?` on an empty prompt, `select:toggleScope`, `/resume`'s ctrl+a
 * between this directory and every one, `session:attention`, to what
 * waits on the person, and `agents:close` in the list of a session's
 * agents, which Claude Code does not have. The defaults
 * are chord's keys as they were before there was a file, which is why some
 * differ from Claude Code's.
 */
export const ACTIONS = {
  'app:toggleTranscript': { context: 'Global', keys: ['ctrl+o'] },
  'history:search': { context: 'Global', keys: ['ctrl+r'] },
  // A leader and a letter, as tmux's prefix and Emacs's ctrl+x: ctrl+x is
  // no key of the prompt's textarea, of chord's or of tmux's own prefix.
  'session:attention': { context: 'Global', keys: ['ctrl+x a'] },
  'chat:submit': { context: 'Chat', keys: ['enter'] },
  'chat:newline': {
    context: 'Chat',
    keys: ['shift+enter', 'alt+enter', 'ctrl+j', 'ctrl+enter'],
  },
  // The oldest queued message into the running turn, the draft left as it
  // is (CHD-535).
  'chat:steer': { context: 'Chat', keys: ['tab'] },
  'chat:cancel': { context: 'Chat', keys: ['escape'] },
  'chat:cycleMode': { context: 'Chat', keys: ['shift+tab'] },
  'chat:externalEditor': { context: 'Chat', keys: ['ctrl+g'] },
  'chat:imagePaste': { context: 'Chat', keys: ['ctrl+v'] },
  'history:previous': { context: 'Chat', keys: ['up'] },
  'history:next': { context: 'Chat', keys: ['down'] },
  'help:toggle': { context: 'Chat', keys: ['?'] },
  'autocomplete:accept': { context: 'Autocomplete', keys: ['tab'] },
  'autocomplete:dismiss': { context: 'Autocomplete', keys: ['escape'] },
  'autocomplete:previous': { context: 'Autocomplete', keys: ['up'] },
  'autocomplete:next': { context: 'Autocomplete', keys: ['down'] },
  'confirm:no': { context: 'Confirmation', keys: ['escape'] },
  'help:dismiss': { context: 'Help', keys: ['escape'] },
  'historySearch:next': { context: 'HistorySearch', keys: ['ctrl+r'] },
  'historySearch:accept': { context: 'HistorySearch', keys: ['tab', 'enter'] },
  'historySearch:cancel': { context: 'HistorySearch', keys: ['escape'] },
  // The list of the session's agents under the prompt, which Claude Code
  // does not have: x closes the child picked in it.
  'agents:close': { context: 'Agents', keys: ['x'] },
  // A code block picked through the leader, which Claude Code does not
  // have: copy it, or put its command in the prompt (CHD-394).
  'codeBlock:pick': { context: 'Global', keys: ['ctrl+x b'] },
  'codeBlock:copy': { context: 'CodeBlock', keys: ['c'] },
  'codeBlock:prompt': { context: 'CodeBlock', keys: ['r'] },
  'codeBlock:previous': { context: 'CodeBlock', keys: ['up'] },
  'codeBlock:next': { context: 'CodeBlock', keys: ['down'] },
  'codeBlock:cancel': { context: 'CodeBlock', keys: ['escape'] },
  'select:cancel': { context: 'Select', keys: ['escape'] },
  'select:toggleScope': { context: 'Select', keys: ['ctrl+a'] },
  // Terminal.app keeps pgup, pgdn, home and end for its own scrollback and
  // passes them on only with shift held.
  'scroll:pageUp': { context: 'Scroll', keys: ['pageup', 'shift+pageup'] },
  'scroll:pageDown': {
    context: 'Scroll',
    keys: ['pagedown', 'shift+pagedown'],
  },
  'scroll:lineUp': { context: 'Scroll', keys: ['shift+up'] },
  'scroll:lineDown': { context: 'Scroll', keys: ['shift+down'] },
  'scroll:top': { context: 'Scroll', keys: ['home', 'shift+home'] },
  'scroll:bottom': { context: 'Scroll', keys: ['end', 'shift+end'] },
  // Live only while a selection is shown, and heard before every other
  // context then. Without kitty's protocol it arrives as ctrl+c, which
  // copies a selection shown anyway (CHD-172).
  'selection:copy': { context: 'Selection', keys: ['ctrl+shift+c'] },
} as const satisfies Record<string, ActionSpec>;

export type Action = keyof typeof ACTIONS;

/** One key press: a key and the modifiers held with it. */
export interface Keystroke {
  /** A character, lower case for a letter, or a named key such as `enter`. */
  readonly key: string;
  readonly ctrl: boolean;
  /** alt, option and meta: the one key a terminal reports for all three. */
  readonly alt: boolean;
  readonly shift: boolean;
  /** cmd, super or win, which only a terminal speaking kitty's protocol sends. */
  readonly cmd: boolean;
}

/** Keys pressed one after another; a chord is more than one. */
export type Sequence = readonly Keystroke[];

/** A key sequence bound to an action in a context. */
export interface Binding {
  readonly context: Context;
  readonly keys: Sequence;
  readonly action: Action;
}

export interface Keymap {
  readonly bindings: readonly Binding[];
}

/** How long the next key of a chord is waited for, as in Claude Code. */
export const CHORD_WAIT_MS = 3000;

/** The named keys, by every name the file may give them. */
const NAMED: Record<string, string> = {
  escape: 'escape',
  esc: 'escape',
  enter: 'enter',
  return: 'enter',
  tab: 'tab',
  space: 'space',
  backspace: 'backspace',
  delete: 'delete',
  up: 'up',
  down: 'down',
  left: 'left',
  right: 'right',
  pageup: 'pageup',
  pagedown: 'pagedown',
  home: 'home',
  end: 'end',
};

const MODIFIERS: Record<string, 'ctrl' | 'alt' | 'shift' | 'cmd'> = {
  ctrl: 'ctrl',
  control: 'ctrl',
  alt: 'alt',
  opt: 'alt',
  option: 'alt',
  meta: 'alt',
  shift: 'shift',
  cmd: 'cmd',
  command: 'cmd',
  super: 'cmd',
  win: 'cmd',
};

/**
 * Keys no binding may take, as in Claude Code: ctrl+c and ctrl+d stop and
 * quit, and the rest reach a program as Enter, Esc, Tab and Backspace.
 */
const RESERVED = ['ctrl+c', 'ctrl+d', 'ctrl+m', 'ctrl+[', 'ctrl+i', 'ctrl+h'];

/** One keystroke as the file writes it, `ctrl+shift+p`, or why it is none. */
export function parseKeystroke(
  text: string,
): { keystroke: Keystroke } | { problem: string } {
  const lower = text.toLowerCase();
  // A trailing `+` is the plus key itself: `ctrl++`.
  const parts = lower.endsWith('++')
    ? [...lower.slice(0, -2).split('+'), '+']
    : lower.split('+');
  const name = parts.pop() ?? '';
  const held = { ctrl: false, alt: false, shift: false, cmd: false };

  for (const part of parts) {
    const modifier = MODIFIERS[part];

    if (modifier === undefined) {
      return { problem: `"${part}" is not a modifier` };
    }

    held[modifier] = true;
  }

  if (name === 'wheelup' || name === 'wheeldown') {
    return {
      problem: 'the wheel always scrolls the transcript and cannot be bound',
    };
  }

  const key = NAMED[name] ?? (name.length === 1 ? name : undefined);

  if (key === undefined) {
    return { problem: `"${name}" is not a key` };
  }

  return { keystroke: { key, ...held } };
}

/** A key sequence as the file writes it, `ctrl+x ctrl+e`, or why it is none. */
export function parseSequence(
  text: string,
): { keys: Sequence } | { problem: string } {
  const strokes = text.trim().split(/\s+/);
  const keys: Keystroke[] = [];

  for (const stroke of strokes) {
    if (stroke === '') {
      return { problem: 'no key' };
    }

    const parsed = parseKeystroke(stroke);

    if ('problem' in parsed) {
      return parsed;
    }

    keys.push(parsed.keystroke);
  }

  return { keys };
}

/** A keystroke as a hint names it: `ctrl+g`, `shift+tab`, `esc`. */
function hintName({ key, ctrl, alt, shift, cmd }: Keystroke): string {
  return [
    ...(ctrl ? ['ctrl'] : []),
    ...(alt ? ['alt'] : []),
    ...(shift ? ['shift'] : []),
    ...(cmd ? ['cmd'] : []),
    key === 'escape' ? 'esc' : key,
  ].join('+');
}

/** The keys as the panel names them, in Claude Code's spelling. */
const PANEL_KEYS: Record<string, string> = {
  escape: 'esc',
  up: '↑',
  down: '↓',
  left: '←',
  right: '→',
  pageup: 'pgup',
  pagedown: 'pgdn',
};

/** A keystroke as the shortcuts panel names it: `ctrl + g`, `shift + ↑`. */
function panelName({ key, ctrl, alt, shift, cmd }: Keystroke): string {
  return [
    ...(ctrl ? ['ctrl'] : []),
    ...(alt ? ['alt'] : []),
    ...(shift ? ['shift'] : []),
    ...(cmd ? ['cmd'] : []),
    PANEL_KEYS[key] ?? key,
  ].join(' + ');
}

/** A sequence as a hint or the status line names it: `ctrl+x ctrl+e`. */
export function sequenceHint(keys: Sequence): string {
  return keys.map(hintName).join(' ');
}

/** A sequence as the shortcuts panel names it: `ctrl + x ctrl + e`. */
export function sequencePanel(keys: Sequence): string {
  return keys.map(panelName).join(' ');
}

function same(a: Keystroke, b: Keystroke): boolean {
  return (
    a.key === b.key &&
    a.ctrl === b.ctrl &&
    a.alt === b.alt &&
    a.shift === b.shift &&
    a.cmd === b.cmd
  );
}

function startsWith(keys: Sequence, start: Sequence): boolean {
  return (
    start.length <= keys.length &&
    start.every((stroke, index) => same(stroke, keys[index]!))
  );
}

function equal(a: Sequence, b: Sequence): boolean {
  return a.length === b.length && startsWith(a, b);
}

function sequenceOf(text: string): Sequence {
  const parsed = parseSequence(text);

  if ('problem' in parsed) {
    throw new Error(`"${text}": ${parsed.problem}`);
  }

  return parsed.keys;
}

/** The keys chord binds with no file. */
export const DEFAULT_KEYMAP: Keymap = {
  bindings: Object.entries(ACTIONS).flatMap(([action, spec]) =>
    spec.keys.map((key): Binding => ({
      context: spec.context,
      keys: sequenceOf(key),
      action: action as Action,
    })),
  ),
};

/**
 * A key press as a keystroke, or none for one no binding can name.
 * A character that is not a letter carries its shift in itself, as `?` does,
 * whether or not the terminal also reports shift.
 */
export function keystrokeOf(
  input: string,
  key: KeyPress,
): Keystroke | undefined {
  const held = {
    ctrl: key.ctrl,
    alt: key.meta === true,
    shift: key.shift === true,
    cmd: key.super === true,
  };
  const named = key.upArrow
    ? 'up'
    : key.downArrow
      ? 'down'
      : key.leftArrow
        ? 'left'
        : key.rightArrow
          ? 'right'
          : key.pageUp
            ? 'pageup'
            : key.pageDown
              ? 'pagedown'
              : key.home
                ? 'home'
                : key.end
                  ? 'end'
                  : key.return
                    ? 'enter'
                    : key.escape
                      ? 'escape'
                      : key.tab
                        ? 'tab'
                        : key.backspace
                          ? 'backspace'
                          : key.delete
                            ? 'delete'
                            : undefined;

  // ctrl+j reaches a terminal program as a line feed, which arrives as the
  // text `\n` with no ctrl.
  if (lineFeed(input, key)) {
    return { key: 'j', ...held, ctrl: true };
  }

  if (named !== undefined) {
    // Esc read from a lone escape byte may come marked as meta too.
    return { key: named, ...held, alt: named === 'escape' ? false : held.alt };
  }

  if (input === ' ') {
    return { key: 'space', ...held };
  }

  if ([...input].length !== 1) {
    return undefined;
  }

  const lower = input.toLowerCase();

  return lower === input.toUpperCase()
    ? { key: input, ...held, shift: false }
    : { key: lower, ...held, shift: held.shift || input !== lower };
}

/**
 * Where Apple's "Russian" layout puts a character somewhere other than
 * "Russian – PC" does, which is the layout convert-layout's table follows.
 * Apple's keeps `/` and `?` on the US key, so of the characters a US layout
 * cannot type only ё moves: onto the backslash key, not the backquote.
 */
const APPLE_RUSSIAN: Record<string, string> = { ё: '\\', Ё: '|' };

/**
 * The US characters a press would have typed in the same place, had the
 * layout been US rather than Russian; none for a character a US layout types
 * itself. Those are left alone because a press cannot say which layout it
 * came from: `,` is where `?` is on "Russian – PC", and translating it would
 * open the panel for a US layout's first comma. Russian – PC's first, then
 * Apple's where it differs.
 */
export function layoutKeys(input: string): string[] {
  if ([...input].length !== 1 || input.codePointAt(0)! < 0x80) {
    return [];
  }

  const keys = [ru.toEn(input), APPLE_RUSSIAN[input]];

  return keys.filter(
    (key, index): key is string =>
      key !== undefined && key !== input && keys.indexOf(key) === index,
  );
}

/** A key that puts its character in the box: no ctrl, alt or cmd held. */
export function types(stroke: Keystroke): boolean {
  return (
    (stroke.key.length === 1 || stroke.key === 'space') &&
    !stroke.ctrl &&
    !stroke.alt &&
    !stroke.cmd
  );
}

/** Whether the press is the line feed byte, which is what ctrl+j sends. */
export function lineFeed(input: string, key: KeyPress): boolean {
  return input === '\n' && !key.ctrl && !key.return;
}

/** Whether `pressed` is one of `action`'s sequences. */
export function bound(
  keymap: Keymap,
  action: Action,
  pressed: Sequence | undefined,
): boolean {
  return (
    pressed !== undefined &&
    keymap.bindings.some(
      (binding) => binding.action === action && equal(binding.keys, pressed),
    )
  );
}

/** Whether `pressed` is the start of one of `chords`, to wait for the rest. */
export function startsChord(
  chords: readonly Sequence[],
  pressed: Sequence,
): boolean {
  return chords.some(
    (keys) => keys.length > pressed.length && startsWith(keys, pressed),
  );
}

/** Every sequence `action` is bound to, in the order they were bound. */
export function keysOf(keymap: Keymap, action: Action): Sequence[] {
  return keymap.bindings
    .filter((binding) => binding.action === action)
    .map((binding) => binding.keys);
}

/** Whether `action` has exactly its default keys. */
export function isDefault(keymap: Keymap, action: Action): boolean {
  const now = keysOf(keymap, action);
  const before = keysOf(DEFAULT_KEYMAP, action);

  return (
    now.length === before.length &&
    now.every((keys, index) => equal(keys, before[index]!))
  );
}

/** `action`'s first key as a hint names it; none when it has no key. */
export function hintKey(keymap: Keymap, action: Action): string | undefined {
  const [first] = keysOf(keymap, action);

  return first === undefined ? undefined : sequenceHint(first);
}

/**
 * The contexts heard wherever another is, and before it: the window's keys
 * and the transcript's scrolling, which even a form leaves alone.
 */
export const ALWAYS: readonly Context[] = ['Global', 'Scroll'];

/**
 * Whether a binding in one context can be pressed while one in another is
 * and neither gives way. A context that only opens over the prompt, such as
 * Autocomplete, takes its keys first by design, as in Claude Code.
 */
function overlap(a: Context, b: Context): boolean {
  return a === b || ALWAYS.includes(a) || ALWAYS.includes(b);
}

/**
 * The actions that went with tabs in 0.58.0 (CHD-493): a file that still
 * binds one is told so, not that it names nothing.
 */
const REMOVED = [
  'session:new',
  'session:next',
  'session:previous',
  ...[1, 2, 3, 4, 5, 6, 7, 8, 9].map((n) => `session:goto${n}`),
  'session:list',
  'session:close',
];

function isAction(name: string): name is Action {
  return Object.hasOwn(ACTIONS, name);
}

function isContext(name: string): name is Context {
  return (CONTEXTS as readonly string[]).includes(name);
}

/**
 * Reads a keybindings file's text over the defaults. Each binding in it
 * replaces whatever its key did in its context, as in Claude Code, and
 * `null` takes the key away. A binding that is wrong — an unknown context,
 * action or key, a reserved key, an action outside its context, or a key
 * that would mean two actions at once — is a problem and is left out, and
 * the rest of the file still counts; text that is not such a file counts for
 * nothing.
 */
export function readKeybindings(text: string): {
  keymap: Keymap;
  problems: string[];
} {
  let input: unknown;

  try {
    input = JSON.parse(text);
  } catch (error) {
    return {
      keymap: DEFAULT_KEYMAP,
      problems: [
        `not valid JSON (${
          error instanceof Error ? error.message : String(error)
        }); the file is ignored`,
      ],
    };
  }

  const blocks =
    typeof input === 'object' && input !== null && !Array.isArray(input)
      ? (input as Record<string, unknown>).bindings
      : undefined;

  if (!Array.isArray(blocks)) {
    return {
      keymap: DEFAULT_KEYMAP,
      problems: ['has no "bindings" list; the file is ignored'],
    };
  }

  const problems: string[] = [];
  let bindings: Binding[] = [...DEFAULT_KEYMAP.bindings];
  const fromFile = new Set<Binding>();

  for (const block of blocks) {
    const { context, bindings: map } =
      typeof block === 'object' && block !== null
        ? (block as Record<string, unknown>)
        : {};

    if (typeof context !== 'string' || !isContext(context)) {
      problems.push(
        typeof context === 'string'
          ? `unknown context "${context}", ignored`
          : 'a block with no "context", ignored',
      );

      continue;
    }

    if (typeof map !== 'object' || map === null || Array.isArray(map)) {
      problems.push(`${context}: "bindings" is not an object, ignored`);

      continue;
    }

    for (const [written, action] of Object.entries(
      map as Record<string, unknown>,
    )) {
      const parsed = parseSequence(written);

      if ('problem' in parsed) {
        problems.push(`"${written}": ${parsed.problem}, ignored`);

        continue;
      }

      const { keys } = parsed;
      const name = sequenceHint(keys);

      if (keys.length === 1 && RESERVED.includes(name)) {
        problems.push(`${name} cannot be rebound, ignored`);

        continue;
      }

      if (action !== null && typeof action !== 'string') {
        problems.push(`${name}: the action is not a name or null, ignored`);

        continue;
      }

      if (action !== null && REMOVED.includes(action)) {
        problems.push(
          `${action} went with tabs: chord runs one session, ignored`,
        );

        continue;
      }

      if (action !== null && !isAction(action)) {
        problems.push(`unknown action "${action}", ignored`);

        continue;
      }

      if (action !== null && ACTIONS[action].context !== context) {
        problems.push(
          `${action} belongs in ${
            ACTIONS[action].context
          }, not ${context}; ignored`,
        );

        continue;
      }

      // Two keys the file spells apart that are one key, or one key in two
      // blocks: the first holds.
      const twice = bindings.find(
        (binding) =>
          fromFile.has(binding) &&
          binding.context === context &&
          equal(binding.keys, keys) &&
          binding.action !== action,
      );

      if (twice !== undefined) {
        problems.push(
          `${name} is bound twice in ${context}; ${twice.action} kept`,
        );

        continue;
      }

      // A key bound again to the action it has keeps its place.
      if (
        bindings.some(
          (binding) =>
            binding.context === context &&
            equal(binding.keys, keys) &&
            binding.action === action,
        )
      ) {
        continue;
      }

      const kept = bindings.filter(
        (binding) => binding.context !== context || !equal(binding.keys, keys),
      );

      if (action === null) {
        bindings = kept;

        continue;
      }

      // A key given a new action in its own context keeps the place the old
      // one had, beside the other contexts' keys, as the defaults have it.
      const replaces = kept.length < bindings.length;
      const clash =
        !replaces &&
        kept.find(
          (binding) =>
            overlap(binding.context, context) &&
            binding.action !== action &&
            (startsWith(binding.keys, keys) || startsWith(keys, binding.keys)),
        );

      if (clash) {
        problems.push(
          equal(clash.keys, keys)
            ? `${name} already bound to ${clash.action}, not to ${action}`
            : `${name} overlaps ${sequenceHint(
                clash.keys,
              )} (${clash.action}), not bound to ${action}`,
        );

        continue;
      }

      const binding: Binding = { context, keys, action };

      fromFile.add(binding);

      bindings = [...kept, binding];
    }
  }

  return { keymap: { bindings }, problems };
}

/**
 * What the status line says of a file's problems: how many, then the first.
 * The count leads so a narrow window cuts only detail; the transcript and
 * stderr list them all.
 */
export function keybindingsNotice(
  file: string,
  problems: readonly string[],
): string | undefined {
  const [first] = problems;

  if (first === undefined) {
    return undefined;
  }

  const count = problems.length;

  return count === 1
    ? `${file}: ${first}`
    : `${file}: ${count} problems · ${first}`;
}
