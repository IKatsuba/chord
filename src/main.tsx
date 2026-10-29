import { createResources } from './platform/resources.ts';
import {
  resourceFixtureCase,
  resourceSourceMode,
} from './platform/resource_fixture.ts';
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
  closeOnForcedExit,
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
  takesMcpServers,
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
  type EarlierSession,
  earlierSessions,
  latestSession,
  readRecords,
  recordsOnce,
  recordedAgent,
  type Resumable,
  type Resume,
  ResumeError,
  resumeMessage,
  sessionById,
} from './session/sessions.ts';
import { openSession } from './session/session.ts';
import { snapshotOnSignal } from './platform/heap.ts';
import { execPath } from './platform/process.ts';
import {
  RESOURCE_WORKER_FLAG,
  runResourceWorker,
} from './platform/resource_worker.ts';
import { serveChord } from './server/server.ts';
import { upgradeCommand } from './upgrade.ts';
import { chordStateDir } from './session/state_dir.ts';
import {
  agentCommands,
  keybindingsFile,
  knownAgents,
  loadKeybindings,
  loadSettings,
  readTeamSelection,
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
import { chooseAgentAtStart } from './ui/app/startup_choice.ts';
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

/** Startup factories stay behind the choice boundary; tests can observe them directly. */
export const startServices = {
  openTerminal,
  render,
  copier,
  serveChord,
  createResources,
  openSession,
};

export const cli = chordCommand().action(async (options, named) => {
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
  // The agent or resume picker before a session starts. App takes its
  // renderer over, so the alternate screen is never
  // left between the two.
  let start: Instance | undefined;
  let terminal:
    (Terminal & { found: ReturnType<typeof background> }) | undefined;
  const terminalSetup = async () => {
    const opened = await startServices.openTerminal({
      mouse: loaded.settings.mouse !== false,
    });

    return {
      ...opened,
      found: background(opened.dark, process.env['COLORFGBG']),
    };
  };

  let keys: Awaited<ReturnType<typeof loadKeybindings>> | undefined;
  let listed: Awaited<ReturnType<typeof listedAgents>> | undefined;

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

  let selected = named;

  if (
    chooseAgentAtStart({
      ...options,
      named,
      stdinTTY: process.stdin.isTTY === true,
      stdoutTTY: process.stdout.isTTY === true,
    })
  ) {
    listed = await listedAgents(agentCommands(loaded.layers));
    keys = await loadKeybindings(keybindingsFile(xdgConfig));
    terminal = await terminalSetup();

    const { promise, resolve: picked } = Promise.withResolvers<
      string | undefined
    >();

    start = startServices.render(
      <Start
        kind='agents'
        agents={listed}
        preferred={loaded.settings.agent ?? DEFAULT_AGENT}
        directory={shownPath(resolve(options.cwd), {
          cwd: resolve(options.cwd),
          home,
        })}
        colours={paletteOf(
          resolveTheme(loaded.settings.theme ?? 'auto', terminal.found),
          COLOUR,
        )}
        keymap={keys.keymap}
        onPick={picked}
      />,
      terminal,
    );

    selected = await promise;

    if (selected === undefined) {
      await start.waitUntilExit();

      return;
    }
  }

  // One id and no agent named on the command line: the session's own
  // agent, as its record says (Q180). An --agent-command still goes with
  // the default agent alone (Q56), so it leaves the id to be refused there.
  // `-r` with no id is Cliffy's `true`: the picker, in place of an id.
  const given = typeof options.resume === 'string' ? options.resume : undefined;
  const records = recordsOnce(() => readRecords(chordStateDir()));
  const recorded =
    named === undefined &&
    options.agentCommand === undefined &&
    given !== undefined
      ? recordedAgent(await records(), given)
      : undefined;
  const flags = {
    agent: selected ?? recorded,
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
    await leaveStart();

    throw new ValidationError(
      `Unknown agent "${agent}". \`chord agents\` lists them.`,
    );
  }

  // A plain line rather than Cliffy's refusal, which prints the help
  // first: nothing is wrong with how chord was called. Only the agent that
  // starts is asked for, so resuming another agent's session does not need
  // the one the command line would have started.
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
        // As every line chord says before its window, a missing command's too.
        console.error(
          start.refused === undefined ? missing : `chord: ${missing}`,
        );
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
        ...(takesMcpServers(agent, invoked.mcpServers)
          ? {}
          : { noMcpServers: true }),
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

  const picking = options.resume === true;
  let id = given;
  let resume: Resume | undefined;
  const find = { agent, cwd: resolve(options.cwd) };

  const env = terminalEnv((name) => process.env[name]);

  keys ??= await loadKeybindings(keybindingsFile(xdgConfig));

  if (picking) {
    // A picker needs a person at a terminal to pick.
    if (!process.stdin.isTTY || !process.stdout.isTTY) {
      throw new ValidationError('--resume needs an id when not in a terminal');
    }

    const sessions = earlierSessions(await records(), { agent });

    if (sessions.length === 0) {
      throw new ValidationError(`No earlier ${agent} session to resume.`);
    }

    terminal = await terminalSetup();

    const { promise, resolve: picked } = Promise.withResolvers<
      EarlierSession | undefined
    >();

    start = startServices.render(
      <Start
        agent={agent}
        directory={shownPath(resolve(options.cwd), {
          cwd: resolve(options.cwd),
          home,
        })}
        home={home}
        cwd={resolve(options.cwd)}
        sessions={sessions}
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

    id = chosen.resume.sessionId;
  }

  if (options.continue || id !== undefined) {
    const found = await records();

    try {
      // A w-… id of an old window is an id like any other, for the agent to
      // answer (Q179).
      resume =
        id === undefined
          ? latestSession(found, find)
          : sessionById(found, id, find);
    } catch (error) {
      await leaveStart();

      if (error instanceof ResumeError) {
        throw new ValidationError(error.message);
      }

      throw error;
    }
  }

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
      teamSelection: there.settings.teamSelection,
      mcp,
      ...resumedStartup(invokedAs, flags, there.layers),
    };
  };

  // The one place the window reads: the directory its session works in.
  const read = await readPlace(cwd);

  /** A directory read, as the window takes it: paths as it shows them. */
  const placeOf = ({
    cwd,
    layers,
    mcp,
    model,
    effort,
    permissionMode,
    teamSelection,
  }: Awaited<ReturnType<typeof readPlace>>): Place => {
    const shown = { cwd, home };
    const starting = (value: Sourced | undefined) =>
      value === undefined
        ? undefined
        : { id: value.id, from: setWhere(value.from, shown) };

    return {
      cwd,
      selectionPolicy: () =>
        readTeamSelection({
          configHome: xdgConfig,
          cwd,
          ...(home === undefined ? {} : { home }),
        }),
      ...(teamSelection === undefined ? {} : { teamSelection }),
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
        // The window's own agent starts as it was invoked, but this place's
        // files may refuse its command, unless a flag gave it one.
        const refused =
          found.refused ??
          (name === agent && flags.agentCommand === undefined
            ? resolveStartup({ agent: name }, layers, name).refused
            : undefined);

        if (refused !== undefined) {
          return { refused: refusalLine(name, refused, shown) };
        }

        return found.agentCommand === undefined && findAgent(name) === undefined
          ? undefined
          : {
              agentCommand: found.agentCommand,
              ...(takesMcpServers(name, found.mcpServers)
                ? {}
                : { mcpServers: false as const }),
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

  const { model, effort, permissionMode, channel, layers } = read;
  const first = placeOf(read);

  // A session resumed works in its record's directory, whose files may
  // refuse what the command line's would not.
  await refuseMissing([
    { agent, agentCommand, refused: first.startupOf(agent)?.refused },
  ]);

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
    loaded.settings.mouse === false
      ? undefined
      : startServices.copier(terminal.renderer);
  const starting = (value: Sourced | undefined) =>
    value === undefined
      ? undefined
      : { id: value.id, from: setWhere(value.from, shown) };
  let resumable: Resumable | undefined;
  // Once for the window, before its first session opens; `-p` has gone.
  const server = startServices.serveChord();
  const collectors = resourceSourceMode(process.env['CHORD_RESOURCE_FIXTURE']);
  const resources = startServices.createResources({
    collectors,
    ...(collectors === 'fixture'
      ? {
          fixtureCase: resourceFixtureCase(
            process.env['CHORD_FAKE_RESOURCE_CASE'],
          ),
        }
      : {}),
  });

  let closingResources: Promise<void> | undefined;
  const closeResources = () =>
    (closingResources ??= resources.close().then((warnings) => {
      for (const warning of warnings) {
        process.stderr.write(`${warning}\n`);
      }
    }));

  const forgetResources = closeOnForcedExit(closeResources);

  listed ??= await listedAgents(agentCommands(loaded.layers));

  const window = (
    <App
      open={startServices.openSession}
      resources={resources.read}
      teamSelection={first.teamSelection}
      selectionPolicy={first.selectionPolicy}
      agent={agent}
      cwd={resume?.cwd ?? options.cwd}
      agentCommand={agentCommand}
      typedCommand={flags.agentCommand}
      starting={{
        model: starting(model),
        effort: starting(effort),
        mode: starting(permissionMode),
      }}
      startupOf={first.startupOf}
      warnings={problems.map((problem) => problemNote(problem, shown))}
      resume={resume}
      onQuit={(session) => {
        resumable = session;
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
  const app = start ?? startServices.render(window, terminal);

  app.rerender(window);

  start = undefined;

  try {
    await app.waitUntilExit();
  } finally {
    await closeResources();
    forgetResources();
  }

  await server.close();
  await clipboard?.disposed();

  // After the window has gone, so it stays in the terminal's scrollback.
  const resuming = resumeMessage(resumable, {
    agent,
    // The flag's command alone: the settings give theirs again (Q56).
    ...(flags.agentCommand === undefined
      ? {}
      : { agentCommand: flags.agentCommand }),
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
  const args = process.argv.slice(2);

  if (args[0] === RESOURCE_WORKER_FLAG) {
    await runResourceWorker(args.slice(1));
  } else {
    await cli.parse(args);
  }
}
