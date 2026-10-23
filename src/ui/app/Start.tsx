import { useTerminalDimensions } from '@opentui/react';
import { useState } from 'react';
import type { EarlierSession } from '../../session/sessions.ts';
import { bound, type Keymap, keystrokeOf } from '../shortcuts/bindings.ts';
import { ResumePicker } from '../pickers/Pickers.tsx';
import { menuRowLimit } from '../prompt/commands.ts';
import type { Palette } from '../theme/theme.ts';
import { Colours, drawnColours, Keys } from './context.ts';
import { BOLD, DIM, TEXT } from '../theme/text.ts';
import { usePress } from './input.ts';
import { useApp } from './renderer.tsx';

/**
 * `chord --resume` with no id: the resume picker before any agent starts, as
 * `claude --resume` opens on its own. Nothing is open, so there is no prompt
 * box and no status line to report on; the pick decides the agent and the
 * directory, and `onPick` hears it. Esc quits, as nothing
 * the person asked for has started; `onPick` hears none then.
 */
export function Start({
  agent,
  directory,
  home,
  cwd,
  sessions,
  colours,
  keymap,
  onPick,
}: {
  agent: string;
  /** The working directory as the header shows it. */
  directory: string;
  home: string | undefined;
  /** The working directory, resolved, which the narrow scope keeps to. */
  cwd: string;
  sessions: readonly EarlierSession[];
  colours: Palette;
  keymap: Keymap;
  onPick: (chosen: EarlierSession | undefined) => void;
}) {
  const { exit } = useApp();
  const { width: columns, height: rows } = useTerminalDimensions();

  drawnColours.current = colours;

  const [everywhere, setEverywhere] = useState(false);
  const [picked, setPicked] = useState(false);
  const pick = (chosen: EarlierSession | undefined) => {
    setPicked(true);
    onPick(chosen);

    if (chosen === undefined) {
      exit();
    }
  };

  usePress(
    (input, key) => {
      const pressed = keystrokeOf(input, key);
      const sequence = pressed === undefined ? undefined : [pressed];

      if (
        bound(keymap, 'select:cancel', sequence) ||
        (key.ctrl && input === 'c')
      ) {
        pick(undefined);
      } else if (bound(keymap, 'select:toggleScope', sequence)) {
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
                {`${agent} · ${directory}`}
              </text>
            </box>
          </box>
          <box flexGrow={1} />
          <ResumePicker
            // A fresh list for each scope, its highlight on the first row.
            key={String(everywhere)}
            picker={{ sessions, cwd, everywhere }}
            open={new Map()}
            rows={menuRowLimit(rows)}
            agent={agent}
            home={home}
            active={!picked}
            starting
            onPick={pick}
          />
        </box>
      </Keys.Provider>
    </Colours.Provider>
  );
}
