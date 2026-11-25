import 'package:chord_tui/chord_tui.dart';

void main(List<String> args) => runApp(
  const MarkdownControlsFixture(),
  theme: args.contains('--plain')
      ? ThemeData.plain()
      : args.contains('--light')
      ? ThemeData.light()
      : ThemeData.dark(),
);

/// Exercises Markdown's public controls without any clipboard or port policy.
class MarkdownControlsFixture extends StatefulWidget {
  const MarkdownControlsFixture({super.key});
  @override
  State<MarkdownControlsFixture> createState() => _ControlsState();
}

class _ControlsState extends State<MarkdownControlsFixture> {
  final _selection = SelectionController();
  final _draft = TextAreaController(text: 'draft');
  late SelectionSource _source;
  CodeBlockId? _picked;
  var _closed = false, _covered = false, _revision = 0, _copies = 0;
  var _copied = '', _snapshot = '';
  @override
  void initState() {
    super.initState();
    _replace();
  }

  void _replace() {
    _source = SelectionSource.markdown(
      id: 'controls',
      revision: _revision,
      text:
          '```ts\n\tcopy body\n\ntail\n```\n\n> ```console\n> quoted body\n> ```\n\n```dart\nstreaming body${_closed ? '\n```' : ''}',
      copyCodeBlocks: true,
      previous: _revision == 0 ? null : _source,
    );
  }

  void _copy(MarkdownCodeBlock requested) {
    final current = _source.codeBlocks
        .where(
          (b) =>
              b.id == requested.id &&
              b.revision == requested.revision &&
              b.complete,
        )
        .firstOrNull;
    if (current == null) return;
    _selection.clear();
    setState(() {
      _copies++;
      _copied = current.text.replaceAll('\t', r'\t').replaceAll('\n', r'\n');
      _picked = null;
    });
  }

  @override
  void dispose() {
    _selection.dispose();
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('ctrl+q', 'Quit controls fixture', () => exitApp(context)),
      Binding(
        'f2',
        'Close or reopen the final code fence',
        () => setState(() {
          _closed = !_closed;
          _revision++;
          _replace();
        }),
      ),
      Binding(
        'f3',
        'Cover or expose the first code border',
        () => setState(() => _covered = !_covered),
      ),
      Binding(
        'ctrl+b',
        'Emphasize the next complete code block',
        () => setState(() {
          final ids = _source.codeBlocks
              .where((b) => b.complete)
              .map((b) => b.id)
              .toList();
          final at = ids.indexWhere((id) => id == _picked);
          _picked = ids.isEmpty ? null : ids[(at + 1) % ids.length];
        }),
      ),
      Binding('ctrl+y', 'Record the emphasized code block', () {
        final block = _source.codeBlocks
            .where((b) => b.id == _picked && b.complete)
            .firstOrNull;
        if (block != null) _copy(block);
      }),
      Binding(
        'ctrl+s',
        'Read the current selected text',
        () => setState(
          () => _snapshot =
              _selection.snapshot()?.text.replaceAll('\n', r'\n') ??
              'unresolved',
        ),
      ),
    ],
    child: SelectionArea(
      controller: _selection,
      selectionStyle: const Style(inverse: true),
      child: Column(
        children: [
          SelectionContainer.disabled(
            child: Column(
              children: [
                Text('Markdown controls · recording only', style: Style.bold),
                Text(
                  'F2 close/open · F3 cover · ctrl+b emphasize · ctrl+y copy',
                  softWrap: false,
                  maxLines: 1,
                ),
                Text('ctrl+s range · ctrl+q quit'),
              ],
            ),
          ),
          Stack(
            children: [
              Markdown.fromSelectionSource(
                _source,
                selectedCodeBlock: _picked,
                onCopyCodeBlock: _copy,
              ),
              if (_covered)
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  child: Text(
                    'covered border ' * 20,
                    softWrap: false,
                    maxLines: 1,
                  ),
                ),
            ],
          ),
          TextArea(
            controller: _draft,
            autofocus: true,
            unhandledKeys: const {'ctrl+b', 'ctrl+y', 'ctrl+s'},
          ),
          SelectionContainer.disabled(
            child: Column(
              children: [
                Text('Copies $_copies: $_copied', softWrap: false, maxLines: 1),
                Text('Range: $_snapshot', softWrap: false, maxLines: 1),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
