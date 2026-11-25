import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

/// The sample edited and copied by the service demo.
const serviceSample = 'Terminal services\nSecond sample line';

Future<void> main(List<String> args) async {
  if (args.contains('--editor-child')) {
    await _editorChild(args);
    return;
  }
  final directory = Directory.systemTemp.createTempSync('terminal-services-');
  final file = File('${directory.path}/sample.md')
    ..writeAsStringSync(serviceSample);
  final scripted = args.contains('--scripted-editor');
  final terminal = StdioTerminal(
    editorLauncher: scripted
        ? (
            executable,
            arguments, {
            workingDirectory,
            required environment,
            required mode,
          }) async {
            final child = await Process.start(
              Platform.resolvedExecutable,
              [
                if (Platform.script.path.endsWith('.dart'))
                  Platform.script.toFilePath(),
                '--editor-child',
                if (args.contains('--editor-fails')) '--fail',
                arguments.last,
              ],
              workingDirectory: workingDirectory,
              environment: environment,
              includeParentEnvironment: false,
              mode: mode,
            );
            return child.exitCode;
          }
        : null,
  );
  Future<void> cleanup() async {
    try {
      await terminal.close();
    } finally {
      if (directory.existsSync()) directory.deleteSync(recursive: true);
    }
  }

  try {
    await runApp(
      TerminalServicesExample(terminal: terminal, file: file),
      terminal: terminal,
      exitProcess: false,
      beforeExit: cleanup,
    );
  } finally {
    await cleanup();
  }
}

Future<void> _editorChild(List<String> args) async {
  final failed = args.contains('--fail');
  final file = File(args.last);
  final rows = stdout.hasTerminal ? stdout.terminalLines : 24;
  stdout.write('\x1b[0m\x1b[2J\x1b[H');
  for (var row = 1; row <= rows; row++) {
    final text = row == 1
        ? 'SCRIPTED EDITOR OWNS TERMINAL'
        : row == 3
        ? 'Press Enter to return (exit ${failed ? 7 : 0}).'
        : 'Scripted editor row $row';
    stdout.write('\x1b[$row;1H$text\x1b[K');
  }
  stdout.write('\x1b[4;1H');
  await stdout.flush();
  stdin.readLineSync();
  if (!failed) {
    final text = file.readAsStringSync();
    if (text.isNotEmpty) {
      file.writeAsStringSync('$text\nEdited by scripted child');
    }
  }
  exitCode = failed ? 7 : 0;
}

/// A caller-owned sample file, editable text and terminal service actions.
class TerminalServicesExample extends StatefulWidget {
  /// A service demo with no editor invocation until its described key is used.
  const TerminalServicesExample({
    super.key,
    required this.terminal,
    required this.file,
    this.initialText = serviceSample,
  });

  /// The terminal whose effects the demo invokes.
  final Terminal terminal;

  /// The demo's owned temporary sample file.
  final File file;

  /// The initial text, empty when testing an empty sample.
  final String initialText;

  @override
  State<TerminalServicesExample> createState() => _ServicesState();
}

const _serviceKeys = {
  'ctrl+y',
  'ctrl+g',
  'ctrl+b',
  'ctrl+n',
  'ctrl+x n',
  'ctrl+t',
  'ctrl+q',
};
const _helpKeys = {..._serviceKeys, 'super+left', 'super+right'};

class _ServicesState extends State<TerminalServicesExample> {
  late final TextAreaController _draft;
  var _editor = 'ready';
  var _lastKey = 'none';
  var _editing = false;

  @override
  void initState() {
    super.initState();
    _draft = TextAreaController(text: widget.initialText)
      ..addListener(_changed);
  }

  void _changed() => setState(() {});
  @override
  void dispose() {
    _draft.removeListener(_changed);
    _draft.dispose();
    super.dispose();
  }

  void _action(String key, void Function() action) {
    setState(() => _lastKey = key);
    action();
  }

  Future<void> _edit() async {
    if (_editing) return;
    _editing = true;
    setState(() => _editor = 'opening');
    try {
      // The example owns its file and deliberately writes exactly the draft.
      widget.file.writeAsStringSync(_draft.text);
      final code = await widget.terminal.runEditor(widget.file.path);
      if (!mounted) return;
      if (code == 0) _draft.text = widget.file.readAsStringSync();
      setState(() => _editor = 'exited $code');
    } catch (error) {
      if (mounted) setState(() => _editor = 'failed: $error');
    } finally {
      _editing = false;
    }
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding(
        'ctrl+y',
        'Copy sample',
        () => _action(
          'ctrl+y',
          () => widget.terminal.copyToClipboard(_draft.text),
        ),
      ),
      Binding(
        'ctrl+g',
        'Open editor',
        () => _action('ctrl+g', () {
          unawaited(_edit());
        }),
      ),
      Binding('ctrl+b', 'Bell', () => _action('ctrl+b', widget.terminal.bell)),
      Binding(
        'ctrl+n',
        'OSC9',
        () => _action(
          'ctrl+n',
          () => widget.terminal.notify(
            'Sample is ready',
            channel: NotificationChannel.osc9,
            title: 'Terminal services',
          ),
        ),
      ),
      Binding(
        'ctrl+x n',
        'OSC777',
        () => _action(
          'ctrl+x n',
          () => widget.terminal.notify(
            'Sample is ready',
            channel: NotificationChannel.osc777,
            title: 'Terminal services',
          ),
        ),
      ),
      Binding(
        'ctrl+t',
        'Title',
        () => _action(
          'ctrl+t',
          () => widget.terminal.setTitle('Terminal services'),
        ),
      ),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Terminal services', style: Theme.of(context).accent),
        Text(
          'Copy sample: ${_draft.text.split('\n').first}',
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        Text('Editor: $_editor'),
        Text('Last key: $_lastKey'),
        Expanded(
          child: Box(
            border: Border.single,
            padding: const EdgeInsets.all(1),
            child: TextArea(
              controller: _draft,
              autofocus: true,
              maxHeight: unbounded,
              unhandledKeys: {
                for (final key in _serviceKeys) key.split(' ').first,
              },
              onKey: (event) {
                setState(() => _lastKey = '${event.combo}');
                return false;
              },
            ),
          ),
        ),
        KeyHelp.builder(
          builder: (context, bindings, pending) => Text(
            [
              for (final binding in bindings)
                if (_helpKeys.contains('${binding.chord}'))
                  '${binding.chord} ${binding.description}',
              if (pending.isNotEmpty) '${pending.join(' ')} …',
            ].join(' · '),
            style: Theme.of(context).dim,
          ),
        ),
      ],
    ),
  );
}
