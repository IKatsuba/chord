import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const PromptFixture());

/// A prompt fixture for checking wrapping, gutter arrows and history keys.
class PromptFixture extends StatefulWidget {
  const PromptFixture({super.key});

  @override
  State<PromptFixture> createState() => _PromptFixtureState();
}

class _PromptFixtureState extends State<PromptFixture> {
  final _draft = TextAreaController();
  String _sent = '';

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
    child: LayoutBuilder(
      builder: (context, constraints) => Column(
        children: [
          Expanded(child: Text(_sent)),
          PromptInput(
            controller: _draft,
            windowRows: constraints.maxHeight,
            onSubmit: (text) {
              setState(() => _sent = text);
              _draft.clear();
            },
            onOlder: () {},
            onNewer: () {},
          ),
        ],
      ),
    ),
  );
}
