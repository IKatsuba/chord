import { TextAttributes } from '@opentui/core';
import { memo, useMemo } from 'react';
import stripAnsi from 'strip-ansi';
import type {
  Compaction,
  Entry,
  MessageFrom,
  ReportRow,
  ShellRun,
  TeamPart,
  TurnState,
} from '../../session/transcript/types.ts';
import {
  paint,
  useAgentColour,
  useColours,
  useHintKey,
  useSelectable,
} from '../app/context.ts';
import { leftOpenLine } from '../agents/agents.ts';
import { leftRunningLine } from '../../session/monitors.ts';
import { ElicitationRecord } from '../dialogs/Form.tsx';
import { permissionOutcome } from '../dialogs/permission.ts';
import { PlanRecord } from '../plan/Plan.tsx';
import { shellView } from '../prompt/bash.ts';
import { Agents } from './agents/Agents.tsx';
import { TeamEntry } from '../teams/Teams.tsx';
import { Ansi } from '../theme/Ansi.tsx';
import { CUT, DIM, DIM_BORDER, fg, FILL, TEXT } from '../theme/text.ts';
import { compactionLine, inSpinner } from './compaction.ts';
import { markdown, QUOTE_INSET } from './markdown.ts';
import {
  foldMessage,
  inArrow,
  messageHeader,
  monitorMessage,
  selfStartedLine,
  teamPartLine,
} from './message.ts';
import { indicator, type Scroll } from './scroll.ts';
import {
  Arrow,
  Failure,
  Folded,
  Gutter,
  Outcome,
  Tool,
  Under,
} from './tools/Tool.tsx';
import { turnEnded } from './tools/tools.ts';

/**
 * The rule in the transcript's last row while scrolled back: how much is
 * below, whether any of it is new, and the key back.
 */
export function Below({ scroll, width }: { scroll: Scroll; width: number }) {
  const segments = indicator(scroll, width, useHintKey('scroll:bottom'));
  const colours = useColours();

  if (segments.length === 0) {
    return null;
  }

  return (
    <box flexDirection='row' height={1} flexShrink={0}>
      <text {...CUT}>
        {segments.map(({ text, accent }, index) =>
          accent ? (
            <span
              key={index}
              attributes={TextAttributes.BOLD}
              {...fg(colours.accent)}
            >
              {text}
            </span>
          ) : (
            <span key={index} attributes={DIM}>
              {text}
            </span>
          ),
        )}
      </text>
    </box>
  );
}

// Memoised: every chunk of a streamed reply draws the window again, and an
// entry it did not land in has the same props, as the reducer keeps it.
export const TranscriptEntry = memo(function TranscriptEntry({
  entry,
  turn,
  agent,
  expanded,
  width,
}: {
  entry: Entry;
  /** The turn running, whose spinner may carry the entry instead. */
  turn: TurnState;
  /** Who asked, for a form's record. */
  agent: string;
  expanded: boolean;
  /** Cells beside the gutter. */
  width: number;
}) {
  const selectable = useSelectable();

  switch (entry.kind) {
    case 'user':
      return (
        <box flexDirection='row' marginTop={1} flexShrink={0}>
          <Gutter dimColor>›</Gutter>
          <text {...FILL} {...selectable}>
            {entry.text}
          </text>
        </box>
      );
    case 'message':
      return (
        <Message
          from={entry.from}
          text={entry.text}
          expanded={expanded}
          width={width}
        />
      );
    case 'assistant':
      return (
        <box flexDirection='row' marginTop={1} flexShrink={0}>
          <Gutter>⏺</Gutter>
          <Reply text={entry.text} width={width} />
        </box>
      );
    case 'error':
      return <Failure text={entry.message} />;
    case 'warning':
      return <Failure text={entry.message} tone='warning' />;
    case 'cancelled':
      return <Outcome text='Interrupted by user' failed />;
    case 'stopped':
      return <Outcome text={`Stopped: ${entry.reason}`} />;
    case 'self_started':
      return (
        <SelfStarted from={entry.from} alone={entry.alone} width={width} />
      );
    case 'left_open':
      return (
        <box flexDirection='row' marginTop={1} flexShrink={0}>
          <Gutter dimColor>⏺</Gutter>
          <text {...FILL} attributes={DIM}>
            <Ansi text={leftOpenLine(entry.agents)} />
          </text>
        </box>
      );
    case 'team_part':
      return <TeamPartLine part={entry.part} expanded={expanded} />;
    case 'monitors_left':
      return (
        <box flexDirection='row' marginTop={1} flexShrink={0}>
          <Gutter dimColor>⏺</Gutter>
          <text {...FILL} attributes={DIM}>
            <Ansi text={leftRunningLine(entry.monitors)} />
          </text>
        </box>
      );
    case 'permission': {
      const { text, allowed } = permissionOutcome(entry);

      return <Outcome text={text} failed={!allowed} />;
    }
    case 'elicitation':
      return (
        <ElicitationRecord entry={entry} agent={agent} expanded={expanded} />
      );
    case 'thought':
      return <Thought text={entry.text} expanded={expanded} />;
    case 'tool':
      return (
        <Tool
          call={entry.call}
          expanded={expanded}
          ended={turnEnded(turn, entry.turnId)}
          width={width}
        />
      );
    // Drawn with the subagents beside it, by whoever lists the entries.
    case 'subagent':
      return (
        <Agents
          agents={[entry.subagent]}
          turn={turn}
          agent={agent}
          open={expanded}
          width={width}
        />
      );
    case 'compaction':
      return inSpinner(entry, turn) ? null : (
        <CompactionRecord
          compaction={entry.compaction}
          expanded={expanded}
          width={width}
        />
      );
    case 'plan':
      return <PlanRecord entries={entry.entries} />;
    case 'shell':
      return <Shell run={entry.run} expanded={expanded} />;
    case 'report':
      return <Report command={entry.command} rows={entry.rows} />;
    case 'note':
      return (
        <Note command={entry.command} text={entry.text} failed={entry.failed} />
      );
    case 'team':
      return (
        <TeamEntry
          turnId={entry.turnId}
          command={entry.command}
          shown={entry.shown}
          expanded={expanded}
          width={width}
        />
      );
  }
});

/**
 * The close of a turn the agent started on its own, which chord cancelled:
 * dim, as nothing went wrong for the person, under what the turn drew, or a
 * `⏺` of its own while it drew nothing. One row, cut at its end.
 */
function SelfStarted({
  from,
  alone,
  width,
}: {
  from: MessageFrom;
  alone: boolean;
  /** Cells beside the gutter. */
  width: number;
}) {
  // Under the turn, `⎿` sits three cells further in than `⏺`.
  const text = selfStartedLine(from, alone ? width : width - 3);

  return alone ? (
    <box flexDirection='row' marginTop={1} flexShrink={0}>
      <Gutter dimColor>⏺</Gutter>
      <text {...CUT} attributes={DIM}>
        {text}
      </text>
    </box>
  ) : (
    <box flexDirection='row' paddingLeft={2} flexShrink={0}>
      <Gutter width={3} dimColor>
        ⎿
      </Gutter>
      <text {...CUT} attributes={DIM}>
        {text}
      </text>
    </box>
  );
}

/**
 * A message another agent, or chord, sent the session: `←` and who sent it,
 * then what it said as markdown, as a reply is, folded after six lines. Never
 * the person's `›`, so nothing an agent wrote reads as theirs. The body hangs
 * under `⎿`, dim, as a tool's result and the outgoing `→` row's do, so a long
 * instruction reads as quoted next to the agent's own bright replies.
 */
function Message({
  from,
  text,
  expanded,
  width,
}: {
  from: MessageFrom;
  text: string;
  expanded: boolean;
  width: number;
}) {
  const colours = useColours();
  const sender = useAgentColour(from.name);
  const { word, name, rest } = messageHeader(from);
  const monitor = from.monitor !== undefined;
  const blocks = useMemo(
    () =>
      monitor
        ? []
        : // An agent's own escapes are text, not styling chord answers for.
          markdown(stripAnsi(text), Math.max(width - 5, 1), undefined, colours),
    [monitor, text, width, colours],
  );
  const { lines, hidden, sentence } = monitor
    ? monitorMessage(text, {
        ended: from.monitor?.end !== undefined,
        expanded,
        width: Math.max(width - 5, 1),
      })
    : foldMessage(
        blocks.flatMap((block, index) => [
          ...(index === 0 ? [] : ['']),
          ...block.text.split('\n'),
        ]),
        expanded,
      );
  const failed = from.note === 'failed';
  const selectable = useSelectable();

  return (
    <box marginTop={1} flexShrink={0}>
      <box flexDirection='row'>
        <Arrow glyph='←' tone={inArrow(from)} colour={sender} />
        <text {...CUT}>
          <span attributes={DIM}>{word}</span>
          <span attributes={TextAttributes.BOLD} {...fg(sender)}>
            <Ansi text={name} />
          </span>
          <span attributes={DIM}>
            <Ansi text={rest} />
          </span>
        </text>
      </box>
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
      {hidden > 0 && <Folded hidden={hidden} />}
      {sentence !== undefined && (
        <Under first={lines.length === 0}>
          <text {...FILL} attributes={DIM}>
            {sentence}
          </text>
        </Under>
      )}
    </box>
  );
}

/**
 * One of chord's commands and what it reported, as Claude Code draws its
 * own: the command as typed, then the rows under `⎿`, labels dim.
 */
function Report({
  command,
  rows,
}: {
  command: string;
  rows: readonly ReportRow[];
}) {
  return (
    <box marginTop={1} flexShrink={0}>
      <box flexDirection='row'>
        <Gutter dimColor>›</Gutter>
        <text {...FILL}>/{command}</text>
      </box>
      {rows.map((row, index) => (
        <Under key={index} first={index === 0}>
          {row.label !== undefined && (
            <box flexDirection='row' flexShrink={0}>
              <text {...TEXT} attributes={DIM}>
                {row.label}
              </text>
            </box>
          )}
          <text {...FILL}>{row.text}</text>
        </Under>
      ))}
    </box>
  );
}

/**
 * A change one of chord's commands made, as a report is drawn: the command
 * as typed, then one dim line under `⎿`. A refusal is the red error line.
 */
function Note({
  command,
  text,
  failed,
}: {
  command: string;
  text: string;
  failed: boolean;
}) {
  const { error } = useColours();

  return (
    <box marginTop={1} flexShrink={0}>
      <box flexDirection='row'>
        <Gutter dimColor>›</Gutter>
        <text {...FILL}>/{command}</text>
      </box>
      {failed ? (
        <box flexDirection='row'>
          <Gutter {...paint(error)}>⏺</Gutter>
          <text {...FILL} {...fg(error)}>
            {text}
          </text>
        </box>
      ) : (
        <Under first>
          <text {...FILL} attributes={DIM}>
            {text}
          </text>
        </Under>
      )}
    </box>
  );
}

/**
 * A bash-mode command as Claude Code draws one: `!` and the command, then
 * what it wrote under `⎿`, stderr in red, and how it ended when that is news.
 * Lines are cut at the edge, as a tool call's are.
 */
function Shell({ run, expanded }: { run: ShellRun; expanded: boolean }) {
  const { lines, hidden, note } = shellView(
    run,
    expanded,
    useHintKey('chat:cancel'),
  );
  const { bash, error } = useColours();
  const selectable = useSelectable();

  return (
    <box marginTop={1} flexShrink={0}>
      <box flexDirection='row'>
        <Gutter {...paint(bash)}>!</Gutter>
        <text {...CUT} {...selectable}>
          {run.command}
        </text>
      </box>
      {lines.map((line, index) => (
        <Under key={index} first={index === 0}>
          <text
            {...CUT}
            {...selectable}
            {...(line.stream === 'stderr' ? fg(error) : {})}
          >
            {line.text}
          </text>
        </Under>
      ))}
      {hidden > 0 && <Folded hidden={hidden} />}
      {note && (
        <Under first={lines.length === 0}>
          <text {...CUT} {...(note.failed ? fg(error) : { attributes: DIM })}>
            {note.text}
          </text>
        </Under>
      )}
    </box>
  );
}

/**
 * A reply as markdown, laid out by markdansi to the width it is drawn in;
 * rendered again only when the text or the width changes. It takes the rest
 * of its row, so its texts are measured whole (`FILL`).
 */
function Reply({ text, width }: { text: string; width: number }) {
  const colours = useColours();
  const blocks = useMemo(
    // An agent's own escapes are text, not styling chord answers for.
    () => markdown(stripAnsi(text), width, undefined, colours),
    [text, width, colours],
  );
  const selectable = useSelectable();

  return (
    <box gap={1} flexGrow={1}>
      {blocks.map((block, index) =>
        block.quote ? (
          <box
            key={index}
            flexDirection='row'
            border={['left']}
            borderStyle='single'
            borderColor={DIM_BORDER}
            paddingLeft={QUOTE_INSET - 1}
          >
            <text {...FILL} {...selectable}>
              <Ansi text={block.text} />
            </text>
          </box>
        ) : (
          <text key={index} {...TEXT} {...selectable}>
            <Ansi text={block.text} />
          </text>
        ),
      )}
    </box>
  );
}

/**
 * A compaction: `✻ Compacting conversation…` while it runs outside a turn,
 * as no spinner is there to say it, then how it ended hung under what asked
 * for it, and in ctrl+o's view the summary the agent kept under that.
 */
function CompactionRecord({
  compaction,
  expanded,
  width,
}: {
  compaction: Compaction;
  expanded: boolean;
  width: number;
}) {
  const line = compactionLine(
    compaction,
    expanded,
    useHintKey('app:toggleTranscript'),
  );
  const { accent } = useColours();
  const summary = compaction.summary.trim();

  if (line.tone === 'running') {
    return (
      <box flexDirection='row' marginTop={1} flexShrink={0}>
        <Gutter {...paint(accent)}>✻</Gutter>
        <text {...FILL} {...fg(accent)}>
          {line.text}
        </text>
      </box>
    );
  }

  return (
    <box flexShrink={0}>
      <Outcome text={line.text} failed={line.tone === 'failed'} />
      {expanded && summary !== '' && (
        <box flexDirection='row' paddingLeft={5}>
          <Reply text={summary} width={Math.max(width - 5, 1)} />
        </box>
      )}
    </box>
  );
}

/**
 * The team part a lead or member got ahead of its first message: one dim
 * line, `⏺ bugfix's instructions for tester · 41 lines (ctrl+o to expand)`,
 * so the person sees that it went in without its lines in the way; ctrl+o
 * shows them.
 */
function TeamPartLine({
  part,
  expanded,
}: {
  part: TeamPart;
  expanded: boolean;
}) {
  const key = useHintKey('app:toggleTranscript');
  const selectable = useSelectable();

  return (
    <box marginTop={1} flexShrink={0}>
      <box flexDirection='row'>
        <Gutter dimColor>⏺</Gutter>
        <text {...FILL} attributes={DIM}>
          {teamPartLine(part, expanded, key)}
        </text>
      </box>
      {expanded && (
        <box flexDirection='row' paddingLeft={2}>
          <text {...FILL} {...selectable} attributes={DIM}>
            <Ansi text={part.text} />
          </text>
        </box>
      )}
    </box>
  );
}

/**
 * Claude Code's ∴: the thought folded to one line until ctrl+o. Like Claude
 * Code it names no key; the shortcuts panel does.
 */
function Thought({ text, expanded }: { text: string; expanded: boolean }) {
  const selectable = useSelectable();

  return (
    <box marginTop={1} flexShrink={0}>
      <box flexDirection='row'>
        <Gutter dimColor>∴</Gutter>
        <text {...FILL} attributes={DIM | TextAttributes.ITALIC}>
          Thinking…
        </text>
      </box>
      {expanded && (
        <box flexDirection='row' paddingLeft={2}>
          <text
            {...FILL}
            {...selectable}
            attributes={DIM | TextAttributes.ITALIC}
          >
            <Ansi text={text.trim()} />
          </text>
        </box>
      )}
    </box>
  );
}
