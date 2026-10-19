import { useTerminalDimensions } from '@opentui/react';
import { Fragment, useMemo } from 'react';
import type {
  TeamRunShown,
  TeamShown,
} from '../../session/transcript/types.ts';
import type { Team } from '../../teams.ts';
import { useColours } from '../app/context.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { CUT, DIM, fg, FILL } from '../theme/text.ts';
import { markdown } from '../transcript/markdown.ts';
import { wrapLine } from '../transcript/message.ts';
import {
  agentRows,
  instructionLines,
  proposalBody,
  proposalTable,
} from '../transcript/tools/proposal.ts';
import {
  Folded,
  Gutter,
  TableRow,
  Tool,
  Under,
} from '../transcript/tools/Tool.tsx';
import { runningHeader, runningTable } from './teams.ts';

/** How many of the body's lines `/team show` keeps folded, by the window's rows. */
function keptLines(windowRows: number): number {
  return windowRows >= 30 ? 3 : 1;
}

/**
 * What one `/team` command left: the command as typed, then a run's
 * `Team(…)` row as `run_team`'s call draws it, the team `/team show`
 * found, or a line, a refusal in the error colour.
 */
export function TeamEntry({
  turnId,
  command,
  shown,
  expanded,
  width,
}: {
  turnId: string;
  command: string;
  shown: TeamShown;
  expanded: boolean;
  width: number;
}) {
  const { error } = useColours();
  // The `⎿` and its gutter take five columns.
  const inside = Math.max(width - 5, 1);

  return (
    <box marginTop={1} flexShrink={0}>
      <box flexDirection='row'>
        <Gutter dimColor>›</Gutter>
        <text {...FILL}>{`/${command}`}</text>
      </box>
      {shown.kind === 'ran' && (
        <Tool
          call={{ id: turnId, status: 'completed', chord: shown.call }}
          expanded={expanded}
          ended
          width={width}
        />
      )}
      {shown.kind === 'said' &&
        shown.text
          .split('\n')
          .flatMap((line) => wrapLine(line, inside))
          .map((line, index) => (
            <Under key={index} first={index === 0}>
              <text {...FILL} {...(shown.failed ? fg(error) : {})}>
                <Ansi text={line} />
              </text>
            </Under>
          ))}
      {shown.kind === 'show' &&
        (shown.running === undefined ? (
          <SavedTeam
            name={shown.name}
            file={shown.file}
            team={shown.team}
            expanded={expanded}
            width={inside}
          />
        ) : (
          <RunningTeam
            name={shown.name}
            file={shown.file}
            team={shown.team}
            run={shown.running}
            width={inside}
          />
        ))}
    </box>
  );
}

/**
 * `/team show` of a team that is not running: its file, its description,
 * a row per agent as a proposal draws them, and the body folded, ctrl+o
 * adding the rest and each agent's instructions, wrapped whole.
 */
function SavedTeam({
  name,
  file,
  team,
  expanded,
  width,
}: {
  name: string;
  file: string;
  team: Team;
  expanded: boolean;
  width: number;
}) {
  const colours = useColours();
  const { height: rows } = useTerminalDimensions();
  const blocks = useMemo(
    () => markdown(team.body, width, undefined, colours),
    [team.body, width, colours],
  );
  const { lines, hidden } = proposalBody({
    instructions: instructionLines(team, width),
    blocks: blocks.map((block) => block.text),
    keep: keptLines(rows),
    expanded,
  });

  return (
    <>
      <Under first>
        <text {...CUT}>{`${name} · ${file}`}</text>
      </Under>
      {wrapLine(team.description, width).map((line, index) => (
        <Under key={`d${index}`} first={false}>
          <text {...FILL} attributes={DIM}>
            <Ansi text={line} />
          </text>
        </Under>
      ))}
      <box height={1} flexShrink={1} />
      {proposalTable(agentRows(team), width, false, expanded).map(
        (line, index) => (
          <Under key={`t${index}`} first={false}>
            <TableRow line={line} warning={colours.warning} />
          </Under>
        ),
      )}
      {lines.map((line, index) => (
        <Under key={`b${index}`} first={false}>
          <text {...CUT}>
            <Ansi text={line === '' ? ' ' : line} />
          </text>
        </Under>
      ))}
      {hidden > 0 && <Folded hidden={hidden} />}
    </>
  );
}

/**
 * `/team show` of a running team: how long its run has worked on what, and
 * each of the file's agents with its mode, its state in the list's colours
 * and its latest call or message, as `/team show` caught them.
 */
function RunningTeam({
  name,
  file,
  team,
  run,
  width,
}: {
  name: string;
  file: string;
  team: Team;
  run: TeamRunShown;
  width: number;
}) {
  const colours = useColours();
  const tones = {
    warning: colours.warning,
    error: colours.error,
    success: colours.success,
  };

  return (
    <>
      {runningHeader(run.name === name ? name : run.name, file, run, width).map(
        (line, index) => (
          <Under key={index} first={index === 0}>
            <text {...CUT}>{line}</text>
          </Under>
        ),
      )}
      <box height={1} flexShrink={1} />
      {runningTable(team, run.agents, width).map((line, index) => {
        const {
          text,
          state: [start, end],
          mark,
          under,
          agent,
        } = line;
        const tone = agent.state?.tone;
        const markTone = agent.mark?.tone;
        const [markStart, markEnd] = mark ?? [end, end];

        return (
          <Fragment key={index}>
            <Under first={false}>
              <text {...CUT}>
                <Ansi text={text.slice(0, start)} />
                <span
                  {...(tone === undefined || tone === 'dim'
                    ? { attributes: DIM }
                    : fg(tones[tone]))}
                >
                  <Ansi text={text.slice(start, end)} />
                </span>
                <Ansi text={text.slice(end, markStart)} />
                <span
                  {...(markTone === undefined || markTone === 'dim'
                    ? { attributes: DIM }
                    : fg(tones[markTone]))}
                >
                  <Ansi text={text.slice(markStart, markEnd)} />
                </span>
                <Ansi text={text.slice(markEnd)} />
              </text>
            </Under>
            {under.map((rest, at) => (
              <Under key={at} first={false}>
                <text {...CUT}>
                  <Ansi text={rest} />
                </text>
              </Under>
            ))}
          </Fragment>
        );
      })}
    </>
  );
}
