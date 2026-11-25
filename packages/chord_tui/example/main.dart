import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const App());

/// A tool call's output under a fold that ctrl+o opens and closes, with the
/// keys listed below it; ctrl+q quits.
class App extends StatefulWidget {
  /// The example.
  const App({super.key});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding(
        'ctrl+o',
        'Toggle tool details',
        () => setState(() => _expanded = !_expanded),
      ),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Column(
      children: [
        Expanded(
          child: Fold(
            title: 'Run checks',
            open: _expanded,
            child: Code(r'$ dart analyze', language: 'shell'),
          ),
        ),
        const KeyHelp(),
      ],
    ),
  );
}
