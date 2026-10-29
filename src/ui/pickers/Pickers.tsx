import process from 'node:process';
import type { ListedAgent } from '../../agents.ts';
import { useTerminalDimensions } from '@opentui/react';
import { useEffect, useMemo, useRef, useState } from 'react';
import wrapAnsi from 'wrap-ansi';
import type { DefinedServer, Ignored } from '../../mcp.ts';
import { DIMCODE_WORDS, NOTICE_CHOICES } from '../../notices.ts';
import type { AgentOption } from '../../session/config.ts';
import type { AgentModels } from '../../session/models.ts';
import type { EarlierSession } from '../../session/sessions.ts';
import type { HeldBack } from '../../session/servers.ts';
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
  heldNote,
  ignoredNote,
  mcpFit,
  mcpRowLimit,
  mcpRows,
  startingLine,
  withHeldBack,
} from './mcp.ts';
import {
  agentChoices,
  choiceKey,
  initialChoice,
  modelChoices,
  fromFirstLine,
  lineKey,
  linedRows,
  oneLineRows,
  openLineView,
  openView,
  optionChoices,
  type PickerChoice,
  pickerKey,
  pickerLayout,
  pickerRows,
  sessionChoices,
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

/** The catalog before any agent owns the terminal or starts a session. */
export function AgentPicker({
  agents,
  preferred,
  rows,
  active,
  onPick,
}: {
  agents: readonly ListedAgent[];
  preferred: string;
  rows: number;
  active: boolean;
  onPick: (id: string) => void;
}) {
  const choices = agentChoices(agents, preferred);
  const closeHint = useCloseHint('to cancel');

  return (
    <box paddingX={1} flexShrink={0}>
      <text {...TEXT}>Select agent</text>
      {choices.length === 0 ? (
        <box marginTop={1}>
          <text {...TEXT} attributes={DIM}>
            No agents available
          </text>
        </box>
      ) : (
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
            ...(choices.length === 0
              ? []
              : ['↑↓ or j/k to move', 'Enter or 1–9 to select']),
            closeHint,
          )}
        </text>
      </box>
    </box>
  );
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
    <box {...borderOf(useColours().permission)} paddingX={1} flexShrink={0}>
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
 * `/resume`: this directory's earlier sessions, newest first, inline above
 * the prompt as the model picker is; each row says when the session was last
 * used, and how it began. ctrl+a
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
  gap = true,
  onPick,
}: {
  picker: ResumePickerState;
  /** The ids of the sessions open now, as children of this one. */
  open: ReadonlySet<string>;
  /** The most sessions shown at once; a longer list scrolls. */
  rows: number;
  agent: string;
  /** The home directory the rows' directories are shown from. */
  home: string | undefined;
  active: boolean;
  starting?: boolean;
  /** The row above its frame; none where it floats over the transcript. */
  gap?: boolean;
  onPick: (chosen: EarlierSession) => void;
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
      marginTop={gap ? 1 : 0}
      flexShrink={0}
    >
      <text {...TEXT} {...fg(useColours().permission)} attributes={BOLD}>
        Resume a session
      </text>
      <text {...CUT} attributes={DIM}>
        {starting
          ? `Pick one of ${agent}'s earlier sessions to open.`
          : `${agent}'s earlier sessions in ${
              everywhere ? 'every directory' : 'this directory'
            }.`}
      </text>
      {choices.length === 0 ? (
        <box marginTop={1}>
          <text {...TEXT}>No earlier sessions in this directory.</text>
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
    <box {...borderOf(useColours().permission)} paddingX={1} flexShrink={0}>
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
    <box {...borderOf(useColours().permission)} paddingX={1} flexShrink={0}>
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
    <box {...borderOf(permission)} paddingX={1} flexShrink={0}>
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
 * dimcode's one-time notice, in the pickers' frame above the prompt
 * (docs/design/CHD-434.md): what it may start, how to turn that off, and
 * the two answers. It takes the keys while `active`; Esc is the window's,
 * and shows it again next time, as 2 does.
 */
export function NoticeBox({
  columns,
  active,
  onAnswer,
}: {
  /** The window's width; the box takes all of it. */
  columns: number;
  active: boolean;
  /** Whether the person dismissed it for good, or asked to see it again. */
  onAnswer: (dismissed: boolean) => void;
}) {
  const { permission } = useColours();
  const later = useCloseHint('to show it again next time');

  return (
    <box {...borderOf(permission)} paddingX={1} flexShrink={0}>
      <text {...TEXT} {...fg(permission)} attributes={BOLD}>
        {DIMCODE_WORDS.title}
      </text>
      {/* Wrapped at spaces, as the transcript is, so a path or a value a
          person types stays whole on its line; only a word longer than the
          line is broken, where it is drawn. */}
      {DIMCODE_WORDS.paragraphs.map((paragraph) => (
        <box key={paragraph} marginTop={1} flexDirection='column'>
          {wrapAnsi(paragraph, Math.max(columns - 4, 1), { trim: true })
            .split('\n')
            .map((line, index) => (
              <text key={index} {...TEXT}>
                {line}
              </text>
            ))}
        </box>
      ))}
      <PickerList
        choices={NOTICE_CHOICES}
        rows={NOTICE_CHOICES.length}
        active={active}
        onPick={(value) => onAnswer(value === 'dismiss')}
      />
      <box marginTop={1}>
        <text {...CUT} attributes={DIM}>
          {hintOf('Enter to pick', '1–2', '↑↓ to move', later)}
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
  servers: defined,
  ignored = [],
  heldBack = [],
  agent,
  windowRows,
  chord,
  starting = false,
}: {
  servers: readonly DefinedServer[];
  /**
   * Its agent's session not there yet: chord has passed it nothing, so
   * neither a server passed nor one held back can be said (CHD-488).
   */
  starting?: boolean;
  /** The servers its agent was not given, each listed `not passed` (CHD-441). */
  heldBack?: readonly HeldBack[];
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
  const users = withHeldBack(defined, heldBack);
  const servers = chord === undefined ? users : [chord.server, ...users];
  const held = heldNote(heldBack);
  // The frame's border and padding take two columns each side.
  const { headings, rows } = mcpRows(servers, columns - 4);
  const { shown, more } = mcpFit(rows, mcpRowLimit(windowRows));
  const lost = ignoredNote(ignored);
  const closeHint = useCloseHint();

  if (starting) {
    return (
      <box {...borderOf(permission)} paddingX={1} flexShrink={0}>
        <text {...TEXT} {...fg(permission)} attributes={BOLD}>
          MCP servers
        </text>
        <text {...TEXT} attributes={DIM}>
          {startingLine(agent)}
        </text>
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

  return (
    <box {...borderOf(permission)} paddingX={1} flexShrink={0}>
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
            {`chord's MCP servers for ${agent}. ACP does not say whether ${agent} connected to the ones it was passed.`}
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
      {held !== undefined && (
        <box marginTop={1}>
          <text {...TEXT} attributes={DIM}>
            {held}
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
export function PickerList({
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
  const { width: columns } = useTerminalDimensions();
  const lines = pickerLayout(choices, rows, columns);
  const heights = lines?.map((each) => each.length);
  const [view, setView] = useState(() =>
    heights === undefined
      ? openView(choices, rows)
      : openLineView(choices, heights, rows),
  );
  const { permission } = useColours();
  const laidAt = useRef(`${columns}x${rows}`);

  // A resize, of either side, lays the labels out again: the highlighted
  // row shows from its first line (CHD-445).
  useEffect(() => {
    const at = `${columns}x${rows}`;

    if (laidAt.current !== at) {
      laidAt.current = at;

      if (heights !== undefined) {
        setView((was) => fromFirstLine(was, heights, rows));
      }
    }
  }, [columns, heights, rows]);

  // Rows of one line, or labels laid into lines, a row taller than the
  // room read a line a press (docs/design/CHD-445.md).
  const shown =
    lines === undefined
      ? oneLineRows(pickerRows(choices, view, rows))
      : linedRows(choices, lines, view, rows);

  usePress(
    (input, key) => {
      const step =
        heights === undefined
          ? pickerKey(view, choices.length, rows, input, key)
          : lineKey(view, heights, rows, input, key);

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
      {shown.rows.map(({ choice, highlighted, number, lines: drawn }) => (
        <box key={choice.value} flexDirection='column'>
          {drawn.map(({ text, first, edge }, at) => (
            <box key={at} flexDirection='row'>
              <ChoiceIndicator isSelected={highlighted && first} />
              {edge !== undefined && <Gutter dimColor>{edge}</Gutter>}
              {/* Every line of a wrapped label takes the highlight. */}
              <text {...CUT} {...(highlighted ? fg(permission) : {})}>
                {first ? `${number} ` : ' '.repeat(number.length + 1)}
                <Ansi text={text} />
              </text>
            </box>
          ))}
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
 * one. Shift+arrows are the window's. Not `marked`, it shows no highlight,
 * as a list the keys have not gone into yet.
 */
/**
 * What a box keeps of its choices with its agent, and its way out to the
 * agents list (Q194): where the highlight was, and who hears it move.
 */
export interface KeptChoice {
  readonly highlighted?: number | undefined;
  readonly onHighlight?: (highlighted: number) => void;
  readonly onLeave?: (() => void) | undefined;
}

export function ChoiceList({
  choices,
  active,
  marked = true,
  highlighted: kept,
  onHighlight,
  onSelect,
  onLeave,
}: {
  choices: readonly Choice[];
  active: boolean;
  marked?: boolean;
  /** Where the highlight was left, when the box was on screen before. */
  highlighted?: number | undefined;
  /** The highlight moved, for whoever keeps it while the box is away. */
  onHighlight?: (highlighted: number) => void;
  onSelect: (value: string) => void;
  /** ↓ on the last choice, where there is a list of agents to go to. */
  onLeave?: (() => void) | undefined;
}) {
  const [highlighted, setHighlighted] = useState(
    Math.min(kept ?? 0, Math.max(choices.length - 1, 0)),
  );

  usePress(
    (input, key) => {
      const picked = choiceKey(
        input,
        key,
        highlighted,
        choices.length,
        onLeave !== undefined,
      );

      if (picked === undefined) {
        return;
      }

      if ('leave' in picked) {
        onLeave?.();
      } else if ('move' in picked) {
        setHighlighted(picked.move);
        onHighlight?.(picked.move);
      } else {
        onSelect(choices[picked.pick]!.value);
      }
    },
    { isActive: active },
  );

  return (
    <box flexDirection='column'>
      {choices.map((choice, index) => (
        <box key={choice.value} flexDirection='row'>
          <ChoiceIndicator isSelected={marked && index === highlighted} />
          <ChoiceLabel
            isSelected={marked && index === highlighted}
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
