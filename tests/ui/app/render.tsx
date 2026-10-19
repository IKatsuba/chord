/** The window on the fake agent, rendered for the tests of every feature it draws. */
import { execFile } from 'node:child_process';
import type { matchFiles } from '../../../src/ui/prompt/mentions.ts';
import { mkdir, mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { expect } from 'bun:test';
import { join } from 'node:path';
import type { ListedAgent } from '../../../src/agents.ts';
import type { EditorEnd } from '../../../src/editor.ts';
import type { ClipboardReader, ImageFileReader } from '../../../src/images.ts';
import type { LinkOpener } from '../../../src/links.ts';
import type { DefinedServer, Ignored } from '../../../src/mcp.ts';
import type { ChordServer } from '../../../src/server/server.ts';
import type { Notifications } from '../../../src/notify.ts';
import type { EditorMode } from '../../../src/settings.ts';
import { openSession, type Session } from '../../../src/session/session.ts';
import type {
  ResumableTab,
  SessionRecord,
} from '../../../src/session/sessions.ts';
import type { ShellOptions, ShellProcess } from '../../../src/shell.ts';
import { App } from '../../../src/ui/app/App.tsx';
import type { SessionStart } from '../../../src/ui/app/sessions.ts';
import {
  keybindingsNotice,
  readKeybindings,
} from '../../../src/ui/shortcuts/bindings.ts';
import type { Copy } from '../../../src/ui/app/selection.ts';
import type { ThemeSetting } from '../../../src/ui/theme/theme.ts';
import { fakeAgentCommand } from '../../fixtures/fake.ts';
import { draw } from '../harness.tsx';

export const ESC = '\x1b';
export const CTRL_C = '\x03';
export const CTRL_D = '\x04';
export const CTRL_O = '\x0f';
export const UP = '\x1b[A';
export const DOWN = '\x1b[B';
export const END = '\x1b[F';
export const TAB = '\t';
export const CTRL_R = '\x12';
export const CTRL_G = '\x07';

export function isAlive(pid: number): Promise<boolean> {
  return new Promise((resolve) => {
    execFile('ps', ['-p', String(pid)], (error) => resolve(error === null));
  });
}

export async function until(
  what: string,
  check: () => boolean | Promise<boolean>,
  timeout = 10_000,
): Promise<void> {
  const deadline = Date.now() + timeout;

  while (!(await check())) {
    if (Date.now() > deadline) {
      throw new Error(`timed out waiting for ${what}`);
    }

    await new Promise((resolve) => setTimeout(resolve, 20));
  }
}

export interface Window {
  frame(): string;
  /** Waits until the screen shows `text`. */
  shows(text: string): Promise<void>;
  type(text: string): Promise<void>;
  press(key: string): Promise<void>;
  /** `text` pasted, as a terminal with bracketed paste sends it. */
  paste(text: string): Promise<void>;
  /** The terminal resized; a side left out stays as it was. */
  resize(size: { columns?: number; rows?: number }): Promise<void>;
  /** The agent processes the session started. */
  readonly pids: number[];
  /** The directory the agent works in, and the files `@` offers. */
  readonly dir: string;
  readonly session: () => Session | undefined;
  /** Everything written to stdout, frames and anything between them. */
  readonly written: () => readonly string[];
  /** What OpenTUI's own selection holds; a drag is the terminal's. */
  readonly selected: () => string;
  /** Whether a text holding `text` is mounted, on screen or not. */
  readonly mounted: (text: string) => boolean;
}

/**
 * chord's window on the fake agent, drawn through `../harness.tsx`; whatever
 * `body` does, the window is unmounted, the agent stopped, and every process
 * it started proved gone.
 */
export async function withWindow(
  body: (window: Window) => Promise<void>,
  {
    rows,
    columns,
    agentCommand = fakeAgentCommand(),
    typedCommand,
    warnings,
    notifications,
    saveTheme,
    vim,
    saveEditorMode,
    editor,
    clipboard,
    readImage,
    match,
    openUrl,
    mcpServers,
    mcpIgnored,
    server,
    runtimes,
    listed,
    keybindings,
    home,
    shell,
    heldClose,
    heldOpen,
    onQuit,
    startupOf,
    splash,
    teams,
    readRecords,
    log,
    copy = copiedStub,
    copyOnSelect,
    mouse = true,
  }: {
    rows?: number;
    columns?: number;
    agentCommand?: string[];
    /** The `--agent-command` the person typed, which resume lines repeat. */
    typedCommand?: string;
    warnings?: string[];
    notifications?: Notifications;
    saveTheme?: (theme: ThemeSetting) => Promise<void>;
    vim?: boolean;
    saveEditorMode?: (mode: EditorMode) => Promise<void>;
    editor?: (draft: string) => Promise<EditorEnd>;
    clipboard?: ClipboardReader;
    readImage?: ImageFileReader;
    /** How `@` matches its files; fzf's, unless a test holds the match. */
    match?: typeof matchFiles;
    openUrl?: LinkOpener;
    mcpServers?: readonly DefinedServer[];
    mcpIgnored?: readonly Ignored[];
    /** chord's own MCP server, which the test closes; none by default. */
    server?: ChordServer;
    /** The runtimes `list_agents` names; the fake and the registry's else. */
    runtimes?: readonly string[];
    /** The agents as `chord agents` lists them, for `/new` to describe. */
    listed?: readonly ListedAgent[];
    /** A keybindings file's text, read as chord reads one at the start. */
    keybindings?: string;
    /** The window's home directory, from the test's; the user's, by default. */
    home?: (dir: string) => string;
    shell?: (command: string, options: ShellOptions) => ShellProcess;
    /** Settles before the session's close begins, to hold a quit midway. */
    heldClose?: Promise<void>;
    /**
     * Called once the session has opened, which the test then sees, and
     * settles before the window is handed it, to hold the window's start
     * midway; it is given the screen to look at meanwhile.
     */
    heldOpen?: (frame: () => string) => Promise<void>;
    onQuit?: (tabs: readonly ResumableTab[]) => void;
    /** How each agent `/new` names starts, as `main.tsx` works it out. */
    startupOf?: (agent: string) => SessionStart | undefined;
    /** The startup splash, which the window's tests leave off. */
    splash?: boolean;
    /** Team files saved for the project, by name, as their text. */
    teams?: Readonly<Record<string, string>>;
    /** Reads the records `/resume` offers; the window's state directory's. */
    readRecords?: (stateDir: string) => Promise<SessionRecord[]>;
    /**
     * What the terminal is told, as `../harness.tsx`'s `Logged` keeps it,
     * the window on the alternate screen.
     */
    log?: string[];
    /**
     * The clipboard's write, never the system's: by default every copy is
     * written, and nothing is kept.
     */
    copy?: Copy;
    copyOnSelect?: boolean;
    /** `"mouse": false`: the terminal is not asked for it, and nothing copies. */
    mouse?: boolean;
  } = {},
) {
  const dir = await mkdtemp(join(tmpdir(), 'chord-app-'));

  for (const [name, text] of Object.entries(teams ?? {})) {
    await mkdir(join(dir, '.chord', 'teams'), { recursive: true });
    await writeFile(join(dir, '.chord', 'teams', `${name}.md`), text);
  }

  let session: Session | undefined;
  let up = false;
  // The screen, once drawn, for a held open to look at.
  const screen: { frame?: () => string } = {};
  // Every one opened, a task agent's among them, each closed at the end.
  const opened: Session[] = [];
  const pids: number[] = [];
  const keys =
    keybindings === undefined ? undefined : readKeybindings(keybindings);
  const app = await draw(
    <App
      agent='fake'
      cwd={dir}
      stateDir={join(dir, 'state')}
      agentCommand={agentCommand}
      typedCommand={typedCommand}
      warnings={warnings}
      notifications={notifications}
      saveTheme={saveTheme}
      vim={vim}
      saveEditorMode={saveEditorMode}
      {...(editor ? { editor } : {})}
      {...(clipboard ? { clipboard } : {})}
      {...(readImage ? { readImage } : {})}
      {...(match ? { match } : {})}
      // Never the system's browser: a test opens no link.
      openUrl={openUrl ?? (() => Promise.resolve('no browser in tests'))}
      settingsFile='~/.config/chord/settings.json'
      mcpServers={mcpServers}
      mcpIgnored={mcpIgnored}
      {...(server ? { server } : {})}
      {...(runtimes ? { runtimes } : {})}
      {...(listed ? { listed } : {})}
      keymap={keys?.keymap}
      {...(home === undefined ? {} : { home: home(dir) })}
      keysFailed={keys && keybindingsNotice('keybindings.json', keys.problems)}
      {...(shell ? { shell } : {})}
      {...(onQuit ? { onQuit } : {})}
      onReady={() => (up = true)}
      {...(startupOf ? { startupOf } : {})}
      {...(readRecords ? { readRecords } : {})}
      splash={splash}
      {...(mouse ? { copy } : {})}
      {...(copyOnSelect === undefined ? {} : { copyOnSelect })}
      open={async (options) => {
        session = await openSession(options);

        opened.push(session);

        if (heldClose) {
          const close = session.close.bind(session);

          session.close = () => heldClose.then(close);
        }

        pids.push(...session.agentPids);
        await heldOpen?.(() => screen.frame?.() ?? '');

        return session;
      }}
    />,
    { rows, columns },
    log === undefined && mouse ? undefined : { log: log ?? [], mouse },
  );

  const frame = app.frame;

  screen.frame = frame;

  // The settle's time runs from the write, not from the frame it draws:
  // Ink draws in the microtask after a write, which takes tens of ms here,
  // and a test catching a short-lived line (`Working…`) depends on that.
  const settle = (written: Promise<void>) =>
    Promise.all([
      written,
      new Promise((resolve) => setTimeout(resolve, 50)),
    ]).then(() => {});

  const window: Window = {
    frame,
    // A failed wait carries the screen, so a passing run prints nothing.
    shows: (text) =>
      until(`"${text}" on screen`, () => frame().includes(text)).catch(
        (error: Error) => {
          throw new Error(`${error.message}; the screen:\n${frame()}`);
        },
      ),
    type: (text) => settle(app.write(text)),
    press: (key) => settle(app.write(key)),
    paste: (text) => settle(app.paste(text)),
    resize: (size) => settle(app.resize(size)),
    pids,
    dir,
    session: () => session,
    written: app.written,
    selected: app.selected,
    mounted: app.mounted,
  };

  try {
    await until('the session', () => session !== undefined);
    // The window takes it later: until then Enter keeps the draft, and a
    // test's first prompt would stay unsent.
    await until('the window to take the session', () => up);
    await body(window);
  } finally {
    await app.unmount();

    for (const each of opened) {
      await each.close();
    }

    for (const pid of pids) {
      expect(!(await isAlive(pid)), `agent ${pid} still running`).toBeTruthy();
    }

    await rm(dir, { recursive: true });
  }
}

/**
 * Waits for the permission prompt. Ink draws a frame before the effects that
 * hand the keys from the prompt input to the choice list have run, so a key
 * sent the moment the prompt shows can still miss the list.
 */
export async function asked(window: Window): Promise<void> {
  await window.shows('Do you want to proceed?');
  await new Promise((resolve) => setTimeout(resolve, 150));
}

/**
 * Types `prompt` and submits it, waiting until the box holds the draft and
 * then until Enter has taken it out. Its row in the transcript is no proof:
 * a reply can scroll it away before a wait sees it, and the box's own row
 * reads `› ${prompt}` before the Enter is handled.
 */
export async function send(window: Window, prompt: string): Promise<void> {
  // The box's first row, which a long draft fills to its edge.
  const head = prompt.split('\n')[0]!.slice(0, 20);
  const drafted = () => promptRow(window)?.includes(head) ?? false;
  const failed = (error: Error) => {
    throw new Error(`${error.message}; the screen:\n${window.frame()}`);
  };

  await window.type(prompt);
  await until(`"${head}" in the prompt box`, drafted).catch(failed);
  await window.press('\r');
  await until(`"${head}" to leave the prompt box`, () => !drafted()).catch(
    failed,
  );
}

/** A clipboard that writes every copy, as the host's does, and keeps none. */
export const copiedStub: Copy = () =>
  Promise.resolve({
    host: { status: 'written' },
    terminal: { status: 'not-attempted', capability: 'unknown' },
  });

/** An SGR mouse report of the left button at the 0-based cell `x`, `y`. */
export const left = (x: number, y: number, how: 'down' | 'drag' | 'up') =>
  `\x1b[<${how === 'drag' ? 32 : 0};${x + 1};${y + 1}${how === 'up' ? 'm' : 'M'}`;

/** The window's last row: the status line, or what stands in its place. */
export function statusRow(window: Window): string {
  return window.frame().split('\n').at(-1) ?? '';
}

/**
 * Waits for the session to be up, as the status line's hint says; the
 * header names the same keys from the first frame.
 */
export async function ready(window: Window): Promise<void> {
  await until('the shortcut hint on the status line', () =>
    statusRow(window).includes('? for shortcuts'),
  ).catch((error: Error) => {
    throw new Error(`${error.message}; the screen:\n${window.frame()}`);
  });
}

/** The prompt box's first row, `!` first in bash mode. */
export function promptRow(window: Window): string | undefined {
  return window
    .frame()
    .split('\n')
    .find((line) => /^│ [›!]/.test(line));
}

export const CTRL_X = '\x18';

/** ctrl+x, then `key` once the leader line shows. */
export async function leader(window: Window, key: string): Promise<void> {
  await window.press(CTRL_X);
  await window.shows('ctrl+x …');
  await window.press(key);
}

/**
 * Quits, a second time where a session still busy asks for it, and waits
 * until every agent the window started has gone.
 */
export async function quitAll(window: Window): Promise<void> {
  await window.press(CTRL_D);

  if (window.frame().includes('ctrl+d again to quit')) {
    await window.press(CTRL_D);
  }

  await until('every agent to stop', async () => {
    for (const pid of window.pids) {
      if (await isAlive(pid)) {
        return false;
      }
    }

    return true;
  });
}

/**
 * Waits for a form or link the agent asked for, and for its keys to be the
 * form's, as `asked` does for a permission.
 */
export async function inputAsked(
  window: Window,
  title = 'fake asks for input',
) {
  await window.shows(title);
  await new Promise((resolve) => setTimeout(resolve, 150));
}
