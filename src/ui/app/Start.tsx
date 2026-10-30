import chalk from 'chalk';
import { useTerminalDimensions } from '@opentui/react';
import { useState } from 'react';
import type { ListedAgent } from '../../agents.ts';
import type { EarlierSession } from '../../session/sessions.ts';
import { markColour } from '../header/header.ts';
import { MARK, SPLASH_MARK } from '../header/mark.ts';
import { Mark } from '../header/Mark.tsx';
import { bound, type Keymap, keystrokeOf } from '../shortcuts/bindings.ts';
import { agentChoices } from '../pickers/picker.ts';
import {
  AgentPicker,
  ResumePicker,
  useAgentHint,
} from '../pickers/Pickers.tsx';
import { menuRowLimit } from '../prompt/commands.ts';
import type { Palette } from '../theme/theme.ts';
import { Colours, drawnColours, Keys, useColours } from './context.ts';
import { BOLD, colour, CUT, DIM, TEXT } from '../theme/text.ts';
import { usePress } from './input.ts';
import { useApp } from './renderer.tsx';
import {
  hintRows,
  startColumn,
  startLayout,
  type StartStep,
  TAGLINE,
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
  preferred,
  active,
  onPick,
}: {
  version: string;
  directory: string;
  agents: readonly ListedAgent[];
  preferred: string;
  active: boolean;
  onPick: (chosen: string) => void;
}) {
  const { width: columns, height: rows } = useTerminalDimensions();
  const listed = agentChoices(agents, preferred).length;
  const hint = useAgentHint(listed > 0);
  const column = startColumn(columns, false);
  const { step, listRows, top } = startLayout({
    columns,
    rows,
    lines: Math.max(listed, 1),
    framed: false,
    // Inside the column's 1-column padding.
    hintRows: hintRows(hint, column - 2),
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
          agents={agents}
          preferred={preferred}
          rows={listRows}
          active={active}
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
  const { width: columns, height: rows } = useTerminalDimensions();

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
            preferred={props.preferred}
            active={!picked}
            onPick={(chosen) => {
              setPicked(true);
              props.onPick(chosen);
            }}
          />
        ) : (
          <box width={columns} height={rows}>
            <box
              flexDirection='row'
              paddingX={1}
              justifyContent='space-between'
              flexShrink={0}
            >
              <text {...TEXT} attributes={BOLD}>
                chord
              </text>
              <box flexShrink={0} marginLeft={2}>
                <text {...TEXT} attributes={DIM}>
                  {`${props.agent} · ${directory}`}
                </text>
              </box>
            </box>
            <box flexGrow={1} />
            <ResumePicker
              key={String(everywhere)}
              picker={{ sessions: props.sessions, cwd: props.cwd, everywhere }}
              open={new Set()}
              rows={menuRowLimit(rows)}
              agent={props.agent}
              home={props.home}
              active={!picked}
              starting
              onPick={(chosen) => {
                setPicked(true);
                props.onPick(chosen);
              }}
            />
          </box>
        )}
      </Keys.Provider>
    </Colours.Provider>
  );
}
