import chalk from 'chalk';
import { useTerminalDimensions } from '@opentui/react';
import { useMemo, useState } from 'react';
import { type ListedAgent, offeredAgents } from '../../agents.ts';
import type { EarlierSession } from '../../session/sessions.ts';
import { markColour } from '../header/header.ts';
import { MARK, SPLASH_MARK } from '../header/mark.ts';
import { Mark } from '../header/Mark.tsx';
import { bound, type Keymap, keystrokeOf } from '../shortcuts/bindings.ts';
import { agentChoices, sessionChoices } from '../pickers/picker.ts';
import {
  AgentPicker,
  ResumePicker,
  useAgentHint,
  useResumeHint,
} from '../pickers/Pickers.tsx';
import { resumeChoices } from '../pickers/state.ts';
import type { Palette } from '../theme/theme.ts';
import { Colours, drawnColours, Keys, useColours } from './context.ts';
import { BOLD, colour, CUT, DIM, TEXT } from '../theme/text.ts';
import { usePress } from './input.ts';
import { useApp } from './renderer.tsx';
import {
  hintRows,
  listLines,
  startColumn,
  startLayout,
  type StartStep,
  TAGLINE,
  unknownNote,
  versionLine,
  wordmarkColours,
} from './start_layout.ts';

/**
 * The page's art and words for its step, all on the window's centre line.
 * Nothing here holds state, so a resize across a step swaps them at once.
 */
function Title({
  step,
  version,
  agent,
  directory,
  columns,
}: {
  step: StartStep;
  version: string;
  agent?: string;
  directory: string;
  columns: number;
}) {
  const { mark: tones } = useColours();
  const room = Math.max(1, columns - 2);
  const words = (width: number) =>
    versionLine({ version, agent, directory, width });

  if (step === 'none') {
    return null;
  }

  if (step === 'line') {
    return (
      <text {...CUT} maxWidth={room} flexShrink={0}>
        <span attributes={BOLD}>chord</span>
        <span attributes={DIM}>{` ${words(room - 'chord '.length)}`}</span>
      </text>
    );
  }

  const full = step === 'full';
  const wordmark = wordmarkColours(markColour(tones, chalk.level));

  return (
    <>
      <box flexDirection='row' flexShrink={0}>
        <box flexShrink={0} marginRight={full ? 3 : 2}>
          <Mark grid={full ? SPLASH_MARK : MARK} />
        </box>
        <box flexShrink={0} justifyContent='center'>
          {wordmark === undefined ? (
            <text {...TEXT} attributes={BOLD}>
              chord
            </text>
          ) : (
            <ascii-font
              text='CHORD'
              font={full ? 'block' : 'tiny'}
              color={wordmark.map((each) => colour(each))}
              selectable={false}
            />
          )}
        </box>
      </box>
      {full && (
        <box marginTop={1} flexShrink={0}>
          <text {...TEXT}>{TAGLINE}</text>
        </box>
      )}
      <text {...CUT} attributes={DIM} maxWidth={room} flexShrink={0}>
        {words(room)}
      </text>
    </>
  );
}

/** The title page around the agent picker. */
function AgentsPage({
  version,
  directory,
  agents,
  offered,
  preferred,
  active,
  onPick,
}: {
  version: string;
  directory: string;
  agents: readonly ListedAgent[];
  offered: readonly string[] | undefined;
  preferred: string;
  active: boolean;
  onPick: (chosen: string) => void;
}) {
  const { width: columns, height: rows } = useTerminalDimensions();
  const { agents: shown, unknown } = offeredAgents(agents, offered);
  const listed = agentChoices(shown, preferred).length;
  const nothingKnown = listed === 0 && unknown.length > 0;
  const hint = useAgentHint(listed > 0);
  const column = startColumn(columns, false);
  const { step, listRows, top, note } = startLayout({
    columns,
    rows,
    // The sentence under `No agents available` is the list's second row.
    lines: nothingKnown ? 2 : Math.max(listed, 1),
    framed: false,
    // Inside the column's 1-column padding.
    hintRows: hintRows(hint, column - 2),
    noteRows: listed > 0 && unknown.length > 0 ? 2 : 0,
  });

  return (
    <box width={columns} height={rows} paddingTop={top} alignItems='center'>
      <Title
        step={step}
        version={version}
        directory={directory}
        columns={columns}
      />
      {/* Keyed so a resize across a step keeps the highlight in its list. */}
      <box
        key='agents'
        width={column}
        marginTop={step === 'none' ? 0 : 1}
        flexShrink={0}
      >
        <AgentPicker
          agents={shown}
          preferred={preferred}
          rows={listRows}
          active={active}
          onPick={onPick}
          nothingKnown={nothingKnown}
          note={note ? unknownNote(unknown, column - 2) : undefined}
        />
      </box>
    </box>
  );
}

/** The title page around the session picker's frame. */
function ResumePage({
  version,
  directory,
  agent,
  home,
  cwd,
  sessions,
  everywhere,
  active,
  onPick,
}: {
  version: string;
  directory: string;
  agent: string;
  home: string | undefined;
  cwd: string;
  sessions: readonly EarlierSession[];
  everywhere: boolean;
  active: boolean;
  onPick: (chosen: EarlierSession) => void;
}) {
  const { width: columns, height: rows } = useTerminalDimensions();
  const column = startColumn(columns, true);
  const picker = { sessions, cwd, everywhere };
  // The scope's own rows, which ctrl+a changes; a resize only lays them out.
  const choices = useMemo(
    () =>
      sessionChoices(
        resumeChoices({ sessions, cwd, everywhere }),
        Date.now(),
        everywhere ? { home } : undefined,
        new Set(),
      ),
    [sessions, cwd, everywhere, home],
  );
  const hint = useResumeHint(choices.length > 0, everywhere, true);
  const { step, listRows, top } = startLayout({
    columns,
    rows,
    lines: listLines(choices, column),
    framed: true,
    // Inside the frame's borders and its 1-column padding.
    hintRows: hintRows(hint, column - 4),
  });

  return (
    <box width={columns} height={rows} paddingTop={top} alignItems='center'>
      <Title
        step={step}
        version={version}
        agent={agent}
        directory={directory}
        columns={columns}
      />
      <box key='resume' width={column} flexShrink={0}>
        <ResumePicker
          key={String(everywhere)}
          picker={picker}
          open={new Set()}
          rows={listRows}
          agent={agent}
          home={home}
          active={active}
          starting
          width={column}
          onPick={onPick}
        />
      </box>
    </box>
  );
}

/**
 * The startup agent or resume choice before anything opens: no conversation,
 * status or prompt. The chosen value goes to the existing startup path;
 * cancellation restores the terminal without starting a session.
 */
export function Start(
  props: {
    /** chord's own, as `--version` prints it. */
    version: string;
    directory: string;
    colours: Palette;
    keymap: Keymap;
  } & (
    | {
        kind: 'agents';
        agents: readonly ListedAgent[];
        /** The `offeredAgents` setting, which picks from `agents`. */
        offered?: readonly string[] | undefined;
        preferred: string;
        onPick: (chosen: string | undefined) => void;
      }
    | {
        kind?: 'resume';
        agent: string;
        home: string | undefined;
        cwd: string;
        sessions: readonly EarlierSession[];
        onPick: (chosen: EarlierSession | undefined) => void;
      }
  ),
) {
  const { version, directory, colours, keymap } = props;
  const { exit } = useApp();

  drawnColours.current = colours;

  const [everywhere, setEverywhere] = useState(false);
  const [picked, setPicked] = useState(false);
  const cancel = () => {
    setPicked(true);
    props.onPick(undefined);
    exit();
  };

  usePress(
    (input, key) => {
      const pressed = keystrokeOf(input, key);
      const sequence = pressed === undefined ? undefined : [pressed];

      if (
        bound(keymap, 'select:cancel', sequence) ||
        (key.ctrl && input === 'c')
      ) {
        cancel();
      } else if (
        props.kind !== 'agents' &&
        bound(keymap, 'select:toggleScope', sequence)
      ) {
        setEverywhere((was) => !was);
      }
    },
    { isActive: !picked },
  );

  return (
    <Colours.Provider value={colours}>
      <Keys.Provider value={keymap}>
        {props.kind === 'agents' ? (
          <AgentsPage
            version={version}
            directory={directory}
            agents={props.agents}
            offered={props.offered}
            preferred={props.preferred}
            active={!picked}
            onPick={(chosen) => {
              setPicked(true);
              props.onPick(chosen);
            }}
          />
        ) : (
          <ResumePage
            version={version}
            directory={directory}
            agent={props.agent}
            home={props.home}
            cwd={props.cwd}
            sessions={props.sessions}
            everywhere={everywhere}
            active={!picked}
            onPick={(chosen) => {
              setPicked(true);
              props.onPick(chosen);
            }}
          />
        )}
      </Keys.Provider>
    </Colours.Provider>
  );
}
