import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const ScrollViewExample());

/// A page that scrolls over a live editor: ↑↓, PgUp/PgDn, Home/End and the
/// wheel scroll it, Tab moves into the editor and scrolls it into sight,
/// typing keeps its cursor in view, and Esc gives the page its keys back.
class ScrollViewExample extends StatefulWidget {
  /// The example.
  const ScrollViewExample({super.key});

  @override
  State<ScrollViewExample> createState() => _ScrollViewExampleState();
}

class _ScrollViewExampleState extends State<ScrollViewExample> {
  final _scroll = ScrollController();
  final _page = FocusNode();
  final _editor = FocusNode();

  @override
  void dispose() {
    _scroll.dispose();
    _page.dispose();
    _editor.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      ...scrollBindings(
        _scroll,
        keys: const ScrollKeys(lineUp: ['up'], lineDown: ['down']),
      ),
      Binding('tab', 'Edit the note', _editor.requestFocus),
      Binding('esc', 'Back to the page', _page.requestFocus),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Column(
      children: [
        Expanded(
          child: Focus(
            focusNode: _page,
            autofocus: true,
            child: Scrollbar(
              controller: _scroll,
              child: SingleChildScrollView(
                controller: _scroll,
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (var i = 1; i <= 30; i++)
                      Text('Paragraph $i of the page above the note.'),
                    Text(''),
                    Box(
                      title: 'Note',
                      child: TextArea(focusNode: _editor, maxHeight: 6),
                    ),
                    Text(''),
                    for (var i = 31; i <= 60; i++)
                      Text('Paragraph $i of the page below the note.'),
                  ],
                ),
              ),
            ),
          ),
        ),
        const KeyHelp(),
      ],
    ),
  );
}
