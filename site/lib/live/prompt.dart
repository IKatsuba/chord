import 'package:chord/ui/prompt/prompt_input.dart';
import 'package:chord_tui/chord_tui.dart';

/// chord's prompt, live, as `tool/prompt.dart` has it: what is sent shows in
/// the room above the input, and the input clears. No agent answers.
class LivePrompt extends StatefulWidget {
  /// The prompt fixture.
  const LivePrompt({super.key, this.onLines});

  /// Told the draft's rows as the editor lays them out (wrapped lines
  /// counted), for a room that grows.
  final void Function(int lines)? onLines;

  @override
  State<LivePrompt> createState() => _LivePromptState();
}

class _LivePromptState extends State<LivePrompt> {
  final _draft = TextAreaController();
  var _sent = '';
  var _lines = 1;

  // Laid out: the page may grow the room, once this layout is done.
  void _laidOut(TextAreaLayout layout) {
    final lines = layout.rows.length;
    if (lines == _lines) return;
    _lines = lines;
    context.owner.afterLayout(() {
      if (mounted) widget.onLines?.call(lines);
    });
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
          onLayoutChanged: _laidOut,
        ),
      ],
    ),
  );
}
