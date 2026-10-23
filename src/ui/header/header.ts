/**
 * The startup header at the top of each session's transcript, as
 * docs/design/CHD-201.md settles it: how the mark is coloured on this
 * terminal, and the lines beside it.
 */
import { cutPath } from '../pickers/mcp.ts';
import { lastUsed } from '../pickers/picker.ts';
import type { MarkTones } from '../theme/theme.ts';
import { MARK } from './mark.ts';
import type { MarkColour } from './mark_rows.ts';

/** Columns between the mark's last column and the text. */
export const MARK_GAP = 3;

/** Cells the mark is wide. */
export const MARK_WIDTH = Math.max(0, ...MARK.map((row) => row.length));

/**
 * Cells the lines beside the mark have in a window `columns` wide, inside
 * the transcript's padding on both sides.
 */
export function textWidth(columns: number): number {
  return columns - 2 - MARK_WIDTH - MARK_GAP;
}

/**
 * How the mark is painted at chalk's colour `level` (0 to 3) in a theme
 * whose mark takes `tones`: the gradient where the terminal has 256 colours
 * or more and the theme has stops, else its one tone, and nothing where
 * colour is off, which leaves the theme no tones at all.
 */
export function markColour(
  tones: MarkTones | undefined,
  level: number,
): MarkColour {
  if (tones === undefined || level < 1) {
    return { level: 'none' };
  }

  if (tones.stops !== undefined && level >= 2) {
    return { level: level >= 3 ? 'truecolor' : '256', stops: tones.stops };
  }

  return { level: '16', tone: tones.tone };
}

/** A run of a header line: `chord` alone is bold, the rest dim. */
export interface HeaderPart {
  readonly text: string;
  readonly bold?: true;
}

export type HeaderLine = readonly HeaderPart[];

/** What the header says of its session. */
export interface HeaderFacts {
  /** chord's own version, as `--version` prints it. */
  readonly version: string;
  readonly agent: string;
  /**
   * The model the session started on, as the status line names it; none
   * until the agent reports one.
   */
  readonly model?: string | undefined;
  /** The session's directory as the window shows it. */
  readonly directory: string;
  /**
   * The key that opens the shortcuts, as the status line's hint names it;
   * none where the keybindings file unbinds it.
   */
  readonly helpKey?: string | undefined;
  /** Set for a session opened again from an earlier one. */
  readonly resumed?:
    | {
        /** When it was last used, epoch milliseconds, where chord knows it. */
        readonly lastUsedAt?: number | undefined;
        /** Its first prompt, on one line, where its past holds one. */
        readonly title?: string | undefined;
        /**
         * Whether `title` is the agent's own title for it, which wraps
         * under its own start rather than being cut (CHD-445).
         */
        readonly titled?: boolean | undefined;
      }
    | undefined;
}

/** Which of `headerLines` says a session was resumed, when one was. */
export const RESUMED_LINE = 4;

/**
 * The lines beside the mark, for a text column `width` cells wide at `now`.
 * The directory is cut from the left, at a `/`; the other
 * lines are cut at the right by the component, a resumed session's title
 * first, as it goes last, but an agent's own title, which wraps (CHD-445).
 */
export function headerLines(
  facts: HeaderFacts,
  width: number,
  now: number,
): HeaderLine[] {
  const { version, agent, model, directory, helpKey, resumed } = facts;
  const lines: HeaderLine[] = [
    [{ text: 'chord', bold: true }, { text: ` v${version}` }],
    // A model reported later grows the line rather than replacing a
    // placeholder.
    [{ text: model === undefined ? agent : `${agent} · ${model}` }],
    [{ text: cutPath(directory, Math.max(1, width)) }],
    // A key unbound is left unsaid, as on the status line; /help is a
    // command, which no keybindings file takes away.
    [
      {
        text:
          helpKey === undefined ? '/help' : `${helpKey} for shortcuts · /help`,
      },
    ],
  ];

  if (resumed === undefined) {
    return lines;
  }

  const when =
    resumed.lastUsedAt === undefined
      ? undefined
      : lastUsed(new Date(resumed.lastUsedAt).toISOString(), now);
  const said = ['resumed', when, resumed.title].filter(
    (part) => part !== undefined && part !== '',
  );

  return [...lines, [{ text: said.join(' · ') }]];
}
