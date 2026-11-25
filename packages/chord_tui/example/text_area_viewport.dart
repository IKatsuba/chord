import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const TextAreaViewportExample());

/// A framed multiline editor: Enter sends what is written above it and
/// clears it, shift+enter adds a line, and four rows scroll with the
/// cursor, whose line and the rows shown are labelled under the frame.
class TextAreaViewportExample extends StatefulWidget {
  /// The example.
  const TextAreaViewportExample({super.key});

  @override
  State<TextAreaViewportExample> createState() =>
      _TextAreaViewportExampleState();
}

class _TextAreaViewportExampleState extends State<TextAreaViewportExample> {
  final _draft = TextAreaController();
  var _sent = '';
  TextAreaLayout? _viewport;

  void _layoutChanged(TextAreaLayout layout) {
    setState(() => _viewport = layout);
  }

  /// The rows the editor shows at most.
  static const _rows = 4;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  void _send(String text) {
    setState(() => _sent = text);
    _draft.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Actions(
      bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
      child: Column(
        children: [
          Text('Text area', style: theme.accent),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Text(_sent),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Box(
              border: Border.single,
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Row(
                children: [
                  SizedBox(
                    width: 2,
                    child: Column(
                      children: [
                        for (final row
                            in _viewport?.shownRows ?? <TextAreaRow>[])
                          Text('${row.line + 1}', style: theme.dim),
                      ],
                    ),
                  ),
                  Expanded(
                    child: TextArea(
                      controller: _draft,
                      autofocus: true,
                      maxHeight: _rows,
                      placeholder: 'Write a message',
                      onSubmit: _send,
                      onLayoutChanged: _layoutChanged,
                    ),
                  ),
                ],
              ),
            ),
          ),
          ListenableBuilder(
            listenable: _draft,
            builder: (context) =>
                Text(_label(), style: theme.dim, softWrap: false),
          ),
          Text(
            'Enter sends · Shift+Enter adds a line · Ctrl+Q quits',
            softWrap: false,
            overflow: TextOverflow.ellipsis,
          ),
          const KeyHelp(),
        ],
      ),
    );
  }

  /// Where the cursor is and which rows show, counted from one, as the
  /// editor's own scrolling settled them.
  String _label() {
    final layout = _draft.lastLayout;
    if (layout == null) return '';
    final first = layout.rowOffset + 1;
    final last = layout.rowOffset + layout.height;
    return 'line ${_draft.cursorLine + 1}, '
        'column ${_draft.cursorColumn + 1} · '
        'rows $first–$last of ${layout.rows.length}';
  }
}
