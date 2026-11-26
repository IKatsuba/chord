// A chord_tui app over WebTerminal, for web_terminal_browser_test.dart:
// `c` copies, `o` opens a link, `t` sets the title, Shift+Enter is a
// kitty key; Ctrl+C quits. The console says each size laid out, each key
// handled and how runApp ended: the screen is written only where it
// changes.
import 'dart:js_interop';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/web.dart';

@JS('console.log')
external void _log(JSString line);

class _App extends StatefulWidget {
  const _App(this.terminal);

  final Terminal terminal;

  @override
  State<_App> createState() => _AppState();
}

class _AppState extends State<_App> {
  void _did(String what, [void Function()? action]) {
    action?.call();
    _log('did $what'.toJS);
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding(
        'c',
        'Copy',
        () => _did('copied', () => widget.terminal.copyToClipboard('from key')),
      ),
      Binding(
        'o',
        'Open',
        () => _did('opened', () => widget.terminal.openUrl('https://a.test/')),
      ),
      Binding(
        't',
        'Title',
        () => _did('titled', () => widget.terminal.setTitle('chord_tui page')),
      ),
      Binding('shift+enter', 'Kitty', () => _did('kitty')),
    ],
    child: LayoutBuilder(
      builder: (context, constraints) {
        final size = '${constraints.maxWidth}x${constraints.maxHeight}';
        _log('size $size'.toJS);
        return Text('size $size');
      },
    ),
  );
}

Future<void> main() async {
  final terminal = WebTerminal(mouse: true);
  try {
    await runApp(
      _App(terminal),
      terminal: terminal,
      exitProcess: false,
      handleSignals: false,
    );
    _log('runApp returned'.toJS);
  } catch (error) {
    _log('runApp failed: $error'.toJS);
  }
}
