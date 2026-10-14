/**
 * What a tool call reads as on screen, kept out of the component: the
 * `Read(src/main.tsx)` headline, the marker's tone for its status, and the few
 * `⎿` lines and diffs that show what it produced.
 */
import type { ToolCallContent, ToolKind } from '@agentclientprotocol/sdk';
import type { ToolCall, TurnState } from '../../../session/transcript/types.ts';
import { type DiffView, diffView } from './diff.ts';
import { isEmpty, type TerminalView, terminalView } from './terminal.ts';
import type { CodeTones } from '../../theme/theme.ts';
import { chordHeadline, chordLines, chordWraps } from './chord.ts';
import { wrapLine } from '../message.ts';

/** `Read(src/main.tsx)`: the tool's name, and its argument when it has one. */
export interface Headline {
  readonly name: string;
  readonly arg?: string;
  /**
   * The argument's lines past its first, which only ctrl+o's view shows: a
   * headline is one row, so a heredoc command does not fill the transcript.
   */
  readonly more?: readonly string[];
  /** Said dim after it: a task's runtime, a message that waited. */
  readonly note?: string;
  /**
   * A message the session sent, `name` its recipient: drawn `→ name`, as the
   * `←` it arrives as, not as a call.
   */
  readonly sent?: true;
}

/**
 * Claude Code's names for its tools, by ACP kind, for titles that do not start
 * with a name of their own (a bare command, a description).
 */
const KIND_NAMES: Record<ToolKind, string> = {
  read: 'Read',
  edit: 'Update',
  delete: 'Delete',
  move: 'Move',
  search: 'Search',
  execute: 'Bash',
  think: 'Think',
  fetch: 'Fetch',
  switch_mode: 'Mode',
  other: 'Tool',
};

/** One code span covering the whole title: agents send commands that way. */
const CODE_SPAN = /^`([^`]+)`$/;

/** A capitalised verb, then what it acts on: `Read README.md`. */
const VERB_FIRST = /^([A-Z][A-Za-z]*) (.+)$/;

/**
 * ACP sends a free-text title (`Read README.md`, `` `ls -la` ``), so the
 * headline is read out of it: a leading capitalised verb becomes the name,
 * otherwise the call's kind names the tool and the title is its argument,
 * cut to its first line.
 */
export function headline(call: ToolCall): Headline {
  if (call.chord !== undefined) {
    return chordHeadline(call.chord);
  }

  const read = titleHeadline(call);
  const [first = '', ...more] = read.arg?.split('\n') ?? [];

  return more.length === 0 ? read : { ...read, arg: first.trimEnd(), more };
}

function titleHeadline(call: ToolCall): Headline {
  const title = call.title?.trim() ?? '';
  const kindName = call.kind === undefined ? 'Tool' : KIND_NAMES[call.kind];

  // A call whose questions chord's box answered asks: claude titles a lone
  // question by the question itself, whose first word is no tool's name.
  if (call.asked === true && title !== '') {
    return { name: 'Asking', arg: title.replace(/^Asking\s+/, '') };
  }

  if (title === '') {
    return { name: kindName };
  }

  const code = CODE_SPAN.exec(title);

  if (code) {
    return { name: kindName, arg: code[1]! };
  }

  const verb = VERB_FIRST.exec(title);

  if (verb) {
    return { name: verb[1]!, arg: unquote(verb[2]!) };
  }

  if (/^[A-Z]\S*$/.test(title)) {
    return { name: title };
  }

  return { name: kindName, arg: title };
}

function unquote(text: string): string {
  return CODE_SPAN.exec(text)?.[1] ?? text;
}

/**
 * Whether the turn a call came in has ended, so a call it left unfinished
 * waits on nothing: a resumed past, a cancelled turn, or one whose prompt has
 * returned while a task it started still asks between turns.
 */
export function turnEnded(turn: TurnState, turnId: string): boolean {
  return (
    turn.status === 'idle' ||
    (turn.status === 'awaiting_permission' && turn.between === true) ||
    turn.turnId !== turnId
  );
}

/** How the marker before a call is drawn. */
export type Tone = 'pending' | 'running' | 'done' | 'failed';

export function toneOf(call: ToolCall): Tone {
  if (call.chord?.error !== undefined) {
    return 'failed';
  }

  switch (call.status) {
    case 'in_progress':
      return 'running';
    case 'completed':
      return 'done';
    case 'failed':
      return 'failed';
    default:
      return 'pending';
  }
}

/**
 * What is drawn under a call: its `⎿` lines, of which `hidden` did not fit,
 * then what each terminal it ran a command in wrote, then the diff of each
 * edit it carries.
 */
export interface Summary {
  readonly lines: readonly string[];
  readonly hidden: number;
  readonly terminals: readonly TerminalView[];
  readonly diffs: readonly DiffView[];
}

/** As many output lines as Claude Code shows before `… +N lines`. */
export const SUMMARY_LINES = 3;

/**
 * What the call produced, a few lines of it, the last few of each terminal's
 * and a few rows of each diff unless `expanded`. A call still waiting or
 * running with nothing to show says so, a terminal that has written nothing
 * yet included, unless what ran it has `ended`, when nothing is waiting any
 * more; a failed call with nothing to say still says it failed, so failure
 * never rests on colour alone. With a theme's `tones`, the diffs' code is
 * coloured. With the room its lines have, `width`, what Open and Team handed
 * over is wrapped to it before it is folded.
 */
export function summary(
  call: ToolCall,
  expanded: boolean,
  tones?: CodeTones,
  ended = false,
  width?: number,
): Summary {
  // A box of questions' record under the call says what was asked and
  // answered; ctrl+o shows the call's own lines too.
  if (call.asked === true && !expanded) {
    return { lines: [], hidden: 0, terminals: [], diffs: [] };
  }

  const content = call.content ?? [];
  // chord's own say what was sent or answered, not the answer's JSON.
  const lines =
    call.chord === undefined
      ? content.flatMap(contentLines)
      : width !== undefined && chordWraps(call.chord)
        ? chordLines(call.chord).flatMap((line) => wrapLine(line, width))
        : chordLines(call.chord);
  const diffs = content.flatMap((item) =>
    item.type === 'diff'
      ? [diffView(item.path, item.oldText, item.newText, expanded, tones)]
      : [],
  );
  const terminals = (call.terminals ?? [])
    .map((terminal) => terminalView(terminal, expanded))
    .filter((view) => !isEmpty(view));
  const tone = toneOf(call);
  // A failing exit under a terminal already says the call failed, in words.
  const told = terminals.some((view) => view.note?.failed);

  if (
    lines.length === 0 &&
    (tone === 'failed' ? !told : terminals.length === 0 && diffs.length === 0)
  ) {
    switch (tone) {
      case 'pending':
      case 'running':
        return {
          lines: ended ? [] : [tone === 'pending' ? 'Waiting…' : 'Running…'],
          hidden: 0,
          terminals,
          diffs,
        };
      case 'failed':
        return { lines: ['Failed'], hidden: 0, terminals, diffs };
      case 'done':
        return { lines: [], hidden: 0, terminals, diffs };
    }
  }

  // chord's refusal is its own sentence, said as it is.
  const shown =
    tone === 'failed' && lines.length > 0 && call.chord === undefined
      ? withError(lines)
      : lines;

  if (expanded || shown.length <= SUMMARY_LINES) {
    return { lines: shown, hidden: 0, terminals, diffs };
  }

  return {
    lines: shown.slice(0, SUMMARY_LINES),
    hidden: shown.length - SUMMARY_LINES,
    terminals,
    diffs,
  };
}

function withError([first, ...rest]: string[]): string[] {
  return [`Error: ${first ?? ''}`, ...rest];
}

function contentLines(content: ToolCallContent): string[] {
  switch (content.type) {
    case 'content':
      return content.content.type === 'text'
        ? textLines(content.content.text)
        : [`[${content.content.type}]`];
    // A diff draws under the lines, headed by its own `Updated` line.
    case 'diff':
      return [];
    // A terminal draws under the lines from what the call's `terminals` hold.
    case 'terminal':
      return [];
    default:
      return [];
  }
}

function textLines(text: string): string[] {
  const lines = text.replace(/\s+$/, '').split(/\r?\n/);

  return lines.length === 1 && lines[0] === '' ? [] : lines;
}
