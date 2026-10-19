import { ValidationError } from '@cliffy/command';
import {
  CliRenderEvents,
  createClipboard,
  createHostClipboard,
  createRendererClipboardAdapter,
} from '@opentui/core';
import process from 'node:process';
import { text as readText } from 'node:stream/consumers';
import type { Writable } from 'node:stream';
import { join, resolve } from 'node:path';
import { realpathSync } from 'node:fs';
import {
  type Instance,
  openTerminal,
  render,
  type Terminal,
} from './ui/app/renderer.tsx';
import { xdgConfig } from 'xdg-basedir';
import { chordCommand } from './cli.ts';
import {
  agentTable,
  DEFAULT_AGENT,
  findAgent,
  listAgents,
  listedAgents,
  missingCommand,
} from './agents.ts';
import { joinPiped, runHeadless } from './headless.ts';
import { loadMcpServers } from './mcp.ts';
import { terminalEnv } from './notify.ts';
import {
  type Copy,
  COPY_TIMEOUT_MS,
  disposed,
  serviceCopy,
} from './ui/app/selection.ts';
import {
  earlierSessions,
  latestSession,
  readRecords,
  type ResumableTab,
  type ResumedTab,
  ResumeError,
  resumeMessage,
  sessionsByIds,
} from './session/sessions.ts';
import { snapshotOnSignal } from './platform/heap.ts';
import { execPath } from './platform/process.ts';
import { serveChord } from './server/server.ts';
import { upgradeCommand } from './upgrade.ts';
import { chordStateDir } from './session/state_dir.ts';
import {
  earlierWindows,
  isWindowId,
  mixedRefusal,
  newWindowId,
  readWindow,
  readWindows,
  type ResumeEntry,
  windowMessage,
  windowOnQuit,
  type WindowTabs,
  windowTabs,
  writeWindow,
} from './session/windows.ts';
import {
  agentCommands,
  keybindingsFile,
  knownAgents,
  loadKeybindings,
  loadSettings,
  problemLine,
  problemNote,
  refusalLine,
  resolveStartup,
  resumedStartup,
  saveEditorMode,
  saveTheme,
  setWhere,
  shownPath,
  type Sourced,
  startupOf,
  unseenProblems,
  userSettingsFile,
} from './settings.ts';
import { App } from './ui/app/App.tsx';
import { Start } from './ui/app/Start.tsx';
import { COLOUR } from './ui/app/context.ts';
import type { Place } from './ui/app/sessions.ts';
import { keybindingsNotice } from './ui/shortcuts/bindings.ts';
import { background, paletteOf, resolveTheme } from './ui/theme/theme.ts';

/**
 * Writes `text` and waits until the stream has taken it, so an exit right
 * after does not cut off output still queued for a pipe.
 */
function writeAll(to: Writable) {
  return (text: string) =>
    new Promise<void>((done, failed) =>
      to.write(text, (error) => (error ? failed(error) : done())),
    );
}

const cli = chordCommand().action(async (options, named) => {
  // A flag rather than a settings key, so it is typed each time; checked
  // here rather than by Cliffy so its refusal says what it is for.
  if (options.dangerouslySkipPermissions && options.print === undefined) {
    throw new ValidationError(
      '--dangerously-skip-permissions works only with -p',
    );
  }

  const home = process.env['HOME'];
  const loaded = await loadSettings({
    configHome: xdgConfig,
    cwd: resolve(options.cwd),
    ...(home === undefined ? {} : { home }),
  });
  const problems = [...loaded.problems];
  // The start picker's tree, while `chord --resume` with no id has it on
  // screen; App takes its renderer over, so the alternate screen is never
  // left between the two.
  let start: Instance | undefined;
  // Anything said on stderr, or a refusal, is said once the picker has
  // gone, or the alternate screen would take it; the window then opens the
  // terminal afresh.
  const leaveStart = async () => {
    if (start !== undefined) {
      const leaving = start;

      start = undefined;
      terminal = undefined;

      await leaving.unmount();
    }
  };

  // On stderr for scripts and `-p`; the window says them again, as the
  // alternate screen hides these until chord quits.
  const report = async (found: typeof problems) => {
    if (found.length > 0) {
      await leaveStart();
    }

    for (const problem of found) {
      console.error(problemLine(problem));
    }
  };

  await report(problems);

  const flags = {
    agent: named,
    agentCommand: options.agentCommand,
    model: options.model,
    effort: options.effort,
    permissionMode: options.permissionMode,
  };
  const { agent, agentCommand, refused, ...invoked } = resolveStartup(
    flags,
    loaded.layers,
    DEFAULT_AGENT,
  );
  const refusedLine =
    refused === undefined
      ? undefined
      : refusalLine(agent, refused, {
          cwd: resolve(options.cwd),
          home,
        });

  if (
    refused === undefined &&
    agentCommand === undefined &&
    findAgent(agent) === undefined
  ) {
    throw new ValidationError(
      `Unknown agent "${agent}". \`chord agents\` lists them.`,
    );
  }

  // A plain line rather than Cliffy's refusal, which prints the help
  // first: nothing is wrong with how chord was called. Only the agents
  // that start are asked for, so a restore whose tabs are all of other
  // agents does not need the one the command line would have started.
  const refuseMissing = async (
    starts: readonly {
      agent: string;
      agentCommand?: Parameters<typeof missingCommand>[1];
      /** Why it is not started at all: its command was refused. */
      refused?: string | undefined;
    }[],
  ) => {
    for (const start of starts) {
      const missing =
        start.refused ??
        (await missingCommand(start.agent, start.agentCommand));

      if (missing !== undefined) {
        await leaveStart();
        console.error(missing);
        process.exit(1);
      }
    }
  };

  if (options.print !== undefined) {
    await refuseMissing([{ agent, agentCommand, refused: refusedLine }]);

    const mcp = await loadMcpServers({
      layers: loaded.layers,
      cwd: resolve(options.cwd),
    });

    await report(mcp.problems);

    const piped =
      process.stdin.isTTY === true ? undefined : await readText(process.stdin);

    process.exit(
      await runHeadless({
        agent,
        cwd: resolve(options.cwd),
        prompt: joinPiped(options.print, piped),
        format: options.outputFormat ?? 'text',
        ...(agentCommand === undefined ? {} : { agentCommand }),
        mcpServers: mcp.servers.map(({ server }) => server),
        ...(invoked.effort === undefined
          ? {}
          : {
              effort: {
                id: invoked.effort.id,
                from: setWhere(invoked.effort.from, {
                  cwd: resolve(options.cwd),
                  home,
                }),
              },
            }),
        ...(invoked.permissionMode === undefined
          ? {}
          : {
              mode: {
                id: invoked.permissionMode.id,
                from: setWhere(invoked.permissionMode.from, {
                  cwd: resolve(options.cwd),
                  home,
                }),
              },
            }),
        allowAll: options.dangerouslySkipPermissions === true,
        stdout: writeAll(process.stdout),
        stderr: writeAll(process.stderr),
      }),
    );
  }

  // `kill -USR2 <pid>` looks inside a window that has run for hours
  // without stopping it (docs/memory.md).
  snapshotOnSignal(() => join(chordStateDir(), 'heaps'));

  // `-r` with no id is Cliffy's `true`: the picker, in place of an id.
  const picking = options.resume?.some((id) => id === true) === true;
  let ids = options.resume?.filter((id) => typeof id === 'string');
  let resumed: readonly ResumedTab[] = [];
  // The window record `--resume w-…` opened, which quitting rewrites.
  let fromWindow: (WindowTabs & { readonly id: string }) | undefined;
  const find = { agent, cwd: resolve(options.cwd) };

  // Opened once for the start picker and the window both, unless the picker
  // gave it up first; the `auto` theme is the background it answered, then
  // `COLORFGBG`'s, then dark.
  let terminal:
    (Terminal & { found: ReturnType<typeof background> }) | undefined;
  const terminalSetup = async () => {
    // `"mouse": false` leaves the mouse to the terminal.
    const opened = await openTerminal({
      mouse: loaded.settings.mouse !== false,
    });

    return {
      ...opened,
      found: background(opened.dark, process.env['COLORFGBG']),
    };
  };

  const env = terminalEnv((name) => process.env[name]);

  const keys = await loadKeybindings(keybindingsFile(xdgConfig));

  if (picking) {
    if (ids !== undefined && ids.length > 0) {
      throw new ValidationError(
        '--resume picks with no id, or opens the ids it is given; not both.',
      );
    }

    // A picker needs a person at a terminal to pick.
    if (!process.stdin.isTTY || !process.stdout.isTTY) {
      throw new ValidationError('--resume needs an id when not in a terminal');
    }

    const stateDir = chordStateDir();
    const records = await readRecords(stateDir);
    const sessions = earlierSessions(records, { agent });
    const windows = earlierWindows(await readWindows(stateDir), records);

    if (sessions.length === 0 && windows.length === 0) {
      throw new ValidationError(
        `No earlier ${agent} session or window to resume.`,
      );
    }

    terminal = await terminalSetup();

    const { promise, resolve: picked } = Promise.withResolvers<
      ResumeEntry | undefined
    >();

    start = render(
      <Start
        agent={agent}
        directory={shownPath(resolve(options.cwd), {
          cwd: resolve(options.cwd),
          home,
        })}
        home={home}
        cwd={resolve(options.cwd)}
        sessions={sessions}
        windows={windows}
        colours={paletteOf(
          resolveTheme(loaded.settings.theme ?? 'auto', terminal.found),
          COLOUR,
        )}
        keymap={keys.keymap}
        onPick={picked}
      />,
      terminal,
    );

    const chosen = await promise;

    if (chosen === undefined) {
      // Esc: nothing started, so nothing is printed.
      await start.waitUntilExit();

      return;
    }

    ids = [
      chosen.kind === 'window'
        ? chosen.window.id
        : chosen.session.resume.sessionId,
    ];
  }

  if (options.continue || ids !== undefined) {
    const stateDir = chordStateDir();
    const records = await readRecords(stateDir);
    const windowId = ids?.find(isWindowId);

    try {
      if (windowId !== undefined) {
        if (ids!.length > 1) {
          throw mixedRefusal(windowId);
        }

        fromWindow = {
          id: windowId,
          ...windowTabs(records, await readWindow(stateDir, windowId), {
            agent,
            named: named !== undefined,
          }),
        };
        resumed = fromWindow.tabs;
      } else {
        resumed =
          ids === undefined
            ? [{ agent, resume: latestSession(records, find) }]
            : sessionsByIds(records, ids, {
                ...find,
                named: named !== undefined,
              });
      }
    } catch (error) {
      await leaveStart();

      if (error instanceof ResumeError) {
        throw new ValidationError(error.message);
      }

      throw error;
    }
  }

  const resume = resumed.at(0)?.resume;
  const cwd = resolve(resume?.cwd ?? options.cwd);
  const invokedAs = {
    agent,
    ...(agentCommand === undefined ? {} : { agentCommand }),
  };

  /**
   * What a session working in `dir` starts with: a session resumed by id
   * may work elsewhere, and its directory's project file and `.mcp.json`
   * are the ones that speak for it. Each problem is said once, however
   * many directories read the user's file.
   */
  const readPlace = async (dir: string) => {
    const there =
      dir === resolve(options.cwd)
        ? loaded
        : await loadSettings({
            configHome: xdgConfig,
            cwd: dir,
            ...(home === undefined ? {} : { home }),
          });
    const mcp = await loadMcpServers({ layers: there.layers, cwd: dir });
    const added = unseenProblems(problems, [
      ...there.problems,
      ...mcp.problems,
    ]);

    await report(added);
    problems.push(...added);

    return {
      cwd: dir,
      layers: there.layers,
      channel: there.settings.preferredNotifChannel,
      mcp,
      ...resumedStartup(invokedAs, flags, there.layers),
    };
  };

  const read = new Map([[cwd, await readPlace(cwd)]]);

  // Several sessions may work in several directories, each read once, and
  // all before the window, so their problems are said in it.
  for (const { resume } of resumed) {
    const dir = resolve(resume.cwd);

    if (!read.has(dir)) {
      read.set(dir, await readPlace(dir));
    }
  }

  /** A directory read, as the window takes it: paths as it shows them. */
  const placeOf = ({
    cwd,
    layers,
    mcp,
    model,
    effort,
    permissionMode,
  }: Awaited<ReturnType<typeof readPlace>>): Place => {
    const shown = { cwd, home };
    const starting = (value: Sourced | undefined) =>
      value === undefined
        ? undefined
        : { id: value.id, from: setWhere(value.from, shown) };

    return {
      cwd,
      startupOf: (name) => {
        const found = startupOf(
          name,
          {
            ...invokedAs,
            ...(model === undefined ? {} : { model }),
            ...(effort === undefined ? {} : { effort }),
            ...(permissionMode === undefined ? {} : { permissionMode }),
          },
          layers,
        );

        if (found.refused !== undefined) {
          return { refused: refusalLine(name, found.refused, shown) };
        }

        return found.agentCommand === undefined && findAgent(name) === undefined
          ? undefined
          : {
              agentCommand: found.agentCommand,
              starting: {
                model: starting(found.model),
                effort: starting(found.effort),
                mode: starting(found.permissionMode),
              },
            };
      },
      mcpServers: mcp.servers.map((defined) => ({
        ...defined,
        from: shownPath(defined.from, shown),
      })),
      mcpIgnored: mcp.ignored.map((lost) => ({
        ...lost,
        from: shownPath(lost.from, shown),
      })),
    };
  };

  const places = new Map(
    [...read].map(([dir, found]) => [dir, placeOf(found)]),
  );
  const { model, effort, permissionMode, channel, layers } = read.get(cwd)!;
  const first = places.get(cwd)!;
  // A window's tabs each run their recorded agent, even one left alone.
  const resumes =
    resumed.length < 2 && fromWindow === undefined
      ? undefined
      : resumed.map((tab) => ({
          ...tab,
          place: places.get(resolve(tab.resume.cwd))!,
        }));
  // Each record names the agent its session is of, which another
  // directory's files may not know how to start.
  const unstartable = resumes?.find(
    (tab) => tab.place.startupOf(tab.agent) === undefined,
  );

  if (unstartable !== undefined) {
    await leaveStart();

    throw new ValidationError(
      `Session ${unstartable.resume.sessionId} is of agent ` +
        `"${unstartable.agent}", which chord cannot start.`,
    );
  }

  await refuseMissing(
    resumes?.map((tab) => {
      const start = tab.place.startupOf(tab.agent)!;

      return {
        agent: tab.agent,
        agentCommand: start.agentCommand,
        refused: start.refused,
      };
    }) ?? [{ agent, agentCommand, refused: refusedLine }],
  );

  const shown = { cwd, home };
  const settingsFile = userSettingsFile(xdgConfig);

  // Each in the transcript, as settings problems are, so all of them can be
  // read at any width; the status line counts them and names the first.
  await report(keys.problems);
  problems.push(...keys.problems);

  // Opened here, after -p has gone its own way, unless the start picker
  // opened it first.
  terminal ??= await terminalSetup();

  const { found } = terminal;
  // With the mouse the terminal's, chord selects nothing to copy.
  const clipboard =
    loaded.settings.mouse === false ? undefined : copier(terminal.renderer);
  const starting = (value: Sourced | undefined) =>
    value === undefined
      ? undefined
      : { id: value.id, from: setWhere(value.from, shown) };
  let resumable: readonly ResumableTab[] = [];
  let resumableFront = 0;
  // Once for the window, before its first session opens; `-p` has gone.
  const server = serveChord();
  const listed = await listedAgents(agentCommands(layers));
  const window = (
    <App
      agent={agent}
      cwd={resume?.cwd ?? options.cwd}
      agentCommand={agentCommand}
      starting={{
        model: starting(model),
        effort: starting(effort),
        mode: starting(permissionMode),
      }}
      startupOf={first.startupOf}
      warnings={problems.map((problem) => problemNote(problem, shown))}
      resume={resume}
      resumes={resumes}
      resumedFront={fromWindow?.front}
      resumedNote={fromWindow?.note}
      onQuit={(tabs, front) => {
        resumable = tabs;
        resumableFront = front;
      }}
      notifications={{
        channel: channel ?? 'auto',
        env,
      }}
      copy={clipboard?.copy}
      copyOnSelect={loaded.settings.copyOnSelect !== false}
      theme={loaded.settings.theme}
      vim={loaded.settings.editorMode === 'vim'}
      mcpServers={first.mcpServers}
      mcpIgnored={first.mcpIgnored}
      server={server}
      configHome={xdgConfig}
      runtimes={knownAgents(
        { agent, ...(agentCommand === undefined ? {} : { agentCommand }) },
        layers,
        listAgents().map(({ name }) => name),
      )}
      listed={listed}
      background={found}
      keymap={keys.keymap}
      keysFailed={keybindingsNotice(
        'keybindings.json',
        keys.problems.map(({ message }) => message),
      )}
      // Nothing should redraw into a pipe.
      splash={process.stdout.isTTY === true}
      {...(settingsFile === undefined
        ? {}
        : {
            saveTheme: (theme) => saveTheme(settingsFile, theme),
            saveEditorMode: (mode) => saveEditorMode(settingsFile, mode),
            settingsFile: shownPath(settingsFile, shown),
          })}
    />
  );
  // The start picker's renderer goes on as the window's, on the same screen.
  const app = start ?? render(window, terminal);

  app.rerender(window);

  start = undefined;

  await app.waitUntilExit();
  await server.close();
  await clipboard?.disposed();

  // A window opened from a record rewrites it, so quitting it again leaves
  // no copy.
  const saving = windowOnQuit(resumable, resumableFront, {
    id: fromWindow?.id ?? newWindowId(),
    at: Date.now(),
  });
  let saved = false;

  if (saving !== undefined) {
    try {
      await writeWindow(chordStateDir(), saving);

      saved = true;
    } catch (error) {
      // Each session's command still resumes it, so they are printed in
      // the window's place.
      console.error(
        `chord could not save this window: ${
          error instanceof Error ? error.message : String(error)
        }`,
      );
    }
  }

  // After the window has gone, so it stays in the terminal's scrollback.
  const resuming =
    saved && saving !== undefined
      ? windowMessage(saving.id)
      : resumeMessage(resumable, {
          agent,
          ...(agentCommand === undefined ? {} : { agentCommand }),
        });

  if (resuming !== undefined) {
    console.log(resuming);
  }
});

cli
  .command(
    'agents',
    'List the agents chord can start: name, title, command, and for those started by their own CLI whether PATH has it.',
  )
  .option('-C, --cwd <dir:string>', 'Directory whose settings to read.', {
    default: process.cwd(),
  })
  .action(async ({ cwd }) => {
    const home = process.env['HOME'];
    const loaded = await loadSettings({
      configHome: xdgConfig,
      cwd: resolve(cwd),
      ...(home === undefined ? {} : { home }),
    });

    for (const problem of loaded.problems) {
      console.error(problemLine(problem));
    }

    console.log(
      agentTable(
        await listedAgents(agentCommands(loaded.layers)),
        process.stdout.isTTY === true ? process.stdout.columns : undefined,
      ),
    );
  });

cli.command('upgrade', upgradeCommand(realpathSync(execPath()), process.env));

/**
 * The window's one clipboard service, OpenTUI's: the system clipboard
 * through its native host, OSC 52 where that fails or over SSH (owner,
 * CHD-172), and the copy `App` writes through. It is disposed as the
 * renderer is destroyed, which every way out reaches; a host that ignores
 * the abort leaves its dispose pending for ever, so the wait is bounded.
 */
function copier(renderer: Terminal['renderer']): {
  copy: Copy;
  disposed: () => Promise<void>;
} {
  const service = createClipboard({
    host: createHostClipboard({ timeoutMs: COPY_TIMEOUT_MS }),
    terminal: createRendererClipboardAdapter(renderer),
  });
  let disposing: Promise<void> | undefined;

  renderer.once(CliRenderEvents.DESTROY, () => {
    disposing = disposed(service, 100);
  });

  return {
    copy: serviceCopy(service),
    disposed: () => disposing ?? Promise.resolve(),
  };
}

if (import.meta.main) {
  await cli.parse(process.argv.slice(2));
}
