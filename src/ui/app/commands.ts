/**
 * chord's own slash commands as the window runs them, with the theme and
 * the editor mode they keep for the next start.
 */
import type { SpendPart } from '../transcript/spend.ts';
import { type Dispatch, useRef } from 'react';
import type { Conversation } from '../../session/conversation.ts';
import type { TeamShown } from '../../session/transcript/types.ts';
import type { EditorMode } from '../../settings.ts';
import {
  newTeamPrompt,
  teamCommand,
  type TeamListing,
} from '../teams/teams.ts';
import type { ChordCommand } from '../prompt/commands.ts';
import { report, reportFacts } from '../transcript/reports.ts';
import { themeName, type ThemeSetting } from '../theme/theme.ts';
import type { AppState, WindowedAction } from './state.ts';

export interface CommandsOptions {
  agent: string;
  cwd: string;
  saveTheme: ((theme: ThemeSetting) => Promise<void>) | undefined;
  saveEditorMode: ((mode: EditorMode) => Promise<void>) | undefined;
  /** The user's settings file, as the window shows paths. */
  settingsFile: string;
  /** How wide the window is, which `/cost`'s table is laid out in. */
  columns: number;
}

/** What the commands do to the sessions; see `useSessions`. */
export interface CommandsSessions {
  conversation(): Conversation | undefined;
  takeBackQueue(typed: string): void;
  /** Stops the command running in the session in front, if one runs. */
  stopCommand(): void;
  openResume(): void;
  quit(): void;
  /** What the whole window has spent, closed agents and sessions too. */
  spend(): readonly SpendPart[];
  /**
   * `/clear` on the session in front, `before` done first; why it was
   * refused, if it was, and then nothing is done.
   */
  clearFront(before: () => void): string | undefined;
  /** Main's key, which `/team` talks to. */
  frontKey(): number | undefined;
  /** A child, not `main`, is picked. */
  picked(): unknown;
  listTeams(): Promise<TeamListing | undefined>;
  runTyped(name: string, job: string): Promise<TeamShown>;
  stopTyped(name: string, show: (shown: TeamShown) => void): void;
  showTyped(name: string): Promise<TeamShown>;
  sendToMain(typed: string, prompt: string): void;
  /**
   * `/new`: an agent of `named`, or of main's runtime, opened for main and
   * gone to, its call to draw; or why not, if it was refused.
   */
  newTyped(named: string): Promise<TeamShown>;
  /** `/fork`; see `useSessions`. */
  forkTyped(
    named: string,
  ): Promise<
    | { readonly name: string; readonly from: number }
    | { readonly refused: string }
  >;
}

export function useCommands(
  {
    agent,
    cwd,
    saveTheme,
    saveEditorMode,
    settingsFile,
    columns,
  }: CommandsOptions,
  state: AppState,
  dispatch: Dispatch<WindowedAction>,
  sessions: CommandsSessions,
): {
  run: (command: ChordCommand, args?: string) => void;
  keepTheme: (chosen: ThemeSetting) => void;
} {
  const { conversation } = sessions;
  // `/team` says once that it talks to main while a child is picked.
  const talked = useRef(false);

  /** Runs one of chord's own slash commands. */
  const run = (command: ChordCommand, args = '') => {
    switch (command) {
      case 'new': {
        const typed = ['new', args].filter(Boolean).join(' ');
        const key = sessions.frontKey();

        return void sessions.newTyped(args).then((shown) => {
          // Opened, the call is main's, drawn as `/team run` draws its own;
          // refused, it is said where it was typed, in open_agent's words.
          if (shown.kind === 'ran' && key !== undefined) {
            dispatch({
              type: 'in_session',
              key,
              action: {
                type: 'team_shown',
                turnId: `new-${crypto.randomUUID()}`,
                command: typed,
                shown,
              },
            });
          } else if (shown.kind === 'said') {
            dispatch({
              type: 'noted',
              turnId: `new-${crypto.randomUUID()}`,
              command: typed,
              text: shown.text,
              failed: true,
            });
          }
        });
      }
      case 'fork': {
        const typed = ['fork', args].filter(Boolean).join(' ');

        const turnId = `fork-${crypto.randomUUID()}`;

        // Said under the command as typed: on the agent forked, which the
        // fork is in front of by then, or where it was refused (CHD-101).
        return void sessions.forkTyped(args).then((forked) =>
          'refused' in forked
            ? dispatch({
                type: 'noted',
                turnId,
                command: typed,
                text: forked.refused,
                failed: true,
              })
            : dispatch({
                type: 'in_session',
                key: forked.from,
                action: {
                  type: 'noted',
                  turnId,
                  command: typed,
                  text: `Forked into ${forked.name}`,
                  failed: false,
                },
              }),
        );
      }
      case 'clear': {
        const refused = sessions.clearFront(() => {
          // The session they were queued in goes; what they said stays.
          sessions.takeBackQueue('');
          // Its output would have gone to the session that goes with it.
          sessions.stopCommand();
        });

        return refused === undefined
          ? undefined
          : dispatch({
              type: 'noted',
              turnId: `clear-${crypto.randomUUID()}`,
              command: 'clear',
              text: refused,
              failed: true,
            });
      }
      case 'help':
        return dispatch({ type: 'help_opened' });
      case 'model':
        return dispatch({ type: 'model_picker_opened' });
      case 'config':
        // The agent may have changed them since the last turn.
        conversation()?.readOptions();

        return dispatch({ type: 'config_picker_opened' });
      case 'resume':
        return sessions.openResume();
      case 'theme':
        return dispatch({ type: 'theme_picker_opened' });
      case 'mcp':
        return dispatch({ type: 'mcp_opened' });
      case 'vim':
        return toggleVim();
      case 'cost':
      case 'context':
      case 'status':
        return dispatch({
          type: 'reported',
          turnId: crypto.randomUUID(),
          command,
          rows: report(
            command,
            reportFacts(state, agent, cwd, Date.now(), {
              spend: sessions.spend(),
              // Under the report's `⎿`, six columns in, inside the
              // transcript's margins: a note never wraps.
              width: columns - 8,
            }),
          ),
        });
      case 'exit':
        return sessions.quit();
      case 'team':
        return team(args);
    }
  };

  /**
   * `/team` and its forms, for `main` whatever is picked,
   * as teams belong to the session the person opened; what each does is
   * drawn in main's transcript under the command as typed.
   */
  const team = (args: string) => {
    const key = sessions.frontKey();

    if (key === undefined) {
      return;
    }

    const typed = ['team', args].filter(Boolean).join(' ');
    const show = (shown: TeamShown) =>
      dispatch({
        type: 'in_session',
        key,
        action: {
          type: 'team_shown',
          turnId: `team-${crypto.randomUUID()}`,
          command: typed,
          shown,
        },
      });
    const said = (text: string, failed: boolean) =>
      show({ kind: 'said', text, failed });
    const asked = teamCommand(args);

    if (asked.form !== 'list' && sessions.picked() && !talked.current) {
      talked.current = true;

      dispatch({ type: 'sessions_noted', message: '/team talks to main' });
    }

    switch (asked.form) {
      case 'refused':
        return said(asked.problem, true);
      case 'list':
        return void sessions.listTeams().then((listing) => {
          if (listing !== undefined) {
            show({ kind: 'listed' });
            dispatch({ type: 'teams_picker_opened', listing });
          }
        });
      case 'new':
        return sessions.sendToMain(`/${typed}`, newTeamPrompt(asked.words));
      case 'show':
        return void sessions.showTyped(asked.name).then(show);
      case 'run':
        return void sessions.runTyped(asked.name, asked.job).then(show);
      case 'stop':
        return sessions.stopTyped(asked.name, show);
    }
  };

  /**
   * Enter on `/theme`: the theme highlighted stays, a note says so and it is
   * saved for the next start. Choosing the one in use again changes nothing.
   * A failed save still leaves it on for this session, and says so.
   */
  const keepTheme = (chosen: ThemeSetting) => {
    dispatch({ type: 'theme_chosen', theme: chosen });

    if (chosen === state.theme) {
      return;
    }

    const note = (text: string, failed: boolean) =>
      dispatch({
        type: 'noted',
        turnId: `theme-${crypto.randomUUID()}`,
        command: 'theme',
        text,
        failed,
      });

    if (saveTheme === undefined) {
      return note(`Theme set to ${themeName(chosen)}`, false);
    }

    saveTheme(chosen).then(
      () => note(`Theme set to ${themeName(chosen)}`, false),
      (error: unknown) =>
        note(
          `Could not save the theme to ${settingsFile}: ${
            error instanceof Error ? error.message : String(error)
          }; it lasts until chord quits`,
          true,
        ),
    );
  };

  /**
   * `/vim`: vim mode on, in insert mode, or off, said in a note, as Claude
   * Code says it, and kept for the next start. A failed save still leaves
   * it so for this session, and says so.
   */
  const toggleVim = () => {
    const on = state.vim === undefined;
    const said = on
      ? 'Vim mode on: Esc for normal mode, i to insert'
      : 'Vim mode off';
    const note = (text: string, failed: boolean) =>
      dispatch({
        type: 'noted',
        turnId: `vim-${crypto.randomUUID()}`,
        command: 'vim',
        text,
        failed,
      });

    dispatch({ type: 'vim_toggled', on });

    if (saveEditorMode === undefined) {
      return note(said, false);
    }

    saveEditorMode(on ? 'vim' : 'normal').then(
      () => note(said, false),
      (error: unknown) =>
        note(
          `${said}, but it could not be saved to ${settingsFile}: ${
            error instanceof Error ? error.message : String(error)
          }; it lasts until chord quits`,
          true,
        ),
    );
  };

  return { run, keepTheme };
}
