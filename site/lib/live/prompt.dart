import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord_tui/chord_tui.dart';

/// chord's prompt, live, as `tool/prompt.dart` has it: what is sent shows in
/// the room above the input, and the input clears. No agent answers.
class LivePrompt extends StatefulWidget {
  /// The prompt fixture.
  const LivePrompt({super.key, this.onLines});

  /// Told the draft's line count as it changes, for a room that grows.
  final void Function(int lines)? onLines;

  @override
  State<LivePrompt> createState() => _LivePromptState();
}

class _LivePromptState extends State<LivePrompt> {
  final _draft = TextAreaController();
  var _sent = '';
  var _lines = 1;

  @override
  void initState() {
    super.initState();
    _draft.addListener(_drafted);
  }

  void _drafted() {
    final lines = '\n'.allMatches(_draft.text).length + 1;
    if (lines == _lines) return;
    _lines = lines;
    widget.onLines?.call(lines);
  }

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
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
  );
}
