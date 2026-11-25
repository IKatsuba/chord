import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/stdio.dart';
import 'package:chord/acp_agent.dart';
import 'package:chord/cli.dart';
import 'package:chord/platform/group_exec.dart';
import 'package:chord/platform/resource_fixture.dart' show resourceFixtureFlag;
import 'package:chord/platform/resources.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/server/server.dart' show serveChord;
import 'package:chord/session/launch_connection.dart';
import 'package:chord/session/servers.dart' show noMcpServersFlag;
import 'package:chord/session/sessions.dart';
import 'package:chord/platform/signals.dart';
import 'package:chord/ui/app/renderer.dart';
import 'package:chord/ui/app/crash_screen.dart';
import 'package:chord/ui/shortcuts/bindings.dart' show Keybindings, layoutKeys;
import 'package:chord/platform/heap.dart';
import 'package:chord/ui/start.dart';
import 'package:chord_tui/chord_tui.dart';

Future<void> main(List<String> args) async {
  // Before anything of chord runs: this copy is an agent's launcher.
  if (args.isNotEmpty && args.first == groupExecFlag) groupExec(args);

  // Given back on a forced way out only once the window has taken it.
  Future<void> Function()? giveBack;
  StdioTerminal? sharedTerminal;
  // `"mouse": false` in the user's file leaves the mouse to the terminal.
  var mouse = true;
  // The start pages' keys and colours, as the window's.
  String? theme;
  Keybindings? keymap;
  StdioTerminal terminalForRun() =>
      sharedTerminal ??= StdioTerminal(mouse: mouse);
  Future<void> leaving() async {
    await leave(giveBack: giveBack);
    await sharedTerminal?.close();
  }

  void Function()? stopSignals;
  // The heap signal's handler; off once the window is gone, as it would
  // otherwise keep the process.
  void Function()? stopHeap;
  void watchSignals() => stopSignals ??= dieBySignal(leaving);

  try {
    await runZonedGuarded(() async {
      final outcome = await runCli(
        args,
        stdout: stdout,
        stderr: stderr,
        cwd: Directory.current.path,
        home: Platform.environment['HOME'],
        environment: Platform.environment,
        // As the original's stream consumer reads it: a malformed byte is
        // replaced, a character split across chunks kept whole.
        readPiped: () =>
            stdin.transform(const Utf8Decoder(allowMalformed: true)).join(),
        columns: stdout.hasTerminal ? stdout.terminalColumns : null,
        stdinTTY: stdin.hasTerminal,
        stdoutTTY: stdout.hasTerminal,
        onSettings: (settings) {
          mouse = settings.mouse != false;
          theme = settings.theme;
        },
        onKeymap: (keys) => keymap = keys,
        watchHeap: (heaps) => stopHeap = snapshotOnSignal(heaps),
        pickResume:
            ({
              required sessions,
              required agent,
              required version,
              required directory,
              required cwd,
              required home,
            }) async {
              final terminal = terminalForRun();
              giveBack = terminal.leave;
              watchSignals();
              try {
                return await selectStartupResume(
                  sessions: sessions,
                  agent: agent,
                  version: version,
                  directory: directory,
                  cwd: cwd,
                  home: home,
                  terminal: terminal,
                  handleSignals: false,
                  keymap: keymap,
                  theme: theme,
                );
              } finally {
                giveBack = null;
              }
            },
        pickAgent:
            ({
              required agents,
              required version,
              required directory,
              required preferred,
              required offered,
            }) async {
              final terminal = terminalForRun();
              giveBack = terminal.leave;
              watchSignals();
              try {
                return await selectStartupAgent(
                  agents: agents,
                  version: version,
                  directory: directory,
                  preferred: preferred,
                  offered: offered,
                  terminal: terminal,
                  handleSignals: false,
                  keymap: keymap,
                  theme: theme,
                );
              } finally {
                giveBack = null;
              }
            },
      );
      if (outcome.acp case final start?) {
        // No terminal: stdout is the protocol, and the way out ends chord.
        // The streams' own errors say what their writes say.
        stdout.done.ignore();
        stderr.done.ignore();
        // chord's own MCP server, which every session's agents are
        // admitted to, as the window's are; the process's exit ends it.
        final server = await serveChord();
        // Their readers' close is chord acp's leave step, with the
        // protocol's own words for /team.
        final resources = createResources(
          launchCollectors(resourceFixtureFlag, Platform.environment),
        );
        serveAcp(
          start,
          server: server,
          resources: resources,
          input: stdin,
          sink: IOSinkOutput(stdout),
          stderr: stderr.writeln,
          stdinIsTerminal: stdin.hasTerminal,
          exit: (how) =>
              exitAcp(how, flush: stderr.flush, exit: exit, raise: raiseSignal),
        );
        return;
      }

      final launch = outcome.launch;

      if (launch != null) {
        final terminal = terminalForRun();
        giveBack = terminal.leave;
        watchSignals();
        // chord's own MCP server, which every session of the window is
        // admitted to.
        final server = await serveChord();
        // The providers' limits get_budgets reads, from the fixtures in a
        // build for captures and never otherwise.
        final resources = createResources(
          launchCollectors(resourceFixtureFlag, Platform.environment),
        );
        // What `/new` lists, PATH looked at once before the window, as the
        // original's main reads it.
        final listed = await launch.readListed?.call() ?? const [];
        final connection = startLaunchConnection(
          launch,
          cwd: launch.cwd ?? Directory.current.path,
          server: server,
          resources: resources.read,
        )..listedAgents = listed;
        // A quit closes what chord owns and kills what is left before exit.
        final drawingFailure = WindowCrash();
        await runApp(
          CrashBoundary(
            onCrash: drawingFailure.caught,
            child: StartWindow(
              launch: launch,
              connection: connection,
              terminal: terminal,
            ),
          ),
          terminal: terminal,
          handleSignals: false,
          // A key on a Russian layout is read as the US key in its place.
          layoutFallback: layoutKeys,
          beforeExit: () async {
            try {
              await leave();
              await server.close();
              await terminal.close();
              // A reader still cleaning up is waited for, its failure said
              // once the terminal is the person's again.
              for (final warning in await resources.close()) {
                stderr.writeln(warning);
              }
            } finally {
              drawingFailure.rethrowIfCaught();
            }
            final message = resumeMessage(
              connection.conversation.resumable,
              record: await quitRecordId(
                connection.conversation.resumableRecord,
                connection.conversation.resumable,
              ),
              overrideAgent: launch.name,
              agentCommand: launch.agentCommand,
              noMcpServers: launch.noMcpServersFrom == noMcpServersFlag,
            );
            if (message != null) {
              stdout.writeln(message);
              await stdout.flush();
            }
          },
        );
        return;
      }

      // Piped output is written behind the process's back; exit would cut it.
      await sharedTerminal?.close();
      stopSignals?.call();
      await Future.wait([stdout.flush(), stderr.flush()]);
      exit(outcome.code);
    }, (error, stack) => crash(error, stack, leaving));
  } finally {
    stopHeap?.call();
    await sharedTerminal?.close();
  }
}
