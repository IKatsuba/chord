import process from 'node:process';
import { useTerminalDimensions } from '@opentui/react';
import { useMemo, useState } from 'react';
import type { DefinedServer, Ignored } from '../../mcp.ts';
import type { AgentOption } from '../../session/config.ts';
import type { AgentModels } from '../../session/models.ts';
import type { ResumeEntry } from '../../session/windows.ts';
import { capital } from '../shortcuts/state.ts';
import {
  resumeChoices,
  type ResumePicker as ResumePickerState,
} from './state.ts';
import {
  hintOf,
  paint,
  useCloseHint,
  useColours,
  useHintKey,
} from '../app/context.ts';
import { usePress } from '../app/input.ts';
import {
  type ListedTeam,
  NO_TEAMS,
  teamChoices,
  type TeamListing,
  teamsHint,
  teamsWhere,
} from '../teams/teams.ts';
import type { Choice } from '../dialogs/permission.ts';
import {
  type Background,
  THEME_SAMPLE,
  themeChoices,
  themeName,
  themePickerLayout,
  type ThemeSetting,
} from '../theme/theme.ts';
import { diffView } from '../transcript/tools/diff.ts';
import { DiffRows, Gutter } from '../transcript/tools/Tool.tsx';
import { Ansi } from '../theme/Ansi.tsx';
import {
  BOLD,
  colour as paletteColour,
  CUT,
  DIM,
  DIM_BORDER,
  fg,
  FILL,
  TEXT,
} from '../theme/text.ts';
import {
  chordLine,
  type ChordRow,
  ignoredNote,
  mcpFit,
  mcpRowLimit,
  mcpRows,
} from './mcp.ts';
import {
  choiceKey,
  initialChoice,
  modelChoices,
  openView,
  optionChoices,
  type PickerChoice,
  pickerKey,
  pickerRows,
  sessionChoices,
  tabChoices,
  type TabRow,
  valueChoices,
} from './picker.ts';

/**
 * A picker's frame, a column in a round border in the permission colour, or
 * in the dim border's grey where there is none.
 */
export function borderOf(colour: string | undefined) {
  return {
    border: true,
    borderStyle: 'rounded',
    borderColor: colour === undefined ? DIM_BORDER : paletteColour(colour),
  } as const;
}

/**
 * `/model`: the agent's models, inline above the prompt as the permission
 * prompt is, the one in use marked. The list takes 1–9, ↑/↓, j/k and Enter;
 * Esc is the window's.
 */
export function ModelPicker({
  models,
  rows,
  agent,
  active,
  onPick,
}: {
  models: AgentModels | undefined;
  /** The most models shown at once; a longer list scrolls. */
  rows: number;
  agent: string;
  active: boolean;
  onPick: (id: string) => void;
}) {
  const choices = modelChoices(models);
  const closeHint = useCloseHint();

  return (
    <box
      {...borderOf(useColours().permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
      <text {...TEXT} {...fg(useColours().permission)} attributes={BOLD}>
        Select model
      </text>
      <text {...CUT} attributes={DIM}>
        {choices.length === 0
          ? `${agent} offers no models to choose from.`
          : `Switch ${agent}'s model for this session.`}
      </text>
      {choices.length > 0 && (
        <PickerList
          choices={choices}
          rows={rows}
          active={active}
          onPick={onPick}
        />
      )}
      <box marginTop={1}>
        <text {...TEXT} attributes={DIM}>
          {hintOf(
            choices.length === 0 ? undefined : 'Enter to switch',
            closeHint,
          )}
        </text>
      </box>
    </box>
  );
}

/**
 * `/resume`: this directory's earlier sessions and saved windows, newest
 * first, inline above the prompt as the model picker is; each row says when
 * the session was last used or the window quit, and how it began. ctrl+a
 * lists every directory's, each row naming its directory too. Enter on one
 * resumes it; Esc is the window's. `starting` is `chord --resume` with no
 * id, where nothing is open yet: a pick opens, and Esc quits.
 */
export function ResumePicker({
  picker,
  open,
  rows,
  agent,
  home,
  active,
  starting = false,
  onPick,
}: {
  picker: ResumePickerState;
  /** The tab each session open in the window is in, by its id. */
  open: ReadonlyMap<string, number>;
  /** The most sessions shown at once; a longer list scrolls. */
  rows: number;
  agent: string;
  /** The home directory the rows' directories are shown from. */
  home: string | undefined;
  active: boolean;
  starting?: boolean;
  onPick: (chosen: ResumeEntry) => void;
}) {
  const { everywhere } = picker;
  // Read once: rows that age while the list is open would shift under the
  // highlight.
  const [sessions] = useState(() => resumeChoices(picker));
  const [choices] = useState(() =>
    sessionChoices(
      sessions,
      Date.now(),
      everywhere ? { home } : undefined,
      open,
    ),
  );
  const closeHint = useCloseHint(starting ? 'to quit' : 'to close');
  const scopeKey = useHintKey('select:toggleScope');
  const scopeHint =
    scopeKey === undefined
      ? undefined
      : `${capital(scopeKey)} ${
          everywhere ? 'for this directory' : 'for all directories'
        }`;

  return (
    <box
      {...borderOf(useColours().permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
      <text {...TEXT} {...fg(useColours().permission)} attributes={BOLD}>
        Resume a session
      </text>
      <text {...CUT} attributes={DIM}>
        {starting
          ? `Pick one of ${agent}'s earlier sessions, or a saved window, to open.`
          : `${agent}'s earlier sessions and saved windows in ${
              everywhere ? 'every directory' : 'this directory'
            }.`}
      </text>
      {choices.length === 0 ? (
        <box marginTop={1}>
          <text {...TEXT}>
            No earlier sessions or windows in this directory.
          </text>
        </box>
      ) : (
        <PickerList
          choices={choices}
          rows={rows}
          active={active}
          onPick={(value) => {
            const chosen = sessions[Number(value)];

            if (chosen) {
              onPick(chosen);
            }
          }}
        />
      )}
      <box marginTop={1}>
        <text {...TEXT} attributes={DIM}>
          {hintOf(
            choices.length === 0 ? undefined : 'Enter to resume',
            scopeHint,
            closeHint,
          )}
        </text>
      </box>
    </box>
  );
}

/**
 * `/team`: the teams saved for this project and every project, inline above
 * the prompt as `/resume`'s list is: each with its size and runtimes, where
 * it is saved, whether it runs in this window and its description, a broken
 * file with its problem. Enter on one hands it to `onPick`; Esc is the
 * window's.
 */
export function TeamsPicker({
  listing,
  rows,
  columns,
  active,
  onPick,
}: {
  listing: TeamListing;
  /** The most teams shown at once; a longer list scrolls. */
  rows: number;
  columns: number;
  active: boolean;
  onPick: (found: ListedTeam) => void;
}) {
  // Read once: a running time that ticks would shift the rows under the
  // highlight.
  const [choices] = useState(() =>
    teamChoices(listing.teams, listing.runs, Date.now(), columns),
  );
  const [highlighted, setHighlighted] = useState(
    () => choices[initialChoice(choices)]?.value,
  );
  const closeHint = useCloseHint();

  return (
    <box
      {...borderOf(useColours().permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
      <text {...TEXT} {...fg(useColours().permission)} attributes={BOLD}>
        Teams
      </text>
      <text {...TEXT} attributes={DIM}>
        {teamsWhere(listing.dirs, columns)}
      </text>
      {choices.length === 0 ? (
        <box marginTop={1}>
          <text {...TEXT}>{NO_TEAMS}</text>
        </box>
      ) : (
        <PickerList
          choices={choices}
          rows={rows}
          active={active}
          onMove={setHighlighted}
          onPick={(name) => {
            const found = listing.teams.find((each) => each.name === name);

            if (found) {
              onPick(found);
            }
          }}
        />
      )}
      <box marginTop={1}>
        <text {...CUT} attributes={DIM}>
          {hintOf(
            ...teamsHint(
              listing.teams.find(({ name }) => name === highlighted),
              columns,
            ),
            closeHint,
          )}
        </text>
      </box>
    </box>
  );
}

/**
 * `ctrl+x w`: the sessions open in the window, in tab order, inline above the
 * prompt as the other pickers are; each row says its agent, where it stands
 * and how it began. Enter or a digit puts that one in front; Esc is the
 * window's. It closes nothing, as closing has a key of its own.
 */
export function SessionsPicker({
  tabs,
  start,
  directory,
  rows,
  active,
  onPick,
}: {
  tabs: readonly TabRow[];
  /** The tab the highlight starts on. */
  start: number | undefined;
  /** The window's directory, as the header shows it. */
  directory: string;
  /** The most sessions shown at once. */
  rows: number;
  active: boolean;
  onPick: (number: number) => void;
}) {
  const choices = tabChoices(tabs, Date.now(), start);
  const closeHint = useCloseHint();

  return (
    <box
      {...borderOf(useColours().permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
      <text {...CUT} {...fg(useColours().permission)} attributes={BOLD}>
        {`Sessions in ${directory}`}
      </text>
      <PickerList
        choices={choices}
        rows={rows}
        active={active}
        onPick={(value) => onPick(Number(value))}
      />
      <box marginTop={1}>
        <text {...TEXT} attributes={DIM}>
          {hintOf(
            'Enter to go',
            choices.length > 1 ? `1–${choices.length} to pick` : '1 to pick',
            closeHint,
          )}
        </text>
      </box>
    </box>
  );
}

/**
 * `/config`: the agent's options other than its mode and model, inline above
 * the prompt as the model picker is, each with the value it is set to. Enter
 * on one lists its values, the one in use marked, and Enter on a value sets
 * it; Esc is the window's, and backs out one level.
 */
export function ConfigPicker({
  options,
  option,
  from,
  rows,
  agent,
  active,
  onOpen,
  onPick,
}: {
  options: readonly AgentOption[];
  /** The option whose values are listed; none on the list of options. */
  option: AgentOption | undefined;
  /** On the list of options, the one Esc came back from. */
  from: string | undefined;
  /** The most rows shown at once; a longer list scrolls. */
  rows: number;
  agent: string;
  active: boolean;
  onOpen: (id: string) => void;
  onPick: (option: AgentOption, value: string) => void;
}) {
  const choices = option ? valueChoices(option) : optionChoices(options, from);
  const back = useCloseHint('to go back');
  const close = useCloseHint();
  const hint = option
    ? hintOf('Enter to set', back)
    : hintOf(choices.length === 0 ? undefined : 'Enter to choose', close);

  return (
    <box
      {...borderOf(useColours().permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
      <text {...TEXT} {...fg(useColours().permission)} attributes={BOLD}>
        {option ? (
          <>
            {'Set '}
            <Ansi text={option.name} />
          </>
        ) : (
          'Settings'
        )}
      </text>
      <text {...CUT} attributes={DIM}>
        {option ? (
          <>
            {`Choose ${agent}'s `}
            <Ansi text={option.name} />
            {' for this session.'}
          </>
        ) : choices.length === 0 ? (
          `${agent} has no settings other than its model and mode.`
        ) : (
          `Change ${agent}'s settings for this session.`
        )}
      </text>
      {choices.length > 0 && (
        <PickerList
          // A fresh list, and highlight, for each level.
          key={option?.id ?? ''}
          choices={choices}
          rows={rows}
          active={active}
          onPick={(value) => (option ? onPick(option, value) : onOpen(value))}
        />
      )}
      <box marginTop={1}>
        <text {...TEXT} attributes={DIM}>
          {hint}
        </text>
      </box>
    </box>
  );
}

/**
 * `/theme`: chord's themes, inline above the prompt as the model picker is,
 * the one in use marked, and a few rows of a diff under them. Each move
 * previews the highlighted theme across the whole window; Enter keeps it and
 * Esc, the window's, goes back to the one in use.
 */
export function ThemePicker({
  current,
  background,
  windowRows,
  active,
  onMove,
  onPick,
}: {
  current: ThemeSetting;
  background: Background;
  /** The window's height, which decides how much of the picker fits. */
  windowRows: number;
  active: boolean;
  onMove: (theme: ThemeSetting) => void;
  onPick: (theme: ThemeSetting) => void;
}) {
  const choices = themeChoices(current, background);
  const layout = themePickerLayout(windowRows);
  const back = useCloseHint('to go back');
  const { permission } = useColours();
  // The sample's code is coloured in the theme previewed, as its rows are.
  const { code } = useColours();
  const sample = useMemo(() => {
    const view = diffView(
      THEME_SAMPLE.path,
      THEME_SAMPLE.old,
      THEME_SAMPLE.new,
      true,
      code,
    );

    return { ...view, rows: view.rows.slice(0, 3) };
  }, [code]);

  return (
    <box
      {...borderOf(permission)}
      paddingX={1}
      marginTop={layout.gap ? 1 : 0}
      flexShrink={0}
    >
      <text {...TEXT} {...fg(permission)} attributes={BOLD}>
        Theme
      </text>
      <text {...CUT} attributes={DIM}>
        {process.env['NO_COLOR']
          ? 'NO_COLOR is set, so chord draws no colour.'
          : 'Choose the colours that read best on this terminal.'}
      </text>
      <PickerList
        choices={choices}
        rows={layout.choices}
        active={active}
        onMove={(value) => onMove(value as ThemeSetting)}
        onPick={(value) => onPick(value as ThemeSetting)}
      />
      {layout.sample && (
        <box marginTop={1} paddingLeft={1} flexDirection='column'>
          <DiffRows view={sample} />
        </box>
      )}
      <box marginTop={1}>
        <text {...CUT} attributes={DIM}>
          {hintOf(
            '↑↓ to preview',
            'Enter to keep',
            back && `${back} to ${themeName(current)}`,
          )}
        </text>
      </box>
    </box>
  );
}

/**
 * `/mcp`: the MCP servers chord passed to the agent, in the pickers' frame
 * but with nothing to pick. Whether the agent reached each one ACP does not
 * say, so the panel says that rather than show a state it cannot know.
 */
export function McpPanel({
  servers: users,
  ignored = [],
  agent,
  windowRows,
  chord,
}: {
  servers: readonly DefinedServer[];
  /** chord's own server, listed first; none where the window has none. */
  chord?: ChordRow;
  /** What the files lost, said under the list so a missing server is found. */
  ignored?: readonly Ignored[];
  agent: string;
  /** The window's height, which decides how many servers are listed. */
  windowRows: number;
}) {
  const { permission } = useColours();
  const { width: columns } = useTerminalDimensions();
  const servers = chord === undefined ? users : [chord.server, ...users];
  // The frame's border and padding take two columns each side.
  const { headings, rows } = mcpRows(servers, columns - 4);
  const { shown, more } = mcpFit(rows, mcpRowLimit(windowRows));
  const lost = ignoredNote(ignored);
  const closeHint = useCloseHint();

  return (
    <box {...borderOf(permission)} paddingX={1} marginTop={1} flexShrink={0}>
      <text {...TEXT} {...fg(permission)} attributes={BOLD}>
        MCP servers
      </text>
      {servers.length === 0 ? (
        <text {...TEXT} attributes={DIM}>
          {lost === undefined
            ? `No MCP servers were passed to ${agent}: none are defined in .mcp.json or in chord's settings files.`
            : `No MCP servers were passed to ${agent}.`}
        </text>
      ) : (
        <>
          <text {...TEXT} attributes={DIM}>
            {`chord passed these to ${agent} when the session started. ACP does not say whether ${agent} connected to them.`}
          </text>
          <box marginTop={1} flexDirection='column'>
            <text {...CUT} attributes={DIM}>
              {headings}
            </text>
            {shown.flat().map((line, index) => (
              <text key={index} {...CUT}>
                {line}
              </text>
            ))}
            {more > 0 && (
              <text {...TEXT} attributes={DIM}>{`… +${more} more`}</text>
            )}
          </box>
        </>
      )}
      {chord !== undefined && (
        <box marginTop={1}>
          <text {...TEXT} attributes={DIM}>
            {chordLine(chord, agent)}
          </text>
        </box>
      )}
      {lost !== undefined && (
        <box marginTop={servers.length === 0 ? 0 : 1}>
          <text {...TEXT} attributes={DIM}>
            {lost}
          </text>
        </box>
      )}
      {closeHint !== undefined && (
        <box marginTop={1}>
          <text {...TEXT} attributes={DIM}>
            {closeHint}
          </text>
        </box>
      )}
    </box>
  );
}

/**
 * A picker's choices, numbered by their place in the whole list, each cut at
 * the edge. A list longer than `rows` shows a window onto it that slides
 * without going round, `↑` and `↓` before the number where choices are
 * hidden that way, and how many are hidden under it, as Claude Code's picker
 * does.
 */
function PickerList({
  choices,
  rows,
  active,
  onPick,
  onMove,
}: {
  choices: readonly PickerChoice[];
  rows: number;
  active: boolean;
  onPick: (id: string) => void;
  /** Hears the choice each move highlights. */
  onMove?: (id: string) => void;
}) {
  const [view, setView] = useState(() => openView(choices, rows));
  const shown = pickerRows(choices, view, rows);
  const { permission } = useColours();

  usePress(
    (input, key) => {
      const step = pickerKey(view, choices.length, rows, input, key);

      if (step?.type === 'move') {
        setView(step.view);

        const choice = choices[step.view.highlighted];

        if (choice) {
          onMove?.(choice.value);
        }
      } else if (step?.type === 'pick') {
        const choice = choices[step.index];

        if (choice) {
          onPick(choice.value);
        }
      }
    },
    { isActive: active },
  );

  return (
    <box marginTop={1} flexDirection='column'>
      {shown.rows.map(({ choice, highlighted, number, edge }) => (
        <box key={choice.value} flexDirection='row'>
          <ChoiceIndicator isSelected={highlighted} />
          {edge !== undefined && <Gutter dimColor>{edge}</Gutter>}
          <text {...CUT} {...(highlighted ? fg(permission) : {})}>
            {`${number} `}
            <Ansi text={choice.label} />
          </text>
        </box>
      ))}
      {shown.hidden > 0 && (
        <box paddingLeft={4}>
          <text {...TEXT} attributes={DIM}>{`… +${shown.hidden} more`}</text>
        </box>
      )}
    </box>
  );
}

/**
 * A numbered list, the highlight in the permission colour, keyed as
 * ink-select-input was, which it was first drawn with: ↑ and ↓ (or k and j)
 * move the highlight round, Enter picks it, and a choice's number picks that
 * one. Shift+arrows are the window's.
 */
export function ChoiceList({
  choices,
  active,
  onSelect,
}: {
  choices: readonly Choice[];
  active: boolean;
  onSelect: (value: string) => void;
}) {
  const [highlighted, setHighlighted] = useState(0);

  usePress(
    (input, key) => {
      const picked = choiceKey(input, key, highlighted, choices.length);

      if (picked !== undefined && 'move' in picked) {
        setHighlighted(picked.move);
      } else if (picked !== undefined) {
        onSelect(choices[picked.pick]!.value);
      }
    },
    { isActive: active },
  );

  return (
    <box flexDirection='column'>
      {choices.map((choice, index) => (
        <box key={choice.value} flexDirection='row'>
          <ChoiceIndicator isSelected={index === highlighted} />
          <ChoiceLabel
            isSelected={index === highlighted}
            label={choice.label}
          />
        </box>
      ))}
    </box>
  );
}

function ChoiceIndicator({ isSelected }: { isSelected?: boolean }) {
  return (
    <Gutter {...paint(useColours().permission)}>
      {isSelected ? '❯' : ' '}
    </Gutter>
  );
}

function ChoiceLabel({
  isSelected,
  label,
}: {
  isSelected?: boolean;
  label: string;
}) {
  const { permission } = useColours();

  return (
    <text {...FILL} {...(isSelected ? fg(permission) : {})}>
      <Ansi text={label} />
    </text>
  );
}
