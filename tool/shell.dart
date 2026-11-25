// Deterministic local shell rows; this fixture starts no process or agent.
import 'dart:io';
import 'dart:async';
import 'package:chord/shell.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/ui/app/terminal.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/theme/theme.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';

Map<String, model.ShellRun> _sampleRuns() {
  final full = model.ShellRun(
    command:
        r'printf "line 01\nline 02\nline 03\nline 04\nline 05\nline 06\nline 07\nline 08\nline 09\nline 10\nline 11\nline 12\n"; printf "warning\n" >&2; exit 3',
    stdout: List.generate(
      12,
      (i) => 'line ${(i + 1).toString().padLeft(2, '0')}',
    ).join('\n'),
    stderr: 'warning\n',
    code: 3,
    running: false,
  );
  final runs = <String, model.ShellRun>{
    'full': full,
    'running': const model.ShellRun(
      command: 'printf ready; sleep',
      stdout: 'ready\n',
      running: true,
    ),
    'empty': const model.ShellRun(command: 'true', running: false, code: 0),
    'success': const model.ShellRun(
      command: 'printf ready',
      stdout: 'ready\n',
      running: false,
      code: 0,
    ),
    'stopped': const model.ShellRun(
      command: 'sleep',
      stdout: 'before\n',
      running: false,
      stopped: true,
    ),
    'error': const model.ShellRun(
      command: 'missing',
      running: false,
      error: 'shell did not start',
    ),
    'blank': const model.ShellRun(
      command: 'printf first\nprintf last',
      stdout: 'first\n\nlast\n',
      stderr: 'warning\n',
      running: false,
      code: 3,
    ),
    'cut': const model.ShellRun(
      command: 'output',
      stdout: 'kept output',
      running: false,
      truncated: true,
    ),
    'long': model.ShellRun(
      command: 'bounded long output',
      running: false,
      stdout: List.generate(
        100,
        (i) => 'row ${(i + 1).toString().padLeft(3, '0')}',
      ).join('\n'),
    ),
  };
  return Map.unmodifiable(runs);
}

/// A deterministic shell screen for headless checks and live inspection.
Widget shellFixture({String scenario = 'full'}) =>
    _Fixture(_sampleRuns(), scenario);

void main(List<String> args) {
  final runs = _sampleRuns();
  final selected = args.where(runs.containsKey).firstOrNull ?? 'full';
  runApp(
    _Fixture(runs, selected),
    theme: args.contains('--light') ? ThemeData.light() : ThemeData.dark(),
    environment: {
      ...Platform.environment,
      if (args.contains('--plain')) 'NO_COLOR': '1',
    },
  );
}

class _FixtureProcess extends ShellProcess {
  final done = Completer<ShellEnd>();
  @override
  Future<ShellEnd> get ended => done.future;
  @override
  void stop() {
    if (!done.isCompleted) done.complete(const ShellEnd(stopped: true));
  }
}

class _Fixture extends StatefulWidget {
  const _Fixture(this.runs, this.initial);
  final Map<String, model.ShellRun> runs;
  final String initial;
  @override
  State<_Fixture> createState() => _FixtureState();
}

class _FixtureState extends State<_Fixture> {
  final scroll = ScrollController(follow: Follow.bottom),
      selection = SelectionController();
  late String selected = widget.initial;
  var live = model.Transcript.empty;
  late final ShellCommands commands = ShellCommands(
    onAction: (_, action) {
      if (mounted) setState(() => live = reduceTranscript(live, action));
    },
    runner: (_, options) {
      options.onOutput!(ShellStream.stdout, 'ready\n');
      return _FixtureProcess();
    },
  );
  @override
  void initState() {
    super.initState();
    if (selected == 'running') {
      commands.run('fixture', 'printf ready; sleep', cwd: '.');
    }
  }

  void choose(String name) {
    commands.retire('fixture');
    setState(() {
      selected = name;
      live = model.Transcript.empty;
      scroll.toTop();
    });
    if (name == 'running') {
      commands.run('fixture', 'printf ready; sleep', cwd: '.');
    }
  }

  @override
  void dispose() {
    unawaited(commands.close());
    scroll.dispose();
    selection.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ChordThemeScope(
    child: Builder(
      builder: (context) => Actions(
        bindings: [
          Binding('ctrl+q', 'Quit', () => exitApp(context)),
          Binding(
            'esc',
            'Stop fixture command',
            () => commands.stop('fixture'),
          ),
          for (final (i, name) in widget.runs.keys.indexed)
            Binding('${i + 1}', 'Show $name', () => choose(name)),
        ],
        child: SelectionArea(
          controller: selection,
          selectionStyle: chordThemeOf(context).selection,
          child: Transcript(
            transcript: selected == 'running'
                ? live
                : model.Transcript.empty.withEntries([
                    model.ShellEntry('fixture', widget.runs[selected]!),
                  ]),
            controller: scroll,
            selectionNamespace: selected,
            shellStopKey: 'esc',
            footer: Text(
              '1 full · 2 running · 3 empty · 4 success · 5 stopped · 6 error · 7 blank · 8 cut · 9 long · esc stop · ctrl+q quit',
              style: Theme.of(context).dim,
            ),
          ),
        ),
      ),
    ),
  );
}
