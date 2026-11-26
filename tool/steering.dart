import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/shell.dart' as shell;
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';

import '../test/fixtures/steering_agent.dart';

/// Owns the in-memory agent and isolated files of the real steering window.
final class SteeringFixture {
  SteeringFixture._(
    this.directory, {
    required bool supported,
    required bool cutsCalls,
  }) {
    connection = StartConnection(
      command: 'memory',
      agent: 'fake',
      cwd: directory.path,
      open:
          ({
            required command,
            env,
            required cwd,
            required onTraffic,
            required onPermission,
            relay,
            cancellationToken,
          }) {
            final agent = SteeringAgent(
              supported: supported,
              cutsCalls: cutsCalls,
            );
            agents.add(agent);
            return agent.open(
              command: command,
              env: env,
              cwd: cwd,
              onTraffic: onTraffic,
              onPermission: onPermission,
              relay: relay,
              cancellationToken: cancellationToken,
            );
          },
    )..start();
  }
  final Directory directory;
  late final StartConnection connection;
  final agents = <SteeringAgent>[];
  final _shells = <_RecordedShell>[];
  Future<void>? _closing;
  final _help = ValueNotifier(false);
  SteeringAgent get agent => agents.last;

  /// Creates only a synthetic notes file and temporary state/config roots.
  static Future<SteeringFixture> create({
    bool supported = true,
    bool cutsCalls = false,
  }) async {
    final directory = await Directory.systemTemp.createTemp(
      'chord-steering-window-',
    );
    await File('${directory.path}/notes.txt').writeAsString('synthetic notes');
    return SteeringFixture._(
      directory,
      supported: supported,
      cutsCalls: cutsCalls,
    );
  }

  /// Closes every admitted in-memory connection before deleting owned files.
  Future<void> close() => _closing ??= () async {
    await connection.close();
    await Future.wait(_shells.map((process) => process.ended));
    _help.dispose();
    if (await directory.exists()) await directory.delete(recursive: true);
  }();

  shell.ShellProcess _runShell(String command, shell.ShellOptions options) {
    final process = _RecordedShell(options);
    _shells.add(process);
    return process;
  }

  /// The actual window, with agent-only controls outside its geometry.
  Widget view() => ListenableBuilder(
    listenable: connection.app,
    builder: (context) {
      final current = agents.lastOrNull;
      return Actions(
        bindings: [
          Binding('ctrl+q', 'Quit fixture', () => exitApp(context)),
          Binding(
            'f1',
            'Toggle fixture controls',
            () => _help.value = !_help.value,
          ),
          Binding(
            'f2',
            'Accept pending fake steer',
            () => current?.answerSteer(),
          ),
          Binding(
            'f3',
            'Refuse pending fake steer',
            () => current?.answerSteer('promptRequired'),
          ),
          Binding(
            'f4',
            'Finish current fake prompt',
            () => current?.finishPrompt(),
          ),
          Binding('f5', 'Toggle fake open call', () => current?.toggleCall()),
          Binding('f6', 'Ask fake permission', () => current?.askPermission()),
          Binding(
            'f7',
            'Emit fake late text',
            () => current?.chunk(' Late fixture work.'),
          ),
        ],
        child: ListenableBuilder(
          listenable: _help,
          builder: (context) => Stack(
            children: [
              TranscriptWindow(
                launch: const Launch(
                  name: 'fake',
                  agent: null,
                  agentCommand: 'memory',
                  version: '0.0.1',
                  directory: 'fixture-project',
                ),
                connection: connection,
                runShell: _runShell,
                readSessionRecords: ({cancellationToken}) async => [],
              ),
              if (_help.value)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  bottom: 0,
                  child: _FixtureHelp(
                    onClose: () => _help.value = false,
                    onQuit: () => exitApp(context),
                  ),
                ),
            ],
          ),
        ),
      );
    },
  );
}

class _FixtureHelp extends StatefulWidget {
  const _FixtureHelp({required this.onClose, required this.onQuit});
  final void Function() onClose, onQuit;
  @override
  State<_FixtureHelp> createState() => _FixtureHelpState();
}

class _FixtureHelpState extends State<_FixtureHelp> {
  final _scroll = ScrollController();
  static const _controls = {
    'ctrl+q': 'Quit fixture',
    'f1': 'Close controls',
    'f2': 'Accept pending steer',
    'f3': 'Refuse pending steer',
    'f4': 'Finish current prompt',
    'f5': 'Toggle open call',
    'f6': 'Ask permission',
    'f7': 'Emit late text',
  };
  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, room) {
      final body = (room.maxHeight - 2).clamp(0, unbounded);
      return SelectionContainer.disabled(
        child: Box(
          background: Style.plain,
          child: FocusScope(
            autofocus: true,
            child: Actions(
              bindings: [
                for (final control in _controls.entries)
                  Binding(
                    control.key,
                    control.value,
                    control.key == 'f1'
                        ? widget.onClose
                        : control.key == 'ctrl+q'
                        ? widget.onQuit
                        : () {},
                  ),
                if (body > 0 && room.maxWidth > 0)
                  ...scrollBindings(
                    _scroll,
                    keys: const ScrollKeys(lineUp: ['up'], lineDown: ['down']),
                  ),
              ],
              child: Focus(
                autofocus: true,
                onKey: (event) =>
                    !_controls.containsKey(event.combo.toString()) &&
                    !(body > 0 &&
                        room.maxWidth > 0 &&
                        const {
                          'up',
                          'down',
                          'pageup',
                          'pagedown',
                          'home',
                          'end',
                        }.contains(event.combo.toString())),
                onPaste: (_) => true,
                child: Column(
                  children: [
                    if (room.maxHeight > 1)
                      Padding(
                        padding: const EdgeInsets.only(left: 1),
                        child: Text(
                          'Fixture controls',
                          softWrap: false,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                    if (body > 0)
                      Expanded(
                        child: KeyHelp.builder(
                          builder: (_, bindings, pending) {
                            final active = {
                              for (final b in bindings) b.chord.toString(): b,
                            };
                            final lines = [
                              for (final key in _controls.keys)
                                if (active[key] case final binding?)
                                  '$key  ${binding.description}',
                            ];
                            return Listener(
                              onPointerSignal: (event) {
                                if (room.maxWidth <= 0 ||
                                    _scroll.contentRows <= _scroll.viewRows) {
                                  return;
                                }
                                for (
                                  var i = 0;
                                  i < event.scrollDelta.y.abs();
                                  i++
                                ) {
                                  event.scrollDelta.y < 0
                                      ? _scroll.lineUp()
                                      : _scroll.lineDown();
                                }
                              },
                              child: ListView.builder(
                                controller: _scroll,
                                itemCount: lines.length,
                                itemBuilder: (_, i) => Padding(
                                  padding: const EdgeInsets.only(left: 1),
                                  child: Text(
                                    lines[i],
                                    softWrap: false,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    if (room.maxHeight > 0)
                      Padding(
                        padding: const EdgeInsets.only(left: 1),
                        child: Text(
                          'F1 close · ↑↓ scroll',
                          softWrap: false,
                          maxLines: 1,
                          overflow: TextOverflow.clip,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    },
  );
}

class _RecordedShell extends shell.ShellProcess {
  _RecordedShell(shell.ShellOptions options) {
    ended = Future(() {
      if (_stopped) return const shell.ShellEnd(stopped: true);
      options.onOutput?.call(
        shell.ShellStream.stdout,
        'recorded held output\n',
      );
      return const shell.ShellEnd(code: 0);
    });
  }
  bool _stopped = false;
  @override
  late final Future<shell.ShellEnd> ended;
  @override
  void stop() => _stopped = true;
}

Future<void> main(List<String> args) async {
  final fixture = await SteeringFixture.create(
    supported: !args.contains('--unsupported'),
    cutsCalls: args.contains('--claude'),
  );
  try {
    await runApp(
      fixture.view(),
      beforeExit: fixture.close,
      theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
      environment: {
        ...Platform.environment,
        'XDG_STATE_HOME': '${fixture.directory.path}/state',
        'XDG_CONFIG_HOME': '${fixture.directory.path}/config',
        if (args.contains('--plain')) 'NO_COLOR': '1',
      },
    );
  } finally {
    await fixture.close();
  }
}
