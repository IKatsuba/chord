/**
 * The pickers' choices — `/model`'s models, `/resume`'s earlier sessions
 * and saved windows, `ctrl+x w`'s open ones and `/config`'s options and
 * their values —
 * where a picker's window onto them sits, and what each key does to it, kept
 * out of the component. The list is drawn by hand, as the slash command list
 * is: ink-select-input scrolls by rotating, so it can neither keep a long
 * list in order nor say where it has scrolled to.
 */
import stringWidth from 'string-width';
import { type AgentOption, valueName } from '../../session/config.ts';
import type { AgentModels } from '../../session/models.ts';
import {
  type ResumeEntry,
  windowDirectory,
  windowSummary,
} from '../../session/windows.ts';
import type { TabWait } from '../../session/tabs.ts';
import { homePath } from '../../settings.ts';
import { visibleRange } from '../prompt/commands.ts';
import { GLYPHS } from '../app/strip.ts';
import { formatElapsed } from '../../session/elapsed.ts';
import { cutPath } from './mcp.ts';
import type { KeyPress } from '../shortcuts/state.ts';
import type { Choice } from '../dialogs/permission.ts';

/** After the model in use, and the value an option is set to. */
export const CURRENT_MARK = '✔';

/**
 * One choice on a picker; `current` is the one the list opens on: the one in
 * use, or the one come back from, when there is one.
 */
export interface PickerChoice extends Choice {
  readonly current?: boolean;
}

/** One model on the list; `current` is the one the agent says it uses. */
export interface ModelChoice extends PickerChoice {
  readonly current: boolean;
}

/** The agent's models in its order, the one in use marked. */
export function modelChoices(models: AgentModels | undefined): ModelChoice[] {
  return (models?.available ?? []).map((model) => ({
    key: model.id,
    // The mark goes after the name, where Claude Code puts it.
    label: `${model.name}${
      model.id === models?.current ? ` ${CURRENT_MARK}` : ''
    }`,
    value: model.id,
    current: model.id === models?.current,
  }));
}

/**
 * `/config`'s first list: each option by the agent's name for it, padded so
 * the values line up, then the value it is set to. The value is its id.
 */
export function optionChoices(
  options: readonly AgentOption[],
  from?: string,
): PickerChoice[] {
  const width = Math.max(0, ...options.map(({ name }) => name.length));

  return options.map((option) => ({
    key: option.id,
    label: `${option.name.padEnd(width)}  ${valueName(option, option.current)}`,
    value: option.id,
    ...(option.id === from ? { current: true } : {}),
  }));
}

/** `/config`'s second list: one option's values, the one it is set to marked. */
export function valueChoices(option: AgentOption): PickerChoice[] {
  return option.values.map(({ value, name }) => ({
    key: value,
    label: `${name}${value === option.current ? ` ${CURRENT_MARK}` : ''}`,
    value,
    current: value === option.current,
  }));
}

/**
 * The value to ask the agent for when `value` is picked for `option`: none
 * for the one it is set to already, as there is nothing to change.
 */
export function valueToAsk(
  option: AgentOption,
  value: string,
): string | undefined {
  return value === option.current ? undefined : value;
}

/** The most columns `/resume`'s directory column takes; longer ones lose their start. */
export const DIRECTORY_WIDTH = 30;

/**
 * `/resume`'s rows, newest first: when each session was last used, or each
 * window quit, padded so the text lines up, then a session's first prompt or
 * a window's summary, `▣ 3 sessions · claude, codex, claude`, and its front
 * tab's first prompt. With `home`, as the list of every directory draws them,
 * each row names its directory between the two, from `~` and cut from the
 * start to `DIRECTORY_WIDTH`, where the name that tells two apart is, and at
 * a `/` so the segments left are whole; a window's is its front tab's, with
 * ` +1` for each other directory its tabs work in. The row is cut at the
 * picker's edge as it is drawn. A session open in a tab of the window says
 * which, `open in 2`, after when it was used, as picking it goes there rather
 * than load it twice; a window says how many of its sessions are open in its
 * summary, as they may be in several tabs. The value is the entry's place in
 * `entries`.
 */
export function sessionChoices(
  entries: readonly ResumeEntry[],
  now: number,
  directories?: { readonly home: string | undefined },
  /** The tab each open session is in, by its id. */
  open: ReadonlyMap<string, number> = new Map(),
): PickerChoice[] {
  const when = entries.map((entry) =>
    lastUsed(
      entry.kind === 'window'
        ? entry.window.lastUsedAt
        : entry.session.lastUsedAt,
      now,
    ),
  );
  const width = Math.max(0, ...when.map((text) => text.length));
  const tabs = entries.map((entry) => {
    const tab =
      entry.kind === 'session'
        ? open.get(entry.session.resume.sessionId)
        : undefined;

    return tab === undefined ? '' : `open in ${tab}`;
  });

  const tabsWidth = Math.max(0, ...tabs.map((text) => text.length));
  const shown = (cwd: string, room: number) =>
    cutPath(homePath(cwd, directories?.home), room);
  const where =
    directories === undefined
      ? undefined
      : entries.map((entry) =>
          entry.kind === 'window'
            ? windowDirectory(entry.window, shown, DIRECTORY_WIDTH)
            : shown(entry.session.resume.cwd, DIRECTORY_WIDTH),
        );
  const whereWidth = Math.max(
    0,
    ...(where ?? []).map((text) => stringWidth(text)),
  );
  const textOf = (entry: ResumeEntry) => {
    if (entry.kind === 'session') {
      return entry.session.prompt;
    }

    const { window } = entry;
    const summary = windowSummary(
      window,
      window.tabs.filter(({ sessionId }) => open.has(sessionId)).length,
    );

    return window.prompt === '' ? summary : `${summary} · ${window.prompt}`;
  };

  return entries.map((entry, index) => ({
    key:
      entry.kind === 'window'
        ? entry.window.id
        : entry.session.resume.sessionId,
    label: [
      when[index]!.padEnd(width),
      ...(tabsWidth === 0 ? [] : [tabs[index]!.padEnd(tabsWidth)]),
      ...(where === undefined
        ? []
        : [
            where[index]! + ' '.repeat(whereWidth - stringWidth(where[index]!)),
          ]),
      textOf(entry),
    ].join('  '),
    value: String(index),
  }));
}

/** One open session as the sessions picker lists it. */
export interface TabRow {
  readonly agent: string;
  readonly wait: TabWait;
  /** The session in front, which the list calls `here`. */
  readonly front: boolean;
  /** Its first prompt, on one line; none before one is sent. */
  readonly prompt: string | undefined;
  /** How many long-lived agents it has open; none or 0 for none. */
  readonly agents?: number;
  /** The child whose wait `wait` is, named before its words. */
  readonly waiter?: string;
}

/** `41s`, `2m`, `1h`: the first unit of an elapsed time, as a row has room for. */
function briefly(ms: number): string {
  return formatElapsed(ms).split(' ')[0]!;
}

/**
 * Where a session stands, as the sessions picker words it: `here` for the one
 * in front, then what its tab's glyph says, in the same order, with how long:
 * `● permission 41s`, `● input 41s`, `✗ failed`, `✓ replied 2m ago`,
 * `working 12s`, and `idle` for the rest.
 */
export function tabState(tab: TabRow, now: number): string {
  const { wait } = tab;

  if (tab.front) {
    return 'here';
  }

  if (wait.asking) {
    return `${GLYPHS.asking} ${
      tab.waiter === undefined ? '' : `${tab.waiter}: `
    }${wait.asking.on.kind === 'input' ? 'input' : 'permission'} ${briefly(
      now - wait.asking.since,
    )}`;
  }

  if (wait.unseen?.kind === 'failed') {
    return `${GLYPHS.failed} failed`;
  }

  if (wait.unseen) {
    return `${GLYPHS.replied} replied ${briefly(now - wait.unseen.since)} ago`;
  }

  return wait.working === undefined
    ? 'idle'
    : `working ${briefly(now - wait.working)}`;
}

/**
 * `ctrl+x w`'s rows, in tab order: each session's agent and where it stands,
 * padded so the columns line up, then its first prompt. The row the list opens
 * on is `start`'s. The value is the tab's number.
 */
export function tabChoices(
  tabs: readonly TabRow[],
  now: number,
  start: number | undefined,
): PickerChoice[] {
  const states = tabs.map((tab) => tabState(tab, now));
  // `claude · 2 agents` for a session with long-lived agents of its own.
  const agents = tabs.map(({ agent, agents = 0 }) =>
    agents === 0
      ? agent
      : `${agent} · ${agents} ${agents === 1 ? 'agent' : 'agents'}`,
  );
  const agentWidth = Math.max(0, ...agents.map((agent) => stringWidth(agent)));
  const stateWidth = Math.max(0, ...states.map((text) => stringWidth(text)));
  const pad = (text: string, width: number) =>
    text + ' '.repeat(width - stringWidth(text));

  return tabs.map((tab, index) => ({
    key: String(index + 1),
    label: [
      pad(agents[index]!, agentWidth),
      pad(states[index]!, stateWidth),
      tab.prompt ?? '',
    ]
      .join('  ')
      .trimEnd(),
    value: String(index + 1),
    ...(index + 1 === start ? { current: true } : {}),
  }));
}

const RELATIVE = new Intl.RelativeTimeFormat('en', { numeric: 'auto' });

const UNITS: readonly [Intl.RelativeTimeFormatUnit, number][] = [
  ['year', 365 * 24 * 60 * 60],
  ['month', 30 * 24 * 60 * 60],
  ['week', 7 * 24 * 60 * 60],
  ['day', 24 * 60 * 60],
  ['hour', 60 * 60],
  ['minute', 60],
];

/**
 * When a session was last used, from `now`, epoch milliseconds: `just now`
 * inside a minute, then `5 minutes ago`, `yesterday`, `3 weeks ago`. A
 * timestamp that does not read as one is shown as it is.
 */
export function lastUsed(at: string, now: number): string {
  const time = Date.parse(at);

  if (Number.isNaN(time)) {
    return at;
  }

  const seconds = Math.max(0, Math.floor((now - time) / 1000));
  const unit = UNITS.find(([, size]) => seconds >= size);

  return unit
    ? RELATIVE.format(-Math.floor(seconds / unit[1]), unit[0])
    : 'just now';
}

/** Where the highlight starts: on the choice in use, or the first. */
export function initialChoice(choices: readonly PickerChoice[]): number {
  return Math.max(
    0,
    choices.findIndex((choice) => choice.current === true),
  );
}

/**
 * The highlighted choice and the first one shown. The window moves only when
 * the highlight leaves it, so the rows hold still while it walks among them.
 */
export interface PickerView {
  readonly highlighted: number;
  readonly top: number;
}

/** The view a picker opens on: the choice in use highlighted and in sight. */
export function openView(
  choices: readonly PickerChoice[],
  rows: number,
): PickerView {
  const highlighted = initialChoice(choices);

  return {
    highlighted,
    top: visibleRange(choices.length, highlighted, rows).start,
  };
}

/** The parts of a press the picker reads. */
export interface PickerKey {
  readonly upArrow: boolean;
  readonly downArrow: boolean;
  readonly return: boolean;
  readonly shift: boolean;
}

/** What a key does to the picker: moves its highlight, or picks a choice. */
export type PickerStep =
  | { readonly type: 'move'; readonly view: PickerView }
  | { readonly type: 'pick'; readonly index: number };

/**
 * The picker's answer to a key, as the permission prompt's ink-select-input
 * answers it, so the two lists take the same keys: ↑/↓ and j/k move, a digit
 * picks the choice with that number, Enter picks the highlighted one. Unlike
 * that list, the highlight stops at either end rather than going round, as
 * the order would otherwise seem to start over. j and k are read whatever is
 * held with them and Enter likewise, as ink-select-input reads them;
 * shift+↑/↓ are the window's, which scrolls the transcript on them.
 */
export function pickerKey(
  view: PickerView,
  count: number,
  rows: number,
  input: string,
  key: PickerKey,
): PickerStep | undefined {
  if (count === 0) {
    return undefined;
  }

  if (key.return) {
    return { type: 'pick', index: view.highlighted };
  }

  if (/^[1-9]$/.test(input)) {
    const index = Number(input) - 1;

    return index < count ? { type: 'pick', index } : undefined;
  }

  const step =
    (key.upArrow && !key.shift) || input === 'k'
      ? -1
      : (key.downArrow && !key.shift) || input === 'j'
        ? 1
        : 0;
  const highlighted = Math.min(Math.max(view.highlighted + step, 0), count - 1);

  if (highlighted === view.highlighted) {
    return undefined;
  }

  return {
    type: 'move',
    view: {
      highlighted,
      top: visibleRange(count, highlighted, rows, view.top).start,
    },
  };
}

/** One row of the picker as drawn. */
export interface PickerRow<C extends PickerChoice = PickerChoice> {
  readonly choice: C;
  readonly highlighted: boolean;
  /** Its place in the whole list, which its digit picks: `1.`, `10.`. */
  readonly number: string;
  /**
   * `↑` on the first row when choices are hidden above it, `↓` on the last
   * when they are hidden below, `' '` on the others; absent when every
   * choice is in sight.
   */
  readonly edge?: '↑' | '↓' | ' ';
}

/**
 * The rows in sight and how many choices are not, numbered by their place in
 * the whole list and padded so the labels line up past `9.`.
 */
export function pickerRows<C extends PickerChoice>(
  choices: readonly C[],
  view: PickerView,
  rows: number,
): { readonly rows: PickerRow<C>[]; readonly hidden: number } {
  const { start, end } = visibleRange(
    choices.length,
    view.highlighted,
    rows,
    view.top,
  );
  const scrolls = end - start < choices.length;
  const width = `${choices.length}.`.length;

  return {
    rows: choices.slice(start, end).map((choice, offset) => {
      const index = start + offset;
      const edge =
        offset === 0 && start > 0
          ? '↑'
          : index === end - 1 && end < choices.length
            ? '↓'
            : ' ';

      return {
        choice,
        highlighted: index === view.highlighted,
        number: `${index + 1}.`.padEnd(width),
        ...(scrolls ? { edge } : {}),
      };
    }),
    hidden: choices.length - (end - start),
  };
}

/**
 * The model to ask the agent for when `id` is picked: none for the one it
 * already uses, as there is nothing to switch.
 */
export function modelToAsk(
  models: AgentModels | undefined,
  id: string,
): string | undefined {
  return id === models?.current ? undefined : id;
}

/**
 * What a key does to a numbered choice list with `count` choices and
 * `highlighted` lit: ↑ and ↓ (or k and j) move the highlight, round past
 * either end; Enter picks it; a choice's number, 1 to 9, picks that one.
 * Shift+arrows are the window's, so they do nothing here.
 */
export function choiceKey(
  input: string,
  key: KeyPress,
  highlighted: number,
  count: number,
): { move: number } | { pick: number } | undefined {
  if (count === 0 || (key.shift === true && (key.upArrow || key.downArrow))) {
    return undefined;
  }

  if (key.upArrow === true || input === 'k') {
    return { move: (highlighted + count - 1) % count };
  }

  if (key.downArrow === true || input === 'j') {
    return { move: (highlighted + 1) % count };
  }

  if (key.return === true) {
    return { pick: highlighted };
  }

  const number = /^[1-9]$/.test(input) ? Number(input) - 1 : -1;

  return number >= 0 && number < count ? { pick: number } : undefined;
}
