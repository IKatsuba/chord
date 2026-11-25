import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

import '../cli.dart';
import '../agents.dart';
import '../notify.dart';
import '../session/sessions.dart';
import 'app/context.dart' show Keys;
import 'app/start.dart';
import 'shortcuts/bindings.dart' show Keybindings, defaultKeymap, layoutKeys;
import 'theme/theme.dart' show themeData;
import 'app/startup_choice.dart';
import '../session/start_connection.dart';
import 'app/window.dart';
import 'start_state.dart';

/// The start pages as the window draws: the keybindings file's keys,
/// named in their hints, and the theme in the user's file, as the
/// original's main passes them to its Start.
class StartLook extends StatelessWidget {
  const StartLook({super.key, this.keymap, this.theme, required this.child});

  /// The file over chord's keys; chord's own without one.
  final Keybindings? keymap;

  /// The `theme` setting; Auto leaves the terminal's own.
  final String? theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final keys = keymap ?? defaultKeymap;
    final page = Keys(
      keymap: keys,
      child: Keymap(data: keys.data, child: child),
    );
    final named = theme;
    if (named == null || named == 'auto') return page;
    return Theme(
      data: themeData(named, colour: !Theme.noColorOf(context)),
      child: page,
    );
  }
}

/// Runs the new invocation's catalog before any agent or session starts.
/// Set [handleSignals] false when the caller owns process signal cleanup.
Future<String?> selectStartupAgent({
  required List<ListedAgent> agents,
  required String version,
  required String directory,
  String preferred = defaultAgent,
  List<String>? offered,
  Terminal? terminal,
  Map<String, String>? environment,
  bool handleSignals = true,
  Keybindings? keymap,
  String? theme,
}) async {
  final selection = StartupSelection();
  await runApp(
    StartLook(
      keymap: keymap,
      theme: theme,
      child: StartPage(
        version: version,
        directory: directory,
        agents: agents,
        preferred: preferred,
        offered: offered,
        onPicked: selection.settle,
        onCanceled: () => selection.settle(null),
      ),
    ),
    terminal: terminal,
    environment: environment,
    exitProcess: false,
    handleSignals: handleSignals,
    // A key on a Russian layout is read as the US key in its place.
    layoutFallback: layoutKeys,
  );
  return selection.selected;
}

/// Runs the startup resume choice without allocating a session or agent.
Future<EarlierSession?> selectStartupResume({
  required List<EarlierSession> sessions,
  required String agent,
  required String version,
  required String directory,
  required String cwd,
  required String? home,
  Terminal? terminal,
  Map<String, String>? environment,
  bool handleSignals = true,
  Keybindings? keymap,
  String? theme,
}) async {
  EarlierSession? selected;
  await runApp(
    StartLook(
      keymap: keymap,
      theme: theme,
      child: ResumeStartPage(
        sessions: sessions,
        agent: agent,
        version: version,
        directory: directory,
        cwd: cwd,
        home: home,
        onPicked: (session) => selected = session,
      ),
    ),
    terminal: terminal,
    environment: environment,
    exitProcess: false,
    handleSignals: handleSignals,
    // A key on a Russian layout is read as the US key in its place.
    layoutFallback: layoutKeys,
  );
  return selected;
}

/// The line the interim window shows: chord's version, the agent and the
/// directory.
String windowLine(Launch launch) =>
    'chord v${launch.version} · ${launch.agent?.title ?? launch.name} · ${launch.directory}';

/// What the interim window says of the keys that quit it.
const quitHint = 'ctrl+c or ctrl+d to quit';

/// The selected agent's window: the transcript for a live connection, or
/// an interim launch summary when no agent command was supplied.
class StartWindow extends StatelessWidget {
  /// The window for [launch], drawing [state] when an agent is started.
  const StartWindow({
    super.key,
    required this.launch,
    this.state,
    this.connection,
    this.terminal,
  });

  /// What the command line chose to open.
  final Launch launch;

  /// The live conversation, when the CLI starts an agent.
  final StartConnection? connection;

  /// The same borrowed terminal supplied to runApp by the process owner.
  final Terminal? terminal;

  /// Connection facts for start-page consumers without a live conversation.
  final ValueNotifier<StartState>? state;

  @override
  Widget build(BuildContext context) {
    final live = connection;
    if (live != null) {
      return TranscriptWindow(
        launch: launch,
        connection: live,
        terminal: terminal,
        notifications: Notifications(
          channel: launch.notifChannel,
          env: terminalEnv((name) => Platform.environment[name]),
        ),
        splash: stdout.hasTerminal,
        copyOnSelect: launch.copyOnSelect,
      );
    }
    return Actions(
      bindings: [
        Binding('ctrl+c', 'quit', () => exitApp(context)),
        Binding('ctrl+d', 'quit', () => exitApp(context)),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 1),
        child: switch (state) {
          null => _rows(context, StartState.idle),
          final state => ListenableBuilder(
            listenable: state,
            builder: (context) => _rows(context, state.value),
          ),
        },
      ),
    );
  }

  Widget _rows(BuildContext context, StartState state) {
    final status = statusLine(state, launch.name);
    final failed =
        state.phase == StartPhase.failed || state.phase == StartPhase.gone;
    return Column(
      children: [
        // As the original's header: chord bold, the rest dim.
        Text.rich(
          TextSpan(
            '',
            children: [
              const TextSpan('chord', style: Style.bold),
              TextSpan(
                windowLine(launch).substring('chord'.length),
                style: Style.dim,
              ),
            ],
          ),
          softWrap: false,
          overflow: TextOverflow.ellipsis,
        ),
        if (status != null)
          _row(status, failed ? Theme.of(context).error : Style.dim),
        Text(quitHint, style: Style.dim),
        for (final (i, line) in detailLines(state).indexed)
          _row(line, i == 0 ? Style.dim : Style.plain),
      ],
    );
  }

  Widget _row(String text, Style style) => Text(
    printable(text),
    style: style,
    softWrap: false,
    overflow: TextOverflow.ellipsis,
  );
}
