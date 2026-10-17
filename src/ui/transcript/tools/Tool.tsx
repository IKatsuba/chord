import { useTerminalDimensions } from '@opentui/react';
import {
  Fragment,
  type ReactNode,
  useContext,
  useEffect,
  useMemo,
  useState,
} from 'react';
import stripAnsi from 'strip-ansi';
import type { ToolCall } from '../../../session/transcript/types.ts';
import {
  ChordServerName,
  paint,
  useAgentColour,
  useColours,
  useHintKey,
  useSelectable,
} from '../../app/context.ts';
import { Ansi } from '../../theme/Ansi.tsx';
import { colour, CUT, DIM, fg, FILL, ROWS, TEXT } from '../../theme/text.ts';
import type { Palette } from '../../theme/theme.ts';
import { markdown } from '../markdown.ts';
import {
  type ArrowTone,
  outArrow,
  wholeMessage,
  wrapLine,
} from '../message.ts';
import { diffHeadline, type DiffView } from './diff.ts';
import {
  agentRows,
  bodyChange,
  bodyChangeLine,
  bodyLines,
  changeRows,
  instructionLines,
  proposalBody,
  proposalOf,
  proposalTable,
  type ProposalView,
  savedLine,
  skipsAsking,
  type TableLine,
} from './proposal.ts';
import type { TerminalView } from './terminal.ts';
import { callTarget } from '../targets.ts';
import {
  type Headline,
  headline,
  headlineRows,
  sentBody,
  summary,
  type Tone,
  toneOf,
} from './tools.ts';

function toneColour(tone: Tone, colours: Palette): string | undefined {
  switch (tone) {
    case 'pending':
      return undefined;
    case 'running':
      return colours.accent;
    case 'done':
      return colours.success;
    case 'failed':
      return colours.error;
  }
}

/**
 * `⏺ Read(src/main.tsx)` and what it produced under `⎿`, then each edit's
 * diff. The headline is drawn whole, wrapped to the row's `width`, and so
 * is every line under it, never cut in the middle (CHD-422); what a message
 * sent says is drawn whole, as a received one's is. A call left running in
 * a turn or a subagent that has `ended` no longer blinks or says it waits.
 */
export function Tool({
  call,
  expanded,
  ended = false,
  width,
}: {
  call: ToolCall;
  expanded: boolean;
  ended?: boolean;
  /** Cells beside the marker. */
  width: number;
}) {
  const chordServer = useContext(ChordServerName);
  const line = headline(call, chordServer);
  const recipient = useAgentColour(line.name);
  const live = toneOf(call);
  const tone = ended && live === 'running' ? 'pending' : live;
  const colours = useColours();
  const selectable = useSelectable();
  const proposal =
    call.chord === undefined ? undefined : proposalOf(call.chord);
  const { lines, hidden, terminals, diffs } = summary(
    call,
    expanded,
    colours.code,
    ended,
    // The `⎿` and its gutter take five columns.
    Math.max(width - 5, 1),
    chordServer,
  );
  const sent = sentBody(call, chordServer);
  // Rows drawn ahead of each terminal's, so only the first row of all has `⎿`.
  const ahead = terminals.reduce<number[]>(
    (counts, view, index) => [
      ...counts,
      counts[index]! + view.lines.length + (view.note ? 1 : 0),
    ],
    [lines.length],
  );

  return (
    <box id={callTarget(call.id)} marginTop={1} flexShrink={0}>
      <box flexDirection='row'>
        {line.sent ? (
          <Arrow glyph='→' tone={outArrow(tone)} colour={recipient} />
        ) : (
          <ToolMarker tone={tone} />
        )}
        <HeadlineText line={line} width={width} colour={recipient} />
      </box>
      {proposal !== undefined && (
        <Proposal
          view={proposal}
          expanded={expanded}
          width={Math.max(width - 5, 1)}
        />
      )}
      {sent !== undefined && (
        <MessageBody text={sent.text} width={width} ending={sent.ending} />
      )}
      {proposal === undefined &&
        sent === undefined &&
        lines.map((line, index) => (
          <Under key={index} first={index === 0}>
            <text
              {...ROWS}
              {...selectable}
              {...(tone === 'failed' ? fg(colours.error) : { attributes: DIM })}
            >
              <Ansi text={line === '' ? ' ' : line} />
            </text>
          </Under>
        ))}
      {sent === undefined && hidden > 0 && <Folded hidden={hidden} />}
      {terminals.map((view, index) => (
        <TerminalOutput
          key={index}
          view={view}
          first={ahead[index] === 0}
          width={Math.max(width - 5, 1)}
        />
      ))}
      {diffs.map((view, index) => (
        <Diff
          key={index}
          view={view}
          first={ahead.at(-1) === 0 && index === 0}
          width={Math.max(width - 5, 1)}
        />
      ))}
    </box>
  );
}

/**
 * A message's text under its arrow, `←` or `→` alike, so the two never
 * drift apart: as markdown at the row's `width` less the gutter, whole,
 * never folded or cut, as the owner reads a message in full (CHD-387), dim,
 * or in the error colour when it `failed`; then `ending`, why a send
 * failed, in the error colour.
 */
export function MessageBody({
  text,
  width,
  failed = false,
  ending,
}: {
  text: string;
  /** Cells beside the marker. */
  width: number;
  failed?: boolean;
  ending?: string | undefined;
}) {
  const colours = useColours();
  const selectable = useSelectable();
  const blocks = useMemo(
    () =>
      // An agent's own escapes are text, not styling chord answers for.
      markdown(stripAnsi(text), Math.max(width - 5, 1), undefined, colours),
    [text, width, colours],
  );
  const lines = wholeMessage(
    blocks.flatMap((block, index) => [
      ...(index === 0 ? [] : ['']),
      ...block.text.split('\n'),
    ]),
  );

  return (
    <>
      {lines.map((line, index) => (
        <Under key={index} first={index === 0}>
          <text
            {...FILL}
            {...selectable}
            {...(failed ? fg(colours.error) : { attributes: DIM })}
          >
            <Ansi text={line === '' ? ' ' : line} />
          </text>
        </Under>
      ))}
      {ending !== undefined && (
        <Under first={lines.length === 0}>
          <text {...FILL} {...selectable} {...fg(colours.error)}>
            {ending}
          </text>
        </Under>
      )}
    </>
  );
}

/**
 * A headline beside its marker, whole, in the rows `headlineRows` lays out
 * in `width` cells: the name bold, a recipient's in its `colour`, the note
 * dim. Each row ends in a line break of the text's own, so OpenTUI wraps
 * nothing and measures the text as tall as its rows.
 */
export function HeadlineText({
  line,
  width,
  colour,
}: {
  line: Headline;
  width: number;
  colour?: string | undefined;
}) {
  const selectable = useSelectable();
  const rows = headlineRows(line, width, colour);

  return (
    <text {...FILL} wrapMode='none' {...selectable}>
      {rows.map((row, index) => (
        <Fragment key={index}>
          {index > 0 && <span>{'\n'}</span>}
          {row.map((run, at) => (
            <span
              key={at}
              {...(run.fg === undefined ? {} : { fg: run.fg })}
              {...(run.bg === undefined ? {} : { bg: run.bg })}
              attributes={run.attributes}
            >
              {run.text}
            </span>
          ))}
        </Fragment>
      ))}
    </text>
  );
}

/**
 * `propose_team`'s team under its call: the description, a row per agent
 * with each mode whole, a mode that skips the person's ok in the warning
 * colour and a change's rows marked, then each agent's instructions and
 * the body, whole as a tool's result is (CHD-422), or a change's body as a
 * diff under a line that counts it, and the line the person's answer left.
 */
function Proposal({
  view,
  expanded,
  width,
}: {
  view: ProposalView;
  expanded: boolean;
  /** Cells beside the `⎿` and its gutter. */
  width: number;
}) {
  const colours = useColours();
  const { height: windowRows } = useTerminalDimensions();
  const { team, before } = view;
  const marked = view.kind === 'change' && before !== undefined;
  const table = proposalTable(agentRows(team, before), width, marked, expanded);
  const description = wrapLine(team.description, width);
  const blocks = useMemo(
    () => markdown(team.body, width, undefined, colours),
    [team.body, width, colours],
  );
  const diff =
    marked && before.body !== team.body
      ? bodyChange({
          name: view.name,
          before: before.body,
          after: team.body,
          // A tool result's, drawn whole (CHD-422).
          expanded: true,
          rows: changeRows(windowRows ?? 24),
          tones: colours.code,
        })
      : undefined;
  const { lines: shown, hidden: body } = proposalBody({
    instructions: instructionLines(team, width),
    blocks: diff === undefined ? blocks.map((block) => block.text) : [],
    keep: bodyLines(windowRows ?? 24),
    expanded: true,
  });
  const hidden = body + (diff?.hidden ?? 0);
  const saved = savedLine(view);

  return (
    <>
      {description.map((line, index) => (
        <Under key={`d${index}`} first={index === 0}>
          <text {...FILL} attributes={DIM}>
            <Ansi text={line} />
          </text>
        </Under>
      ))}
      <box height={1} flexShrink={1} />
      {table.map((line, index) => (
        <Under key={`t${index}`} first={false}>
          <TableRow line={line} warning={colours.warning} />
        </Under>
      ))}
      {shown.map((line, index) => (
        <Under key={`b${index}`} first={false}>
          <text {...FILL}>
            <Ansi text={line === '' ? ' ' : line} />
          </text>
        </Under>
      ))}
      {diff !== undefined && (
        <Diff
          view={diff.view}
          first={false}
          headline={bodyChangeLine(view.name, diff.view)}
          width={width}
        />
      )}
      {hidden > 0 && <Folded hidden={hidden} />}
      {saved !== undefined && (
        <Under first={false}>
          <text
            {...FILL}
            {...(saved.saved ? fg(colours.success) : { attributes: DIM })}
          >
            {saved.text}
          </text>
        </Under>
      )}
    </>
  );
}

/**
 * One agent's row, its mode in the warning colour where it skips asking,
 * and what a changed effort and mode were dim.
 */
export function TableRow({
  line,
  warning,
}: {
  line: TableLine;
  warning: string | undefined;
}) {
  const {
    text,
    mode: [start, end],
    was,
    effortWas,
    row,
  } = line;

  if (row.change === 'removed' || line.role) {
    return (
      <text {...FILL} attributes={DIM}>
        {text}
      </text>
    );
  }

  // Painted spans in the order they are in the line, the effort's column
  // being before the mode's, and the text between them plain.
  const spans = [
    ...(effortWas === undefined ? [] : [{ at: effortWas, dim: true }]),
    { at: [start, end] as const, dim: false },
    ...(was === undefined ? [] : [{ at: was, dim: true }]),
  ].filter(({ at: [from, to] }) => from < to);
  let read = 0;

  return (
    <text {...FILL}>
      {spans.map(({ at: [from, to], dim }) => {
        const plain = text.slice(read, from);

        read = to;

        return (
          <Fragment key={from}>
            {plain}
            <span
              {...(dim
                ? { attributes: DIM }
                : skipsAsking(row.mode)
                  ? fg(warning)
                  : {})}
            >
              {text.slice(from, to)}
            </span>
          </Fragment>
        );
      })}
      {text.slice(read)}
    </text>
  );
}

/**
 * What a command wrote in its terminal, dim as a call's other lines, its
 * latest lines, each wrapped to `width`, and the count of those above them,
 * then a failing exit in the error tone.
 */
function TerminalOutput({
  view,
  first,
  width,
}: {
  view: TerminalView;
  first: boolean;
  width: number;
}) {
  const { error } = useColours();
  const selectable = useSelectable();
  const rows = view.lines.flatMap((line) => wrapLine(line, width));

  return (
    <>
      {rows.map((line, index) => (
        <Under key={index} first={first && index === 0}>
          <text {...ROWS} {...selectable} attributes={DIM}>
            {line === '' ? ' ' : line}
          </text>
        </Under>
      ))}
      {view.hidden > 0 && <Folded hidden={view.hidden} />}
      {view.note && (
        <Under first={first && view.lines.length === 0}>
          <text
            {...FILL}
            {...(view.note.failed ? fg(error) : { attributes: DIM })}
          >
            {view.note.text}
          </text>
        </Under>
      )}
    </>
  );
}

/** A line hung off a call, behind `⎿` when it is the first. */
export function Under({
  first,
  children,
}: {
  first: boolean;
  children: ReactNode;
}) {
  return (
    <box flexDirection='row' paddingLeft={2}>
      <Gutter width={3} dimColor>
        {first ? '⎿' : ' '}
      </Gutter>
      {children}
    </box>
  );
}

export function Folded({
  hidden,
  inset = 5,
}: {
  hidden: number;
  inset?: number;
}) {
  const key = useHintKey('app:toggleTranscript');

  return (
    <box flexDirection='row' paddingLeft={inset}>
      <text {...CUT} attributes={DIM}>
        {`… +${hidden} ${hidden === 1 ? 'line' : 'lines'}${
          key === undefined ? '' : ` (${key} to expand)`
        }`}
      </text>
    </box>
  );
}

const DIFF_MARKS = { added: '+', removed: '-', context: ' ' } as const;

/**
 * Claude Code's edit: the `Updated` line, then numbered rows behind a `+` or
 * `-`, so no change rests on colour alone.
 */
function Diff({
  view,
  first,
  headline = diffHeadline(view),
  width,
}: {
  view: DiffView;
  first: boolean;
  /** In place of `Updated …`, for a change not written yet. */
  headline?: string;
  /** Cells beside the `⎿`, which each row's code is wrapped to. */
  width?: number;
}) {
  const selectable = useSelectable();

  return (
    <>
      <Under first={first}>
        <text {...FILL} {...selectable} attributes={DIM}>
          {headline}
        </text>
      </Under>
      {view.rows.length > 0 && (
        <box paddingLeft={5}>
          <DiffRows view={view} {...(width === undefined ? {} : { width })} />
        </box>
      )}
      {view.hidden > 0 && <Folded hidden={view.hidden} />}
    </>
  );
}

/**
 * A diff's rows in the theme's colours. With a tint, a changed row is tinted
 * green or red and its code coloured by the file's language on the tint;
 * without, as in the 16-colour themes, the row is green or red from its sign
 * on, as `git diff` draws it; under NO_COLOR it is neither. Given the
 * `width` the rows take, a line longer than its room wraps under its code,
 * the number and the sign on its first row alone.
 */
export function DiffRows({ view, width }: { view: DiffView; width?: number }) {
  const { diff } = useColours();
  const { tint } = diff;
  const selectable = useSelectable();
  // The number, a space, the sign and a space before the code.
  const room =
    width === undefined ? undefined : Math.max(width - view.numberWidth - 3, 1);

  return view.rows.flatMap((row, index) => {
    if (row.kind === 'gap') {
      return [
        <box key={index} flexDirection='row'>
          <text {...TEXT} attributes={DIM}>
            {' '.repeat(view.numberWidth + 1)}…
          </text>
        </box>,
      ];
    }

    const code =
      tint || row.kind === 'context' ? (row.code ?? row.text) : row.text;
    const pieces = room === undefined ? [code] : wrapLine(code, room);
    const colouring = tint
      ? row.kind === 'context'
        ? {}
        : fg(tint.text)
      : row.kind === 'context'
        ? {}
        : fg(diff[row.kind]);

    return pieces.map((piece, at) => (
      <box
        key={`${index}.${at}`}
        flexDirection='row'
        {...(tint
          ? {
              flexGrow: 1,
              ...(row.kind === 'context'
                ? {}
                : { backgroundColor: colour(tint[row.kind]) }),
            }
          : {})}
      >
        <Gutter width={view.numberWidth + 1} dimColor>
          {at === 0 ? String(row.number).padStart(view.numberWidth) : ''}
        </Gutter>
        <text {...TEXT} {...(row.kind === 'context' ? {} : fg(diff[row.kind]))}>
          {at === 0 ? `${DIFF_MARKS[row.kind]} ` : '  '}
        </text>
        <text {...ROWS} {...selectable} {...colouring}>
          <Ansi text={piece === '' ? ' ' : piece} />
        </text>
      </box>
    ));
  });
}

/**
 * The status as the ⏺'s colour; a running call pulses between the accent and
 * dim, so it reads as alive without the mark vanishing from a captured screen.
 */
export function ToolMarker({ tone }: { tone: Tone }) {
  const [lit, setLit] = useState(true);
  const running = tone === 'running';

  useEffect(() => {
    if (!running) {
      return;
    }

    const timer = setInterval(() => setLit((on) => !on), 500);

    return () => clearInterval(timer);
  }, [running]);

  const colour = toneColour(tone, useColours());

  if (colour === undefined || (running && !lit)) {
    return <Gutter dimColor>⏺</Gutter>;
  }

  return <Gutter color={colour}>⏺</Gutter>;
}

/** A message's `←` or `→` in the gutter, in its tone. */
export function Arrow({
  glyph,
  tone,
  colour,
}: {
  glyph: '←' | '→';
  tone: ArrowTone;
  /** The other agent's colour, for an arrow that is neither dim nor red. */
  colour?: string | undefined;
}) {
  const { error, warning } = useColours();

  switch (tone) {
    case 'plain':
      return <Gutter {...paint(colour)}>{glyph}</Gutter>;
    case 'warning':
      return <Gutter {...paint(warning)}>{glyph}</Gutter>;
    case 'dim':
      return <Gutter dimColor>{glyph}</Gutter>;
    case 'failed':
      return <Gutter {...paint(error)}>{glyph}</Gutter>;
  }
}

/**
 * The mark before a block; it never shrinks, so a long unbroken line wraps
 * beside it instead of squeezing it.
 */

export function Gutter({
  children,
  width = 2,
  color,
  dimColor,
}: {
  children: string;
  width?: number;
  color?: string;
  dimColor?: boolean;
}) {
  return (
    <box flexDirection='row' width={width} flexShrink={0}>
      <text {...TEXT} {...fg(color)} attributes={dimColor ? DIM : 0}>
        {children}
      </text>
    </box>
  );
}

/**
 * A line under the turn it ends, as Claude Code hangs one off a message; dim,
 * or in the error colour when it is a refusal or an interrupt.
 */
export function Outcome({
  text,
  failed = false,
}: {
  text: string;
  failed?: boolean;
}) {
  const { error } = useColours();

  return (
    <box flexDirection='row' paddingLeft={2} flexShrink={0}>
      <Gutter width={3} dimColor>
        ⎿
      </Gutter>
      <text {...FILL} {...(failed ? fg(error) : { attributes: DIM })}>
        <Ansi text={text} />
      </text>
    </box>
  );
}

/**
 * In the error colour when it stopped something; a warning, which chord
 * carries on past, in the warning colour.
 */
export function Failure({
  text,
  tone = 'error',
}: {
  text: string;
  tone?: 'error' | 'warning';
}) {
  const colour = useColours()[tone];

  return (
    <box flexDirection='row' marginTop={1} flexShrink={0}>
      <Gutter {...paint(colour)}>⏺</Gutter>
      <text {...FILL} {...fg(colour)}>
        <Ansi text={text} />
      </text>
    </box>
  );
}
