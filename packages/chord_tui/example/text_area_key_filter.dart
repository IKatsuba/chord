import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const KeyFilterExample());

/// Native typing unless a live controller says the key belongs to the app.
class KeyFilterExample extends StatefulWidget {
  const KeyFilterExample({super.key});
  @override
  State<KeyFilterExample> createState() => _KeyFilterExampleState();
}

class _KeyFilterExampleState extends State<KeyFilterExample> {
  final input = TextAreaController();
  bool help = false;
  @override
  void dispose() {
    input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('?', 'Help when empty', () => setState(() => help = !help)),
      Binding('ctrl+c', 'Clear input', input.clear),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          help
              ? 'Help is open. ? toggles on empty input.'
              : 'Type draft? or press ? on empty input.',
        ),
        TextArea(
          controller: input,
          autofocus: true,
          shouldHandleKey: (event) => event.key != '?' || input.text.isNotEmpty,
        ),
        const KeyHelp(),
      ],
    ),
  );
}
