import { useTerminalDimensions } from '@opentui/react';
import { useState } from 'react';
import type { ListedAgent } from '../../agents.ts';
import type { EarlierSession } from '../../session/sessions.ts';
import { bound, type Keymap, keystrokeOf } from '../shortcuts/bindings.ts';
import { AgentPicker, ResumePicker } from '../pickers/Pickers.tsx';
import { menuRowLimit } from '../prompt/commands.ts';
import type { Palette } from '../theme/theme.ts';
import { Colours, drawnColours, Keys } from './context.ts';
import { BOLD, DIM, TEXT } from '../theme/text.ts';
import { usePress } from './input.ts';
import { useApp } from './renderer.tsx';

/**
 * The startup agent or resume choice before anything opens: no conversation,
 * status or prompt. The chosen value goes to the existing startup path;
 * cancellation restores the terminal without starting a session.
 */
export function Start(
  props: {
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
  const { directory, colours, keymap } = props;
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
                {props.kind === 'agents'
                  ? directory
                  : `${props.agent} · ${directory}`}
              </text>
            </box>
          </box>
          <box flexGrow={1} />
          {props.kind === 'agents' ? (
            <AgentPicker
              agents={props.agents}
              preferred={props.preferred}
              rows={menuRowLimit(rows)}
              active={!picked}
              onPick={(chosen) => {
                setPicked(true);
                props.onPick(chosen);
              }}
            />
          ) : (
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
          )}
        </box>
      </Keys.Provider>
    </Colours.Provider>
  );
}
