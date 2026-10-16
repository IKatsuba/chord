/**
 * What a message from another agent, or chord, reads as, kept out of the
 * component: its header, and its text folded after six lines, twice a tool
 * call's three, as a message is words meant to be read.
 */
import cliTruncate from 'cli-truncate';
import stringWidth from 'string-width';
import wrapAnsi from 'wrap-ansi';
import { fromLine, senderName } from '../../session/tasks.ts';
import type {
  MessageFrom,
  MonitorEnd,
  TeamPart,
} from '../../session/transcript/types.ts';
import type { Tone } from './tools/tools.ts';

/** How many lines of a message show before it folds. */
export const MESSAGE_LINES = 6;

/**
 * The header after `←`: `from`, dim, so the row reads as one that came in
 * whichever way the arrow is remembered, then the sender bold, `@` and all,
 * then the rest dim.
 */
export function messageHeader(from: MessageFrom): {
  readonly word: string;
  readonly name: string;
  readonly rest: string;
} {
  const whole = fromLine(from);

  return {
    word: 'from ',
    name: senderName(from),
    rest: whole.slice(from.name.length),
  };
}

/**
 * How a message's arrow is drawn: as the text is, dim, or in the error
 * colour. The direction is the arrow's shape, so no tone carries it.
 */
export type ArrowTone = 'plain' | 'dim' | 'failed' | 'warning';

/**
 * `←`: a failed report's in the error colour, chord's own dim, and a
 * monitor's end by how it ended.
 */
export function inArrow(from: MessageFrom): ArrowTone {
  const end = from.monitor?.end;

  if (end !== undefined) {
    return monitorArrow(end);
  }

  if (from.note === 'failed') {
    return 'failed';
  }

  return from.name === 'chord' ? 'dim' : 'plain';
}

/**
 * A monitor's end: a clean exit plain, the person's stop dim, a timeout a
 * warning, and whatever else cut it short an error.
 */
function monitorArrow(end: MonitorEnd): ArrowTone {
  switch (end.kind) {
    case 'exit':
      return end.code === 0 ? 'plain' : 'failed';
    case 'stopped':
      return 'dim';
    case 'timed_out':
      return 'warning';
    case 'signal':
    case 'flooded':
      return 'failed';
  }
}

/**
 * `→`, from its call's tone: dim until it is delivered, in the error colour
 * when chord refused it.
 */
export function outArrow(tone: Tone): ArrowTone {
  switch (tone) {
    case 'pending':
    case 'running':
      return 'dim';
    case 'failed':
      return 'failed';
    case 'done':
      return 'plain';
  }
}

/** A message's lines as its row draws them. */
export interface Folded {
  readonly lines: readonly string[];
  /** How many lines the fold left out. */
  readonly hidden: number;
  /** A monitor's end: chord's sentence, drawn dim after the fold. */
  readonly sentence?: string;
}

/**
 * The lines of a message laid out already, the first `MESSAGE_LINES` of them
 * unless `expanded`, and how many were left out.
 */
export function foldMessage(
  lines: readonly string[],
  expanded: boolean,
): Folded {
  // A last blank line would hide a line for nothing.
  const kept = lines.join('\n').replace(/\s+$/, '').split('\n');

  if (expanded || kept.length <= MESSAGE_LINES) {
    return { lines: kept, hidden: 0 };
  }

  // A fold that ends on a blank line reads as a gap before the fold line.
  const shown = kept
    .slice(0, MESSAGE_LINES)
    .join('\n')
    .replace(/\s+$/, '')
    .split('\n');

  return { lines: shown, hidden: kept.length - shown.length };
}

/**
 * A monitor's event as its row draws it, `width` wide: the lines it printed,
 * verbatim, as a log's `*` and `_` are no emphasis, each wrapped after its
 * own indent with the space at a break dropped, folded as any message is;
 * and on its end, chord's sentence, which its message carries last and the
 * row draws dim and never folds.
 */
export function monitorMessage(
  text: string,
  {
    ended,
    expanded,
    width,
  }: {
    readonly ended: boolean;
    readonly expanded: boolean;
    readonly width: number;
  },
): Folded {
  const all = text.split('\n');
  const sentence = ended ? all.pop() : undefined;
  const rows = all.flatMap((line) => wrapLine(line, width));
  const folded =
    rows.length === 0 ? { lines: [], hidden: 0 } : foldMessage(rows, expanded);

  return sentence === undefined
    ? folded
    : { ...folded, sentence: wrapLine(sentence, width).join('\n') };
}

/**
 * A line wrapped to `width`, its indent kept on its first row: as much of it
 * as leaves a cell for the text, so no row is wider than `width`.
 */
export function wrapLine(line: string, width: number): string[] {
  let indent = /^\s*/.exec(line)![0];

  while (indent !== '' && stringWidth(indent) > width - 1) {
    indent = indent.slice(0, -1);
  }

  const room = Math.max(1, width - stringWidth(indent));

  return wrapAnsi(line.trimStart(), room, { hard: true, trim: true })
    .split('\n')
    .map((row, index) => (index === 0 ? indent + row : row));
}

/**
 * A queued message's row after its `←`: its header, `from @parser · codex: `,
 * and its first line apart, as the row draws the header whole and cuts only
 * the text to the width, so a long name never cuts away why it waits. One
 * held for the person's answer says so in its header.
 */
export function queuedMessage(
  from: MessageFrom,
  text: string,
  afterAnswer = false,
): { readonly header: string; readonly text: string } {
  const [first = '', ...rest] = text.split('\n');
  const { word, name, rest: after } = messageHeader(from);

  return {
    header: `${word}${name}${after}${afterAnswer ? ' · after your answer' : ''}: `,
    text: rest.length > 0 ? `${first} …` : first,
  };
}

/**
 * The one line a team part draws as: whose instructions, for whom, and how
 * long, with the key that shows them while they are folded.
 */
export function teamPartLine(
  part: TeamPart,
  expanded: boolean,
  key: string | undefined,
): string {
  const lines = part.text.split('\n').length;

  return `${part.team}'s instructions for ${
    part.member ?? 'the lead'
  } · ${lines} ${lines === 1 ? 'line' : 'lines'}${
    expanded || key === undefined ? '' : ` (${key} to expand)`
  }`;
}

/**
 * The line that closes a turn the agent started on its own with a message,
 * which chord cancelled: whose turn it was, and where the message went, cut
 * at its end to `cells`, as what matters comes first.
 */
export function selfStartedLine(from: MessageFrom, cells: number): string {
  return cliTruncate(
    `Interrupted · the agent started this on its own; ${senderName(from)}'s message goes as the next turn`,
    cells,
  );
}
