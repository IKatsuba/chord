/**
 * What a tool call reads as on screen, kept out of the component: the
 * `Read(src/main.tsx)` headline, the marker's tone for its status, and the few
 * `⎿` lines and diffs that show what it produced.
 */
import type { ToolCallContent, ToolKind } from '@agentclientprotocol/sdk';
import type { ToolCall, TurnState } from '../../../session/transcript/types.ts';
import { type DiffView, diffView } from './diff.ts';
import { isEmpty, type TerminalView, terminalView } from './terminal.ts';
import { Chalk } from 'chalk';
import { type Run, runs } from '../../theme/text.ts';
import { brush } from '../highlight.ts';
import type { CodeTones } from '../../theme/theme.ts';
import { chordHeadline, chordLines, cutLine, sentText } from './chord.ts';
import {
  chordCallOf,
  isChordTool,
  MCP_TITLE,
} from '../../../session/transcript/chord.ts';
import { wrapLine } from '../message.ts';

export const GUARDIAN_REVIEWING = 'Guardian reviewing…';

/** Only chord's structured Guardian verdict changes its presentation. */
export function guardianView(call: ToolCall): 'hidden' | 'reviewing' | 'block' {
  switch (call.guardian) {
    case 'approved':
      return 'hidden';
    case 'inProgress':
      return 'reviewing';
    default:
      return 'block';
  }
}

/**
 * `Read(src/main.tsx)`: the tool's name, and its argument when it has one,
 * whole: a heredoc command keeps every line, as Claude Code draws it.
 */
export interface Headline {
  readonly name: string;
  readonly arg?: string;
  /** Said dim right after the name, before the argument: ` (MCP)`. */
  readonly tag?: string;
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
 * otherwise the call's kind names the tool and the title is its argument.
 * An MCP call, titled `mcp__<server>__<tool>` with its arguments only in
 * `rawInput`, is drawn as Claude Code draws it, its name alone until they
 * come; one to chord's own server,
 * by the name the session gave it, `chordServer`, as chord's own call even
 * before chord has tied it to the request it served. Codex's, which wraps
 * the server, the tool and the arguments in its `rawInput`, is drawn the
 * same way by what chord's enrichers filed from the wrapper, not its title.
 */
export function headline(call: ToolCall, chordServer?: string): Headline {
  // A plan put to the person reads as one, whatever its agent titled the
  // call: `Plan(<name>)`, cursor's name when it gave one (CHD-437).
  if (call.plan !== undefined) {
    const { name } = call.plan.wait;

    return { name: 'Plan', ...(name === undefined ? {} : { arg: name }) };
  }

  if (call.chord !== undefined) {
    return chordHeadline(call.chord);
  }

  // A record filed before the server was is drawn by its title, as then.
  if (call.mcp?.server !== undefined) {
    const { server, tool, input } = call.mcp;

    return mcpHeadline(server, tool, input, chordServer);
  }

  const mcp = MCP_TITLE.exec(call.title?.trim() ?? '');

  if (mcp === null) {
    return titleHeadline(call);
  }

  const [, server = '', tool = ''] = mcp;

  return mcpHeadline(server, tool, call.rawInput, chordServer);
}

/**
 * `<server> - <tool> (MCP)(key: JSON, …)`, as Claude Code writes an MCP
 * call; one to chord's own server as chord's own call.
 */
function mcpHeadline(
  server: string,
  tool: string,
  input: unknown,
  chordServer: string | undefined,
): Headline {
  if (server === chordServer && isChordTool(tool)) {
    return chordHeadline({ tool, input: input ?? {} });
  }

  const arg = mcpArguments(input);

  return {
    name: `${server} - ${tool}`,
    tag: ' (MCP)',
    ...(arg === undefined ? {} : { arg }),
  };
}

/**
 * An MCP call's arguments as Claude Code writes them: `key: value` joined
 * by `, `, the key bare and the value as JSON, so a newline in a string is
 * `\n` and never breaks the row; none for no arguments, none yet or
 * `null`, and anything else but an object as JSON whole. The C1 controls JSON leaves as they are are escaped
 * too, as Claude Code escapes them.
 */
export function mcpArguments(input: unknown): string | undefined {
  if (input === undefined || input === null) {
    return undefined;
  }

  const text =
    input === null || typeof input !== 'object' || Array.isArray(input)
      ? JSON.stringify(input)
      : Object.entries(input)
          .map(
            ([key, value]) =>
              `${JSON.stringify(key).slice(1, -1)}: ${JSON.stringify(value)}`,
          )
          .join(', ');

  return text === '' || text === undefined
    ? undefined
    : text.replace(
        /[\u007f-\u009f]/g,
        (char) => `\\u${char.charCodeAt(0).toString(16).padStart(4, '0')}`,
      );
}

/**
 * A headline for a row that stays one row, a subagent's latest calls and
 * the sessions list's: its argument's first line.
 */
export function firstLine(line: Headline): Headline {
  const [first = ''] = line.arg?.split('\n') ?? [];

  return line.arg === undefined ? line : { ...line, arg: first.trimEnd() };
}

/**
 * Styles a headline is built with before it is wrapped: every colour as
 * itself, as wrap-ansi carries the codes across the rows it breaks, and
 * `runs` reads them back into OpenTUI's spans.
 */
const STYLE = new Chalk({ level: 3 });

/**
 * A headline laid out in rows of `width` cells, each row its styled runs:
 * the name bold, a recipient's in its `colour`, the `to` and the note dim.
 * It is built as one string with those codes and wrapped by `wrapLine`, so
 * each line of its argument starts a row, a line wider than the room breaks
 * between words, and the `)` and the note follow the argument's last word.
 */
export function headlineRows(
  { name, arg, tag, note, sent }: Headline,
  width: number,
  colour?: string,
): Run[][] {
  const named = brush(STYLE, sent ? colour : undefined);
  const text = [
    sent ? STYLE.dim('to ') : '',
    STYLE.bold(named(sent ? `@${name}` : name)),
    tag === undefined ? '' : STYLE.dim(tag),
    arg === undefined ? '' : `(${arg})`,
    note === undefined ? '' : STYLE.dim(note),
  ].join('');
  const wrapped = text
    .split('\n')
    .flatMap((line) => wrapLine(line, width))
    .join('\n');
  const rows: Run[][] = [[]];

  // Read as one, so a style the agent opened on a line holds on the next.
  for (const run of runs(wrapped)) {
    const [first = '', ...rest] = run.text.split('\n');

    if (first !== '') {
      rows.at(-1)!.push({ ...run, text: first });
    }

    for (const row of rest) {
      rows.push(row === '' ? [] : [{ ...run, text: row }]);
    }
  }

  return rows;
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

/**
 * Whether the turn waits on the person for the call `callId` of the
 * session's own agent, or of the subagent `subagentId`: a permission box
 * is open for it, or queued behind another.
 */
export function asksFor(
  turn: TurnState,
  callId: string,
  subagentId?: string,
): boolean {
  return (
    turn.status === 'awaiting_permission' &&
    turn.permissions.some(
      (wait) => wait.toolCallId === callId && wait.subagentId === subagentId,
    )
  );
}

/** How the marker before a call is drawn. */
export type Tone = 'pending' | 'running' | 'done' | 'failed';

/**
 * The marker's tone for the call's ACP status; one the person is being
 * `asked` about waits on them whatever its status, as Codex's adapter keeps
 * a command `in_progress` while it asks (the owner's answer on CHD-404).
 */
export function toneOf(call: ToolCall, asked = false): Tone {
  if (call.chord?.error !== undefined) {
    return 'failed';
  }

  if (asked) {
    return 'pending';
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

/** A sent message's body: the text it sent, then what said it failed. */
export interface SentBody {
  readonly text: string;
  /** chord's refusal, or `Failed`, drawn after the fold. */
  readonly ending?: string;
}

/**
 * A `send_message` call's text, drawn under its `→` as a received message's
 * is, in every state, so what was sent reads as what came in; a refused or
 * failed one keeps it, as the message most worth reading, and says why after
 * it; one cut off before it reached chord, read from the call as the agent
 * sent it to `chordServer`, says it was not delivered. None for any other
 * call or an empty text, whose own lines say it.
 */
export function sentBody(
  call: ToolCall,
  chordServer?: string,
): SentBody | undefined {
  const cut = cutChord(call, chordServer);
  const chord = call.chord ?? cut;
  const text = chord === undefined ? undefined : sentText(chord);

  if (text === undefined) {
    return undefined;
  }

  if (cut !== undefined) {
    return { text, ending: cutLine(cut.tool) };
  }

  return toneOf(call) === 'failed'
    ? { text, ending: call.chord?.error ?? 'Failed' }
    : { text };
}

/**
 * The call of chord's tools `call` asked for when the agent cut it off
 * before it reached chord: nothing served for it, so it did nothing.
 */
function cutChord(call: ToolCall, chordServer: string | undefined) {
  return call.cut === true && call.chord === undefined
    ? chordCallOf(call, chordServer)
    : undefined;
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
 * The kinds of call whose result still folds after `SUMMARY_LINES` lines:
 * Read's, which is the file, while its rule is open with the owner; every
 * other result is drawn whole (the owner's answer on CHD-422).
 */
const FOLDED_KINDS: ReadonlySet<string> = new Set(['read']);

/**
 * What the call produced, whole, each diff too; a Read's first few lines
 * unless `expanded`, and each terminal's last few, as `terminalView` keeps
 * them. A call still waiting or running with nothing to show says so, a
 * terminal that has written nothing yet included, unless what ran it has
 * `ended`, when nothing is waiting any more; a failed call with nothing to
 * say still says it failed, so failure never rests on colour alone. With a
 * theme's `tones`, the diffs' code is coloured. With the room its lines
 * have, `width`, each line is wrapped to it, never cut. One the person is
 * `asked` about says it waits above whatever it has to show.
 */
export function summary(
  call: ToolCall,
  expanded: boolean,
  tones?: CodeTones,
  ended = false,
  width?: number,
  chordServer?: string,
  asked = false,
): Summary {
  // A box of questions' record under the call says what was asked and
  // answered; ctrl+o shows the call's own lines too.
  if (call.asked === true && !expanded) {
    return { lines: [], hidden: 0, terminals: [], diffs: [] };
  }

  const content = call.content ?? [];
  const cut = cutChord(call, chordServer);
  // chord's own say what was sent or answered, not the answer's JSON; one
  // cut off what it asked for and that it did nothing, not the agent's error.
  const lines =
    cut !== undefined
      ? [...chordLines(cut), cutLine(cut.tool)]
      : call.chord === undefined
        ? content.flatMap(contentLines)
        : chordLines(call.chord, expanded);
  const diffs = content.flatMap((item) =>
    item.type === 'diff'
      ? [diffView(item.path, item.oldText, item.newText, true, tones)]
      : [],
  );
  const terminals = (call.terminals ?? [])
    .map((terminal) => terminalView(terminal, expanded))
    .filter((view) => !isEmpty(view));
  const tone = toneOf(call, asked);
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
    tone === 'failed' &&
    lines.length > 0 &&
    call.chord === undefined &&
    cut === undefined
      ? withError(lines)
      : lines;

  const folds =
    chordCallOf(call, chordServer)?.tool !== 'get_budgets' &&
    !(
      call.chord?.tool === 'run_team' &&
      typeof call.chord.answer === 'object' &&
      call.chord.answer !== null &&
      'receipt' in call.chord.answer
    ) &&
    !expanded &&
    FOLDED_KINDS.has(call.kind ?? '') &&
    shown.length > SUMMARY_LINES;
  const kept = [
    ...(asked && tone === 'pending' ? ['Waiting…'] : []),
    ...(folds ? shown.slice(0, SUMMARY_LINES) : shown),
  ];

  return {
    lines:
      width === undefined
        ? kept
        : kept.flatMap((line) => wrapLine(line, width)),
    hidden: folds ? shown.length - SUMMARY_LINES : 0,
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
