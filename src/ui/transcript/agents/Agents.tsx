import { TextAttributes } from '@opentui/core';
import { memo, type ReactNode, useContext } from 'react';
import type {
  PermissionWait,
  Subagent,
  TurnState,
} from '../../../session/transcript/types.ts';
import {
  AgentColours,
  ChordServerName,
  useColours,
  useHintKey,
  useSelectable,
} from '../../app/context.ts';
import type { ArrowTone } from '../message.ts';
import { PlanRecord } from '../../plan/Plan.tsx';
import { Ansi } from '../../theme/Ansi.tsx';
import { CUT, DIM, DIM_BORDER, fg, FILL, TEXT } from '../../theme/text.ts';
import { TranscriptEntry } from '../Transcript.tsx';
import type { Headline } from '../tools/tools.ts';
import {
  Gutter,
  HeadlineText,
  Outcome,
  Tool,
  ToolMarker,
  Under,
} from '../tools/Tool.tsx';
import { agentTarget } from '../targets.ts';
import {
  agentHeadline,
  agentTone,
  blockFold,
  endedLine,
  endingOf,
  groupHeader,
  groupRow,
  rowLine,
  WAITING_NOTE,
  WORK_LOST_NOTE,
  type WorkLine,
  workOf,
} from './subagents.ts';

/** The permission requests the turn waits on, for the calls they are about. */
function waitsOf(turn: TurnState): readonly PermissionWait[] {
  return turn.status === 'awaiting_permission' ? turn.permissions : [];
}

interface AgentsProps {
  agents: readonly Subagent[];
  turn: TurnState;
  agent: string;
  open: boolean;
  /** Cells beside the gutter. */
  width: number;
}

/**
 * Subagents spawned back to back, where the first spawn came among the
 * parent's entries: one alone as a block shaped like a tool call, several as
 * one tree. With `open`, as in ctrl+o's view, each shows its task and its
 * whole work, whose own subagents stay folded.
 */
export const Agents = memo(function Agents({
  agents,
  turn,
  agent,
  open,
  width,
}: AgentsProps) {
  return agents.length === 1 ? (
    <AgentBlock
      subagent={agents[0]!}
      turn={turn}
      agent={agent}
      open={open}
      width={width}
    />
  ) : (
    <AgentGroup
      agents={agents}
      turn={turn}
      agent={agent}
      open={open}
      width={width}
    />
  );
}, sameAgents);

/**
 * Props alike as a memo compares them, but the group as its subagents: the
 * window slices it out of the transcript afresh on every draw.
 */
function sameAgents(
  { agents: before, ...rest }: AgentsProps,
  { agents: after, ...others }: AgentsProps,
): boolean {
  const keys = Object.keys(rest) as (keyof typeof rest)[];

  return (
    before.length === after.length &&
    before.every((subagent, at) => subagent === after[at]) &&
    keys.every((key) => Object.is(rest[key], others[key]))
  );
}

/**
 * `Read(src/main.tsx)`, its name bold, as a call's headline is drawn; a
 * message sent, `→ to @main`, its arrow drawn as `arrow` says and both in the
 * recipient's colour, as the row it opens to. A function rather than a
 * component, so the line's `<text>` holds every run and cuts them as one.
 */
function headlineText(
  { name, arg, tag, note, sent }: Headline,
  { error, agents }: HeadlineColours,
  arrow: ArrowTone = 'plain',
): ReactNode {
  const recipient = agents[name];

  return (
    <>
      {sent && (
        <>
          <span
            {...(arrow === 'dim'
              ? { attributes: DIM }
              : fg(arrow === 'failed' ? error : recipient))}
          >
            →
          </span>{' '}
          <span attributes={DIM}>to </span>
        </>
      )}
      <span
        attributes={TextAttributes.BOLD}
        {...fg(sent ? recipient : undefined)}
      >
        <Ansi text={sent ? `@${name}` : name} />
      </span>
      {tag !== undefined && <span attributes={DIM}>{tag}</span>}
      {arg !== undefined && <Ansi text={`(${arg})`} />}
      {note !== undefined && (
        <span attributes={DIM}>
          <Ansi text={note} />
        </span>
      )}
    </>
  );
}

/** What a headline is coloured by: the error colour and each agent's. */
interface HeadlineColours {
  readonly error: string | undefined;
  readonly agents: Readonly<Record<string, string>>;
}

function useHeadlineColours(): HeadlineColours {
  return { error: useColours().error, agents: useContext(AgentColours) };
}

/** A call of a subagent's, or a subagent it started, as one line of its work. */
function WorkLineText({ line }: { line: WorkLine }) {
  const colours = useHeadlineColours();

  return (
    <text {...FILL} {...(line.failed ? fg(colours.error) : {})}>
      {headlineText(line.headline, colours, line.arrow || undefined)}
      {line.waiting && <span attributes={DIM}>{WAITING_NOTE}</span>}
    </text>
  );
}

/**
 * `⏺ Agent(<title>)`: folded, its latest calls under `⎿` while it runs and
 * how it ended once it has; open, its task, its work, then its ending.
 */
function AgentBlock({
  subagent,
  turn,
  agent,
  open,
  width,
}: {
  subagent: Subagent;
  turn: TurnState;
  agent: string;
  open: boolean;
  width: number;
}) {
  const fold = blockFold(subagent, waitsOf(turn), useContext(ChordServerName));
  const key = useHintKey('app:toggleTranscript');
  const ended = endedLine(subagent);

  return (
    <box id={agentTarget(subagent.id)} marginTop={1} flexShrink={0}>
      <box flexDirection='row'>
        <ToolMarker tone={agentTone(subagent.state)} />
        <HeadlineText line={agentHeadline(subagent)} width={width} />
      </box>
      {open ? (
        <>
          <Task subagent={subagent} />
          <box paddingLeft={5}>
            <Work
              subagent={subagent}
              turn={turn}
              agent={agent}
              width={Math.max(width - 5, 1)}
            />
          </box>
          {ended && <Outcome text={ended.text} failed={ended.failed} />}
        </>
      ) : fold.kind === 'ended' ? (
        <Outcome text={fold.text} failed={fold.failed} />
      ) : fold.kind === 'starting' ? (
        <Outcome text='Initializing…' />
      ) : (
        <>
          {fold.lines.map((line, index) => (
            <Under key={index} first={index === 0}>
              <WorkLineText line={line} />
            </Under>
          ))}
          {fold.more > 0 && (
            <box flexDirection='row' paddingLeft={5}>
              <text {...CUT} attributes={DIM}>
                {`+${fold.more} more tool ${
                  fold.more === 1 ? 'use' : 'uses'
                }${key === undefined ? '' : ` (${key} to expand)`}`}
              </text>
            </box>
          )}
        </>
      )}
    </box>
  );
}

/** What a subagent was asked to do, in full, under its `⎿`. */
function Task({ subagent }: { subagent: Subagent }) {
  const task = subagent.description?.trim();
  const selectable = useSelectable();

  return task ? (
    <Under first>
      <text {...FILL} {...selectable}>
        <Ansi text={task} />
      </text>
    </Under>
  ) : null;
}

/**
 * Several subagents spawned together: `Running 2 agents…`, then a row for
 * each behind `├─` or `└─`, and under it its current call or its ending; open,
 * its task and work instead, a `│` down the side of every child but the last.
 */
function AgentGroup({
  agents,
  turn,
  agent,
  open,
  width,
}: {
  agents: readonly Subagent[];
  turn: TurnState;
  agent: string;
  open: boolean;
  width: number;
}) {
  const header = groupHeader(agents);
  const key = useHintKey('app:toggleTranscript');
  const colours = useHeadlineColours();
  const { error } = colours;
  const waits = waitsOf(turn);
  const chordServer = useContext(ChordServerName);
  const selectable = useSelectable();

  return (
    <box marginTop={1} flexShrink={0}>
      <box flexDirection='row'>
        <ToolMarker tone={header.tone} />
        <text {...CUT}>
          {header.text}
          {!open && key !== undefined && (
            <span attributes={DIM}>{` (${key} to expand)`}</span>
          )}
        </text>
      </box>
      {agents.map((subagent, index) => {
        const last = index === agents.length - 1;
        // The row's glyphs take three cells after the block's two.
        const row = groupRow(subagent, width - 3);
        const line = rowLine(subagent, waits, chordServer);
        // Its counts are on its row, so its ending is the word alone.
        const ending = endingOf(subagent.state);

        return (
          <box key={subagent.id} id={agentTarget(subagent.id)}>
            <box flexDirection='row' paddingLeft={2}>
              <Gutter width={3} dimColor>
                {last ? '└─' : '├─'}
              </Gutter>
              {/* The agent's title, as a lone block's; its counts are chord's. */}
              <text {...CUT} {...selectable}>
                {headlineText(row.headline, colours)}
              </text>
              {row.counts !== undefined && (
                <text {...CUT} attributes={DIM}>
                  {row.counts}
                </text>
              )}
            </box>
            <box
              marginLeft={2}
              {...(last
                ? { paddingLeft: 1 }
                : {
                    border: ['left' as const],
                    borderStyle: 'single' as const,
                    borderColor: DIM_BORDER,
                  })}
            >
              {open ? (
                <>
                  <Task subagent={subagent} />
                  <box paddingLeft={5}>
                    <Work
                      subagent={subagent}
                      turn={turn}
                      agent={agent}
                      width={Math.max(width - 8, 1)}
                    />
                  </box>
                  {ending && (
                    <Under first>
                      <text
                        {...FILL}
                        {...(ending.failed ? fg(error) : { attributes: DIM })}
                      >
                        {ending.word}
                      </text>
                    </Under>
                  )}
                </>
              ) : (
                <Under first>
                  {line.kind === 'call' ? (
                    <WorkLineText line={line.line} />
                  ) : line.kind === 'starting' ? (
                    <text {...FILL} attributes={DIM}>
                      Initializing…
                    </text>
                  ) : (
                    <text
                      {...FILL}
                      {...(line.ending.failed
                        ? fg(error)
                        : { attributes: DIM })}
                    >
                      {line.ending.word}
                    </text>
                  )}
                </Under>
              )}
            </box>
          </box>
        );
      })}
    </box>
  );
}

/**
 * A subagent's work as its parent's transcript would draw it, its plan once
 * where it first came; the subagents it started stay folded. Once it has
 * ended, a call it left unfinished waits on nothing. A task whose record has
 * gone says so where its work would be.
 */
function Work({
  subagent,
  turn,
  agent,
  width,
}: {
  subagent: Subagent;
  turn: TurnState;
  agent: string;
  width: number;
}) {
  if (subagent.task?.workLost) {
    return (
      <text {...TEXT} attributes={DIM}>
        {WORK_LOST_NOTE}
      </text>
    );
  }

  return workOf(subagent).map((item, index) =>
    item.kind === 'plan' ? (
      <PlanRecord key={index} entries={item.entries} />
    ) : item.kind === 'agents' ? (
      <Agents
        key={index}
        agents={item.agents}
        turn={turn}
        agent={agent}
        open={false}
        width={width}
      />
    ) : item.entry.kind === 'tool' ? (
      <Tool
        key={index}
        call={item.entry.call}
        expanded
        ended={endingOf(subagent.state) !== undefined}
        width={width}
      />
    ) : (
      <TranscriptEntry
        key={index}
        entry={item.entry}
        turn={turn}
        agent={agent}
        expanded
        width={width}
      />
    ),
  );
}
