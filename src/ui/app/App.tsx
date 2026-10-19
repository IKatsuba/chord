import { useTerminalDimensions } from '@opentui/react';
import process from 'node:process';
import manifest from '../../../package.json' with { type: 'json' };
import { useEffect, useMemo, useReducer, useRef, useState } from 'react';
import { listFiles } from '../../files.ts';
import type { DefinedServer, Ignored } from '../../mcp.ts';
import { editInEditor, type EditorEnd } from '../../editor.ts';
import {
  type ClipboardReader,
  type ImageFileReader,
  readClipboardImage,
  readImageFile,
} from '../../images.ts';
import { type LinkOpener, openLink } from '../../links.ts';
import type { Notifications } from '../../notify.ts';
import type { OpenSession, Starting } from '../../session/conversation.ts';
import { openSession } from '../../session/session.ts';
import {
  readRecords as readSessionRecords,
  type ResumableTab,
  type Resume,
  type SessionRecord,
} from '../../session/sessions.ts';
import {
  findAgent,
  listAgents,
  type ListedAgent,
  startLine,
} from '../../agents.ts';
import type { ChordServer } from '../../server/server.ts';
import { frontTab, noTabs } from '../../session/tabs.ts';
import { promptLine } from '../../session/record.ts';
import { type EditorMode, homePath } from '../../settings.ts';
import { runShell, type ShellOptions, type ShellProcess } from '../../shell.ts';
import { subagentPath } from '../../session/subagents.ts';
import { agentGroup } from '../transcript/agents/subagents.ts';
import { bashCommand, typedText } from '../prompt/bash.ts';
import { agentItems, menuRowLimit, teamQuery } from '../prompt/commands.ts';
import { pickedDraft } from '../teams/teams.ts';
import { inSpinner } from '../transcript/compaction.ts';
import { emptyHistory, recordedWith, walking } from '../prompt/history.ts';
import { askedPermission } from '../dialogs/permission.ts';
import { DEFAULT_KEYMAP, hintKey, type Keymap } from '../shortcuts/bindings.ts';
import { placeholderBefore } from '../prompt/images.ts';
import { matchFiles, mentionAt } from '../prompt/mentions.ts';
import { planRowLimit } from '../plan/plan.ts';
import { queueRowLimit } from '../prompt/queue.ts';
import { type Cursor, endOf, promptRows } from '../prompt/prompt.ts';
import { matched } from '../prompt/search.ts';
import {
  type AppState,
  frontState,
  initialAppState,
  liveChords,
  pendingBindings,
  reduceApp,
  reduceWindowed,
  windowed,
} from './state.ts';
import { askedInput, betweenAsked, heldBack } from '../dialogs/state.ts';
import { askerParts } from '../dialogs/asker.ts';
import {
  configOption,
  configPickerShown,
  mcpShown,
  modelPickerShown,
  resumePickerShown,
  sessionsPickerShown,
  shownTheme,
  teamsPickerShown,
  themePickerShown,
} from '../pickers/state.ts';
import { commandMenu, fileFinder } from '../prompt/state.ts';
import {
  agentColour,
  type Background,
  paletteOf,
  resolveTheme,
  type ThemeSetting,
} from '../theme/theme.ts';
import { agentsHint, agentsRowLimit, summaryHint } from '../agents/agents.ts';
import { AgentsList, ChildLine } from '../agents/Agents.tsx';
import { SummaryLine } from '../background/Background.tsx';
import {
  BackgroundView,
  backgroundRowLimit,
} from '../background/BackgroundView.tsx';
import { agentsHaveKeys, backgroundShown } from '../background/state.ts';
import { startingVim } from '../prompt/vim.ts';
import { useCommands } from './commands.ts';
import {
  changeSteps,
  emptyPasteSteps,
  type KeyContext,
  awaitedSteps,
  keySteps,
  newerSteps,
  olderSteps,
  type Step,
  submitSteps,
} from './keys.ts';
import { type OpeningTab, type SessionStart, useSessions } from './sessions.ts';
import {
  answerLink,
  useEditor,
  useFiles,
  useMatch,
  useImages,
  useNotify,
  useSelection,
  useShell,
} from './terminal.ts';
import type { Copy } from './selection.ts';
import { useMouse, usePasted, usePress } from './input.ts';
import { Clip } from './Clip.tsx';
import { useMeasured } from './layout.ts';
import { useTimers } from './timers.ts';
import {
  AgentColours,
  ChordServerName,
  COLOUR,
  Colours,
  Keys,
} from './context.ts';
import { ElicitationForm } from '../dialogs/Form.tsx';
import { QuestionBox } from '../dialogs/Questions.tsx';
import { LinkPrompt } from '../dialogs/Link.tsx';
import {
  PermissionPrompt,
  type RequestScroller,
} from '../dialogs/Permission.tsx';
import {
  ConfigPicker,
  McpPanel,
  ModelPicker,
  ResumePicker,
  SessionsPicker,
  TeamsPicker,
  ThemePicker,
} from '../pickers/Pickers.tsx';
import { chordRow } from '../pickers/mcp.ts';
import {
  CommandList,
  FileList,
  PromptInput,
  Queue,
  SearchLine,
} from '../prompt/Prompt.tsx';
import { Shortcuts } from '../shortcuts/Shortcuts.tsx';
import { LeaderLine, StatusLine, Working } from '../status/Status.tsx';
import { Strip } from './Strip.tsx';
import { Plan } from '../plan/Plan.tsx';
import { Agents } from '../transcript/agents/Agents.tsx';
import { firstMounted } from '../transcript/mount.ts';
import { Below, TranscriptEntry } from '../transcript/Transcript.tsx';
import { Failure } from '../transcript/tools/Tool.tsx';
import { Header } from '../header/Header.tsx';
import { Splash } from '../splash/Splash.tsx';
import { splashShown } from '../splash/splash.ts';

export interface AppProps {
  agent: string;
  cwd: string;
  /** Replaces chord's own command for `agent`. */
  agentCommand?: string | string[] | undefined;
  /** The model and mode each session starts on; the agent's by default. */
  starting?: Starting | undefined;
  /**
   * How a session of any agent `/new` names starts, `agent`'s included; none
   * for one chord cannot start. By default `agent` starts on the two above,
   * and any other the registry knows on its own command and the agent's
   * model and mode.
   */
  startupOf?: ((agent: string) => SessionStart | undefined) | undefined;
  /** Said in the transcript before anything else, such as settings problems. */
  warnings?: readonly string[] | undefined;
  /**
   * Where session records are kept, written as each session goes and read by
   * `/resume`; chord's state directory by default.
   */
  stateDir?: string | undefined;
  /** Reads the session records `/resume` offers; the state directory's, by default. */
  readRecords?: (stateDir: string) => Promise<SessionRecord[]>;
  /** How the session is opened; tests pass the fake agent's. */
  open?: OpenSession;
  /**
   * An earlier session to open again; `/clear` starts a new one after it,
   * and `/resume` another earlier one.
   */
  resume?: Resume | undefined;
  /**
   * Earlier sessions to open again in place of `agent`'s one, each in a tab
   * of its own, in order, the first in front, each on its own agent where it
   * works; `cwd` and the settings above are the first's.
   */
  resumes?: readonly OpeningTab[] | undefined;
  /**
   * Which of `resumes` comes to the front, by its index: the tab a window
   * record had in front; the first when not said.
   */
  resumedFront?: number | undefined;
  /**
   * What the status line says once `resumes` are open, such as a window
   * record's tab left out as its session is gone.
   */
  resumedNote?: string | undefined;
  /** The files `@` offers; the working directory's, walked, by default. */
  files?: (cwd: string) => Promise<readonly string[]>;
  /** How the files are matched against what follows `@`; fzf's, by default. */
  match?: typeof matchFiles;
  /** How a bash-mode command runs; the user's shell, by default. */
  shell?: (command: string, options: ShellOptions) => ShellProcess;
  /**
   * ctrl+g's editor, run while the window has given the terminal up; the
   * user's `$VISUAL` or `$EDITOR`, by default.
   */
  editor?: (draft: string) => Promise<EditorEnd>;
  /** ctrl+v's clipboard; the system's, by default. */
  clipboard?: ClipboardReader;
  /**
   * Opens a link an agent asked the person to open, once they chose to; the
   * system's browser, by default.
   */
  openUrl?: LinkOpener;
  /** Reads the image a pasted or typed path names; the file's, by default. */
  readImage?: ImageFileReader;
  /** The home directory a `~/` path starts in; `$HOME`, by default. */
  home?: string | undefined;
  /**
   * Hears, as the window quits, the sessions to resume: each open one a
   * prompt went to, in tab order, and which of them was in front, by its
   * index; the nearest to its left when the one in front had no prompt.
   */
  onQuit?: (sessions: readonly ResumableTab[], front: number) => void;
  /**
   * Hears that the window has its first session up and takes a prompt,
   * which comes a render after the session opens.
   */
  onReady?: () => void;
  /**
   * How the terminal is told chord waits on the person; none by default, and
   * `main.tsx` passes the settings' channel.
   */
  notifications?: Notifications | undefined;
  /** The `theme` setting chord starts on; `auto` by default. */
  theme?: ThemeSetting | undefined;
  /** The terminal's background, as `auto` reads it; dark when unknown. */
  background?: Background | undefined;
  /**
   * Keeps a theme chosen with `/theme` for the next start; `main.tsx` writes
   * it to the user's settings file, which `settingsFile` names as shown.
   */
  saveTheme?: ((theme: ThemeSetting) => Promise<void>) | undefined;
  /** Whether vim mode is on at the start; off by default. */
  vim?: boolean | undefined;
  /** Keeps `/vim`'s choice for the next start, as `saveTheme` keeps a theme. */
  saveEditorMode?: ((mode: EditorMode) => Promise<void>) | undefined;
  settingsFile?: string | undefined;
  /**
   * The MCP servers every session gets, each with its file as the window
   * shows paths; `/mcp` lists them. None by default.
   */
  mcpServers?: readonly DefinedServer[] | undefined;
  /** What the files defined that chord did not pass, named as shown. */
  mcpIgnored?: readonly Ignored[] | undefined;
  /**
   * chord's own MCP server, which every session gets beside `mcpServers`
   * where its agent takes HTTP; `/mcp` lists it first. None by default.
   */
  server?: ChordServer | undefined;
  /**
   * Every runtime chord can start, as `list_agents` names them; `agent` and
   * every one chord knows by name by default.
   */
  runtimes?: readonly string[] | undefined;
  /**
   * The user's config directory, whose `chord/teams/` holds the teams for
   * every project; none reads only the project's, as in tests.
   */
  configHome?: string | undefined;
  /**
   * The agents as `chord agents` lists them, PATH looked at, for `/new` to
   * describe and order its names by; the known ones, unlooked, by default.
   */
  listed?: readonly ListedAgent[] | undefined;
  /** Which key does what, as the keybindings file has it; the defaults else. */
  keymap?: Keymap | undefined;
  /** What was wrong in the keybindings file, for the status line to say. */
  keysFailed?: string | undefined;
  /**
   * Writes a selection to the clipboard: `main.tsx`'s through OpenTUI's
   * clipboard service, a test's stub, or none, which copies nothing.
   */
  copy?: Copy | undefined;
  /** Release copies a selection; `false` leaves it to the copy key. */
  copyOnSelect?: boolean | undefined;
  /**
   * Whether the startup splash holds the screen until the first session is
   * up; `main.tsx` asks for it on a terminal, and tests leave it off.
   */
  splash?: boolean | undefined;
}

const NO_BACKGROUND: Background = { tone: 'dark', from: 'default' };

/** The key the window's first session opens under. */
const FIRST_SESSION = noTabs().nextKey;

/**
 * The whole window. chord owns the full terminal (alternate screen) rather than
 * printing into scrollback, so the layout is fixed: header, transcript, the
 * spinner while a turn runs, the prompts queued behind it, prompt, status
 * line. It assembles the window and routes keys; the sessions, the terminal
 * and the commands are driven by the hooks beside it.
 */
export function App({
  agent,
  cwd,
  agentCommand,
  starting,
  startupOf = (name) =>
    name === agent
      ? { agentCommand, starting }
      : findAgent(name) === undefined
        ? undefined
        : {},
  warnings = [],
  stateDir,
  readRecords = readSessionRecords,
  open = openSession,
  resume,
  resumes,
  resumedFront,
  resumedNote,
  files = listFiles,
  match = matchFiles,
  shell = runShell,
  editor = editInEditor,
  clipboard = readClipboardImage,
  openUrl = openLink,
  readImage = readImageFile,
  home = process.env['HOME'],
  onQuit,
  onReady,
  notifications,
  theme = 'auto',
  background = NO_BACKGROUND,
  saveTheme,
  vim = false,
  saveEditorMode,
  settingsFile = 'the settings file',
  mcpServers = [],
  mcpIgnored = [],
  server,
  configHome,
  runtimes = [...new Set([agent, ...listAgents().map(({ name }) => name)])],
  listed = listAgents().map(({ name, title, start, runner }) => ({
    name,
    title,
    start: startLine(start),
    from: runner,
  })),
  keymap = DEFAULT_KEYMAP,
  keysFailed,
  copy,
  copyOnSelect = true,
  splash = false,
}: AppProps) {
  const { width: columns, height: rows } = useTerminalDimensions();
  // In the first frame, so they come before anything the session says.
  const [all, dispatch] = useReducer(reduceWindowed, warnings, (said) =>
    windowed(
      said.reduce<AppState>(
        (state, message, index) =>
          reduceApp(state, {
            type: 'warned',
            turnId: `warning-${index}`,
            message,
          }),
        {
          ...initialAppState,
          agents: agentItems(runtimes, listed),
          theme,
          ...(vim ? { vim: startingVim } : {}),
          keys: keymap,
          ...(keysFailed === undefined ? {} : { keysFailed }),
        },
      ),
      FIRST_SESSION,
    ),
  );
  const state = useMemo(() => frontState(all), [all]);
  const { draft, cursor } = state;
  const setCursor = (at: Cursor) => dispatch({ type: 'draft_set', cursor: at });
  const [history, setHistory] = useState(emptyHistory);
  // The textarea skips telling us a cursor it reported last, so a cursor set
  // from here starts a fresh textarea, or a move back to that spot is lost.
  const [inputKey, setInputKey] = useState(0);
  const redraw = () => setInputKey((key) => key + 1);
  // Set while one of chord's keys is being handled. The input hears the same
  // key and may type it, before or after the window's handler depending on
  // which listener was registered first, which a remount changes.
  const chordKey = useRef(false);
  // Set from a cut placeholder until the box it redraws is up: the old
  // textarea still reports the cursor it left after its own deletion.
  const cutting = useRef(false);
  // How the permission box on screen scrolls its request, while one is up.
  const requestScroller = useRef<RequestScroller | undefined>(undefined);

  useEffect(() => {
    cutting.current = false;
  }, [inputKey]);

  /** Puts `text` in the box with the cursor at `at`. */
  const showDraft = (text: string, at: Cursor) => {
    dispatch({ type: 'draft_set', text, cursor: at });
    redraw();
  };

  // What a prompt sent after its files were read is recorded on: history as
  // it is by then.
  const latestHistory = useRef(history);

  latestHistory.current = history;

  const notify = useNotify(notifications);
  const sessions = useSessions(
    {
      agent,
      agentCommand,
      place: { cwd, startupOf, mcpServers, mcpIgnored },
      stateDir,
      readRecords,
      open,
      resume,
      resumes,
      resumedFront,
      resumedNote,
      server,
      runtimes,
      home,
      configHome,
      onQuit,
    },
    {
      all,
      state,
      dispatch,
      redraw,
      showDraft,
      notify,
      remember: (text, images) =>
        setHistory(recordedWith(latestHistory.current, text, images)),
      stopCommand: (key) => bash.stop(key),
    },
  );
  const { conversation } = sessions;
  // Every tab may run another agent, and work in another directory; what is
  // drawn and run is the front's.
  const frontAgent = frontTab(sessions.sessions.tabs)?.agent ?? agent;
  const here = sessions.frontPlace();

  // Once it has given way, the splash never comes back: not for /clear's
  // session, nor another tab's start.
  const [splashLeft, setSplashLeft] = useState(false);
  const splashing = splashShown(splash, splashLeft, state.connection);

  useEffect(() => {
    if (
      state.connection.status === 'ready' ||
      state.connection.status === 'failed'
    ) {
      setSplashLeft(true);
    }

    if (state.connection.status === 'ready') {
      onReady?.();
    }
  }, [state.connection.status]);

  useTimers(state, dispatch);

  const asked = askedPermission(state.transcript.turn);
  // A request between turns waits without the keys until `ctrl+x a`.
  const held = heldBack(state);
  const between = betweenAsked(state.transcript) !== undefined;
  // A chord's next key is the window's alone, so a digit after the leader
  // never picks a permission's or a form's choice.
  const listening =
    state.connection.status !== 'closing' && state.pendingKeys === undefined;
  const inputAsked = askedInput(state.transcript);
  const picking = modelPickerShown(state);
  const resumingShown = resumePickerShown(state);
  const listingSessions = sessionsPickerShown(state);
  const configuring = configPickerShown(state);
  const theming = themePickerShown(state);
  const listingMcp = mcpShown(state);
  const listingTeams = teamsPickerShown(state);
  const viewing = backgroundShown(state);
  // The list under the prompt has the keys, not the view opened from it.
  const listFocus = agentsHaveKeys(state);
  // Any picker holds the keys the prompt would otherwise take.
  const choosing =
    viewing ||
    picking ||
    resumingShown ||
    configuring ||
    theming ||
    listingMcp ||
    listingSessions ||
    listingTeams;
  const colours = paletteOf(
    resolveTheme(shownTheme(state), background),
    COLOUR,
  );
  // The front session's agents under the prompt, and the child the prompt
  // goes to, if one is picked.
  const agentRows = sessions.agentRows();
  // The list under the prompt: those agents, then the background's
  // summary line, its last stop.
  const agentsLimit = agentsRowLimit(rows);
  const listRows = sessions.listed(agentsLimit);
  const backgroundItems = sessions.background();
  const listShown = listRows.length > 0 || backgroundItems.length > 0;
  // With no agents drawn the summary line is the list's one stop.
  const summaryFocused =
    backgroundItems.length > 0 &&
    (state.summaryFocus === true || listRows.length === 0);
  const child = sessions.picked();
  const childShown = child && {
    name: child.name,
    colour: agentColour(colours, child.colour),
    ...(child.leadName === undefined ? {} : { team: child.leadName }),
  };
  const agentColours = useMemo(
    () =>
      Object.fromEntries(
        agentRows.flatMap((row) => {
          const colour = agentColour(colours, row.colour);

          return colour === undefined ? [] : [[row.name, colour]];
        }),
      ),
    [agentRows.map((row) => `${row.name}:${row.colour}`).join('\n'), colours],
  );

  // Another size wraps the background's rows again: the frame is found
  // again from the `❯`, a tall row from its first line (CHD-430).
  useEffect(() => {
    dispatch({ type: 'background_resized' });
  }, [columns, rows]);

  // A list gone while it had the keys hands them back to the box; a summary
  // line gone gives the `❯` back to the agent picked.
  useEffect(() => {
    if (state.agentsFocus && !listShown) {
      dispatch({ type: 'agents_focused', focused: false });
    } else if (state.summaryFocus && backgroundItems.length === 0) {
      dispatch({ type: 'summary_focused', focused: false });
    }
  }, [
    state.agentsFocus,
    state.summaryFocus,
    listShown,
    backgroundItems.length,
  ]);

  const menu = commandMenu(state, draft);
  const finder = fileFinder(state, draft, cursor);
  const menuRows = menuRowLimit(rows);
  // Esc does not end the mention, so it counts as closed while put away;
  // the edit that brings it back opens it again.
  const mentioning =
    mentionAt(draft, cursor) !== undefined && !state.finder.dismissed;

  useFiles(files, here.cwd, mentioning, dispatch);

  const query = mentioning ? mentionAt(draft, cursor)?.query : undefined;

  useMatch(
    state.files,
    query,
    state.matched?.files === state.files && state.matched?.query === query,
    dispatch,
    match,
  );

  // The names `/team show`, `run` and `stop` offer, read afresh each time
  // the draft comes to one, as a team file may be saved at any time.
  const namingTeam = teamQuery(draft)?.form;

  useEffect(() => {
    if (namingTeam === undefined) {
      return;
    }

    void sessions.listTeams().then(
      (listing) =>
        listing &&
        dispatch({
          type: 'team_names_listed',
          names: {
            teams: listing.teams.map((found) => ({
              name: found.name,
              broken: 'problem' in found,
            })),
            runs: listing.runs.map(({ name }) => name),
          },
        }),
    );
  }, [namingTeam]);

  const bash = useShell(shell, (key) => sessions.placeOf(key).cwd, dispatch);
  const images = useImages({
    clipboard,
    readImage,
    home,
    agent: frontAgent,
    state,
    dispatch,
    sessions: { ...sessions, front: all.front },
  });
  const editDraft = useEditor(editor, dispatch, showDraft);
  const selection = useSelection({
    state,
    dispatch,
    copy,
    copyOnSelect,
    size: `${columns}x${rows}`,
  });

  // A paste clears a selection first, so the textarea never puts it in
  // place of selected text.
  usePasted(() => selection.clear());

  const commands = useCommands(
    {
      // The reports speak of the session shown: a picked child's runtime,
      // not the tab's (CHD-405).
      agent: child?.runtime ?? frontAgent,
      cwd: here.cwd,
      saveTheme,
      saveEditorMode,
      settingsFile,
    },
    state,
    dispatch,
    { ...sessions, stopCommand: () => bash.stop(all.front) },
  );

  // What vim's keys work on: the latest draft, cursor and vim state, kept
  // ahead of the render, so keys read in one go each see the one before.
  const typed = useRef({ vim: state.vim, draft, cursor });

  typed.current = { vim: state.vim, draft, cursor };

  /** What a key is read against: the window as last drawn. */
  const context = (): KeyContext => ({
    state,
    history,
    rows,
    typed: typed.current,
    submitting: images.submitting(all.front),
    home,
    agents: listShown,
    summaryOnly: listRows.length === 0 && backgroundItems.length > 0,
    splash: splashing,
  });

  /** Does one thing a key, an Enter or an edit asked. */
  const playOne = (step: Step) => {
    switch (step.type) {
      case 'dispatch':
        return dispatch(step.action);
      case 'show_draft':
        return showDraft(step.text, step.cursor);
      case 'history':
        return setHistory(step.history);
      case 'leave_splash':
        return setSplashLeft(true);
      case 'typed':
        typed.current = step.typed;

        return;
      case 'chord_key':
        chordKey.current = true;

        // Every listener hears one key in the same tick.
        return queueMicrotask(() => (chordKey.current = false));
      case 'cutting':
        cutting.current = true;

        return;
      case 'open_session':
        return sessions.openBeside();
      case 'next_session':
        sessions.sessions.next();

        return sessions.showFront();
      case 'previous_session':
        sessions.sessions.previous();

        return sessions.showFront();
      case 'goto_session':
        sessions.sessions.goTo(step.number);

        return sessions.showFront();
      case 'close_session':
        return sessions.closeFront();
      case 'attend_session':
        return sessions.attend();
      case 'move_agent':
        return sessions.moveAgent(step.by, agentsLimit);
      case 'close_agent':
        return sessions.closePicked();
      case 'move_background':
        return sessions.moveBackground(step.by, {
          width: columns - 4,
          height: backgroundRowLimit(rows),
        });
      case 'stop_background':
        return sessions.stopBackground();
      case 'go_to_call':
        return sessions.goToCall();
      case 'interrupt':
        return conversation()?.interrupt();
      case 'reject_permission':
        return conversation()?.reject(step.id);
      case 'scroll_request':
        return requestScroller.current?.(step.step);
      case 'set_mode':
        return conversation()?.setMode(step.mode);
      case 'read_commands':
        return conversation()?.readCommands();
      case 'send':
        return sessions.send(step.text);
      case 'send_with_paths':
        return void images.sendWithPaths(step.text);
      case 'take_pasted_paths':
        return void images.takePastedPaths(step.draft, step.end);
      case 'run_command':
        return commands.run(step.command, step.args);
      case 'run_shell':
        return bash.run(all.front, step.command);
      case 'stop_shell':
        return bash.stop(all.front);
      case 'open_editor':
        return void editDraft(draft);
      case 'paste_image':
        return void images.paste(step.quiet);
      case 'copy_selection':
        return selection.copy();
      case 'clear_selection':
        return selection.clear();
      case 'quit':
        return sessions.askQuit();
    }
  };

  const play = (steps: readonly Step[]) => steps.forEach(playOne);

  const submit = (value: string) => play(submitSteps(value, context()));

  // Enter or Tab that waits for a match acts once it is back, or lets go
  // once the mention it was pressed on has changed.
  useEffect(() => {
    if (state.awaitedPick !== undefined) {
      play(awaitedSteps(context()));
    }
  });

  // A key of chord's that would also type is kept from the textarea.
  usePress((input, key) => {
    const steps = keySteps(input, key, context());

    play(steps);

    return steps.some((step) => step.type === 'chord_key');
  });

  // While the search finds a prompt the box shows it, in bash mode when it is
  // a command; the draft waits underneath.
  const found = state.search && matched(state.search, history.prompts);
  const foundCommand = found === undefined ? undefined : bashCommand(found);
  const boxText = foundCommand ?? found ?? draft;
  // Whether the box would have the keys, vim's normal mode aside: while
  // searching, typing is the search line's, and a chord's next key is the
  // window's alone.
  const boxKeys =
    state.connection.status !== 'closing' &&
    (!asked || held) &&
    !choosing &&
    state.pendingKeys === undefined &&
    !state.search &&
    !listFocus;

  // Only the tail's entries are mounted, from the tail's first or the one
  // held while scrolled back; it costs only the tail to find.
  const first = firstMounted(state);
  const { viewport, content, place, measure } = useMeasured(
    state,
    all.front,
    first,
    dispatch,
  );
  const mouse = useMouse({
    // Wherever the pointer is, as the line keys scroll.
    onWheel: (step) =>
      dispatch({
        type: 'wheeled',
        step: step === 'up' ? 'line_up' : 'line_down',
      }),
    onPress: () => selection.pressed(),
  });

  const { waits, armed, strip } = sessions.lines(columns);
  const directory = homePath(here.cwd, home);
  const firstPrompt = state.transcript.entries.find(
    (entry) => entry.kind === 'user',
  );

  // A form or link in the prompt's place; one asked between turns is drawn
  // above the prompt instead, without the keys, until the person takes them
  // into it (CHD-158).
  // A form, a question box or a link names who asks (CHD-389), and says so
  // when it came between turns (CHD-158).
  const inputBetween =
    inputAsked !== undefined &&
    betweenAsked(state.transcript) === inputAsked.id;
  const inputAsker =
    inputAsked === undefined
      ? []
      : askerParts({
          entries: state.transcript.entries,
          subagentId: inputAsked.subagentId ?? inputAsked.asker,
          between: inputBetween,
          picked: childShown,
          runtime: frontAgent,
        });
  // The asker's words where a sentence names it: `… needs one`.
  const inputAgent = inputAsker.map((part) => part.text).join('') || frontAgent;
  const inputDialog =
    inputAsked?.mode === 'form' &&
    inputAsked.questions !== undefined &&
    !listingSessions ? (
      <QuestionBox
        key={inputAsked.id}
        wait={inputAsked}
        questions={inputAsked.questions}
        filled={
          state.answering?.id === inputAsked.id
            ? state.answering.state
            : undefined
        }
        agent={inputAgent}
        asker={inputAsker}
        between={inputBetween}
        windowRows={rows}
        width={columns}
        active={listening && !listFocus && !viewing && !held}
        held={held}
        hidden={viewing}
        onFill={(answering) =>
          dispatch({
            type: 'questions_answered',
            id: inputAsked.id,
            state: answering,
          })
        }
        onAnswer={(response) => conversation()?.answer(inputAsked.id, response)}
      />
    ) : inputAsked?.mode === 'form' && !listingSessions ? (
      <ElicitationForm
        key={inputAsked.id}
        wait={inputAsked}
        filled={
          state.filling?.id === inputAsked.id ? state.filling.form : undefined
        }
        agent={inputAgent}
        asker={inputAsker}
        between={inputBetween}
        windowRows={rows}
        width={columns}
        active={listening && !listFocus && !viewing && !held}
        held={held}
        hidden={viewing}
        onFill={(form) =>
          dispatch({ type: 'form_filled', id: inputAsked.id, form })
        }
        onAnswer={(response) => conversation()?.answer(inputAsked.id, response)}
      />
    ) : inputAsked?.mode === 'url' && !listingSessions ? (
      <LinkPrompt
        key={inputAsked.id}
        wait={inputAsked}
        agent={inputAgent}
        asker={inputAsker}
        between={inputBetween}
        active={listening && !listFocus && !viewing && !held}
        held={held}
        hidden={viewing}
        onAnswer={(answer) =>
          answerLink(openUrl, conversation(), inputAsked, answer)
        }
      />
    ) : undefined;

  return (
    <Colours.Provider value={colours}>
      <AgentColours.Provider value={agentColours}>
        <ChordServerName.Provider
          value={conversation()?.session?.chordServer?.name}
        >
          <Keys.Provider value={state.keys}>
            {splashing && (
              <Splash
                agent={frontAgent}
                armed={armed}
                closing={state.connection.status === 'closing'}
                columns={columns}
                rows={rows}
              />
            )}
            {/* Under the splash the window is laid out but not drawn, so the
        keys pressed meanwhile land in it as if typed there. */}
            <box
              // Always given, so a window shown again is not left hidden.
              visible={!splashing}
              width={columns}
              height={rows}
              {...mouse}
            >
              {/* One session has no row above the header: the header already
        names chord, the agent and the directory. */}
              {strip && <Strip view={strip} />}
              {/* Only this box gives way when the window is full. Everything else and
        every entry is pinned with flexShrink={0}, because OpenTUI boxes shrink by
        default and Yoga would squeeze entries and the prompt box instead of
        letting the transcript run past the view, to be scrolled back to. */}
              {/* Its basis is nothing, so when the rows under it run out it
        has none to keep, and a permission request taller than what is left
        gives way only after the transcript is gone (CHD-246). */}
              <Clip flexGrow={1} flexShrink={1} flexBasis={0} paddingX={1}>
                {/* Following, the transcript hangs from the top while it fits,
          the header on the window's first row, or under the tab strip, and
          once it overflows it sits on the bottom and new rows push the old
          ones up; scrolled back, it hangs from the row on top, so new rows
          land below the view and nothing on screen moves. */}
                <Clip
                  ref={viewport}
                  flexGrow={1}
                  flexShrink={1}
                  justifyContent={
                    state.scroll.following ? 'flex-end' : 'flex-start'
                  }
                >
                  <box
                    ref={content}
                    flexShrink={0}
                    onSizeChange={measure}
                    renderAfter={measure}
                  >
                    {/* The transcript's start, drawn only with its first
              entry, as the entries above the window are not mounted. */}
                    {first > 0 ? null : child ? (
                      <ChildLine
                        child={child}
                        model={
                          state.models === undefined
                            ? child.model
                            : (state.startedModel ?? child.model)
                        }
                      />
                    ) : (
                      <Header
                        facts={{
                          version: manifest.version,
                          agent: frontAgent,
                          model: state.startedModel,
                          directory,
                          helpKey: hintKey(state.keys, 'help:toggle'),
                          resumed: state.resumed && {
                            lastUsedAt: state.resumed.lastUsedAt,
                            // A child is known by its name, as its first
                            // prompt is its parent's; an agent's replay is
                            // all there is of a session chord has no record
                            // of.
                            title:
                              state.resumed.name ??
                              state.resumed.prompt ??
                              (firstPrompt?.kind === 'user'
                                ? promptLine(firstPrompt.text)
                                : undefined),
                          },
                        }}
                        columns={columns}
                      />
                    )}
                    {first === 0 && state.connection.status === 'failed' && (
                      <Failure
                        text={`${frontAgent} did not start: ${state.connection.message}`}
                      />
                    )}
                    {state.transcript.entries.slice(first).map((entry, at) => {
                      const index = first + at;
                      const group = agentGroup(state.transcript.entries, index);

                      // Each entry keeps a box of its own, an empty one for a
                      // subagent its group draws, so scrolling counts entries
                      // as the transcript does.
                      return (
                        <box key={index} ref={place(index)} flexShrink={0}>
                          {group === undefined ? (
                            <TranscriptEntry
                              entry={entry}
                              turn={state.transcript.turn}
                              agent={frontAgent}
                              expanded={state.expanded}
                              width={columns - TRANSCRIPT_INSET}
                            />
                          ) : (
                            group.length > 0 && (
                              <Agents
                                agents={group}
                                turn={state.transcript.turn}
                                agent={frontAgent}
                                open={state.expanded}
                                width={columns - TRANSCRIPT_INSET}
                              />
                            )
                          )}
                        </box>
                      );
                    })}
                  </box>
                  {/* Takes the rows a short transcript leaves, so that it stays
            on top; it has none to take once the transcript overflows, and
            flex-end then puts the overflow above the view. */}
                  <box flexGrow={1} flexShrink={1} />
                </Clip>
                <Below scroll={state.scroll} width={columns - 2} />
              </Clip>
              <Working
                turn={state.transcript.turn}
                asking={inputAsked}
                compacting={state.transcript.entries.some((entry) =>
                  inSpinner(entry, state.transcript.turn),
                )}
              />
              {state.transcript.plan.length > 0 && (
                <Plan
                  plan={state.transcript.plan}
                  limit={planRowLimit(rows)}
                  running={state.transcript.turn.status !== 'idle'}
                />
              )}
              {state.queue.length > 0 && (
                <Queue queue={state.queue} limit={queueRowLimit(rows)} />
              )}
              {/* One box above the prompt at a time: the background view
        opened over a request waiting takes its place until it closes
        (CHD-462). */}
              {asked && !listingSessions && (
                <PermissionPrompt
                  key={asked.id}
                  wait={asked}
                  hidden={viewing}
                  asker={
                    asked.subagentId === undefined
                      ? []
                      : subagentPath(state.transcript.entries, asked.subagentId)
                  }
                  {...(childShown === undefined ? {} : { child: childShown })}
                  between={between}
                  held={held}
                  width={columns - 4}
                  active={listening && !listFocus && !viewing}
                  onChoose={(optionId) =>
                    conversation()?.choose(asked.id, optionId)
                  }
                  scroller={requestScroller}
                  onOverflow={(overflows) =>
                    dispatch({
                      type: 'request_overflowed',
                      id: asked.id,
                      overflows,
                    })
                  }
                />
              )}
              {viewing && state.backgroundView && (
                <BackgroundView
                  items={backgroundItems}
                  focus={state.backgroundView.focus}
                  at={state.backgroundView}
                  hint={state.backgroundView.hint}
                  columns={columns}
                  rows={rows}
                />
              )}
              {picking && (
                <ModelPicker
                  models={state.models}
                  rows={menuRows}
                  agent={frontAgent}
                  active={listening}
                  onPick={sessions.pickModel}
                />
              )}
              {configuring && (
                <ConfigPicker
                  options={state.options}
                  option={configOption(state)}
                  from={state.configPicker?.from}
                  rows={menuRows}
                  agent={frontAgent}
                  active={listening}
                  onOpen={(id) =>
                    dispatch({ type: 'config_option_opened', id })
                  }
                  onPick={sessions.pickOption}
                />
              )}
              {listingSessions && (
                <SessionsPicker
                  tabs={sessions.tabRows()}
                  start={sessions.listFrom()}
                  directory={directory}
                  rows={menuRows}
                  active={listening}
                  onPick={sessions.pickTab}
                />
              )}
              {resumingShown && state.resumePicker && (
                <ResumePicker
                  // A fresh list for each scope, its highlight on the first row.
                  key={String(state.resumePicker.everywhere)}
                  picker={state.resumePicker}
                  open={sessions.openTabs()}
                  rows={menuRows}
                  agent={frontAgent}
                  home={home}
                  active={listening}
                  onPick={(chosen) => sessions.pickResume(chosen, columns)}
                />
              )}
              {theming && (
                <ThemePicker
                  current={state.theme}
                  background={background}
                  windowRows={rows}
                  active={listening}
                  onMove={(theme) =>
                    dispatch({ type: 'theme_previewed', theme })
                  }
                  onPick={commands.keepTheme}
                />
              )}
              {listingTeams && state.teamsPicker && (
                <TeamsPicker
                  listing={state.teamsPicker}
                  rows={menuRows}
                  columns={columns - 4}
                  active={listening}
                  onPick={(found) => {
                    const text = pickedDraft(found);

                    if (text === undefined) {
                      return;
                    }

                    dispatch({ type: 'teams_picker_closed' });
                    showDraft(text, endOf(text));
                  }}
                />
              )}
              {listingMcp && (
                <McpPanel
                  servers={here.mcpServers}
                  ignored={here.mcpIgnored}
                  agent={frontAgent}
                  windowRows={rows}
                  {...(server === undefined
                    ? {}
                    : {
                        chord: chordRow(
                          conversation()?.session?.chordServer,
                          child !== undefined,
                        ),
                      })}
                />
              )}
              {held && inputDialog}
              {inputDialog !== undefined && !held && inputDialog}
              {inputDialog !== undefined && !held && !viewing ? null : (
                <PromptInput
                  key={state.search ? `search:${state.search.match}` : inputKey}
                  value={boxText}
                  cursor={found === undefined ? cursor : endOf(boxText)}
                  rows={promptRows(rows)}
                  chords={liveChords(state, draft, cursor)}
                  {...(state.search && found !== undefined
                    ? { highlight: state.search.query }
                    : {})}
                  // The list's ↑ and ↓ are the window's, as a recalled prompt's are
                  // history's: the textarea leaves them alone.
                  walking={
                    walking(history, typedText(state.bash, draft)) ||
                    menu !== undefined ||
                    finder !== undefined
                  }
                  bash={
                    found === undefined
                      ? state.bash
                      : foundCommand !== undefined
                  }
                  // The input lets go of the keys an effect after the permission
                  // prompt or the model picker is drawn; a key in between is not the
                  // draft's either.
                  onChange={(value) =>
                    (!asked || held) &&
                    !choosing &&
                    !chordKey.current &&
                    play(changeSteps(value, context()))
                  }
                  // While a permission is asked or a model picked, the keys are that
                  // list's, not the draft's.
                  focus={boxKeys && state.vim?.mode !== 'normal'}
                  {...(childShown === undefined ? {} : { agent: childShown })}
                  width={columns}
                  // A press on the box gives the list's keys back to it, the
                  // row's ❯ going and the child picked staying the box's
                  // (CHD-384): OpenTUI has already put its focus there.
                  onPressed={() =>
                    state.agentsFocus &&
                    dispatch({ type: 'agents_focused', focused: false })
                  }
                  // Normal mode's cursor stands only where the box would
                  // otherwise have the keys, so no dialog's own input loses them.
                  normal={boxKeys && state.vim?.mode === 'normal'}
                  onCursorChange={(at) => {
                    if (
                      (!asked || held) &&
                      !choosing &&
                      !chordKey.current &&
                      !cutting.current
                    ) {
                      setCursor(at);
                    }
                  }}
                  onSubmit={submit}
                  onPaste={(text) => play(emptyPasteSteps(text, context()))}
                  wordCut={(before) => placeholderBefore(before, state.images)}
                  onOlder={() => play(olderSteps(context()))}
                  onNewer={() => play(newerSteps(context()))}
                />
              )}
              {state.search ? (
                <SearchLine search={state.search} />
              ) : finder ? (
                <FileList finder={finder} rows={menuRows} />
              ) : menu ? (
                <CommandList menu={menu} rows={menuRows} width={columns} />
              ) : state.help ? (
                <Shortcuts width={columns} />
              ) : (
                // Reserved even when blank, so a message never moves the transcript.
                // Column 2, where Claude Code's status lines and the panel start.
                <box flexDirection='row' paddingX={2} height={1} flexShrink={0}>
                  {state.pendingKeys === undefined ? (
                    <StatusLine
                      state={state}
                      agent={frontAgent}
                      // The shown session's, main's or the picked child's, read
                      // where the list's row reads it.
                      effort={
                        sessions.conversation()?.session?.efforts()?.current
                      }
                      // While the list has the keys, the line says what they
                      // do; its rows show what waits.
                      waits={listFocus ? undefined : waits}
                      armed={armed}
                      draft={draft}
                      width={columns - 4}
                      {...(listFocus
                        ? {
                            hint: summaryFocused
                              ? summaryHint(columns - 4)
                              : agentsHint(
                                  columns - 4,
                                  hintKey(state.keys, 'agents:close'),
                                ),
                          }
                        : {})}
                    />
                  ) : (
                    <LeaderLine
                      held={state.pendingKeys}
                      bindings={pendingBindings(state, draft, cursor)}
                      width={columns - 4}
                    />
                  )}
                </box>
              )}
              <AgentsList
                rows={listRows}
                limit={agentsLimit}
                width={columns - 4}
                focused={listFocus && !summaryFocused}
              />
              <SummaryLine
                items={backgroundItems}
                width={columns - 4}
                focused={listFocus && summaryFocused}
              />
            </box>
          </Keys.Provider>
        </ChordServerName.Provider>
      </AgentColours.Provider>
    </Colours.Provider>
  );
}

/** The transcript's padding on both sides and an entry's gutter. */
const TRANSCRIPT_INSET = 4;
