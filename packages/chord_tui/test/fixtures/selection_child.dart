import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const SelectionChildFixture());

/// Shows layout-preserving source eligibility with no clipboard or port policy.
class SelectionChildFixture extends StatefulWidget {
  const SelectionChildFixture({super.key});
  @override
  State<SelectionChildFixture> createState() => _FixtureState();
}

class _FixtureState extends State<SelectionChildFixture> {
  final _selection = SelectionController();
  final _scroll = ScrollController();
  final _first = SelectionSource.text(
    id: 'first',
    revision: 0,
    text: const TextSpan('first eligible'),
  );
  final _decoration = SelectionSource.text(
    id: 'decoration',
    revision: 0,
    text: TextSpan(
      'wrapped decoration, drawn in place and omitted from selection. ' * 5,
    ),
  );
  final _code = SelectionSource.markdown(
    id: 'code',
    revision: 0,
    text: '```dart\nprint("decorative code");\n```',
  );
  final _last = SelectionSource.text(
    id: 'last',
    revision: 0,
    text: const TextSpan('last eligible'),
  );
  late SelectionSource _middle, _source;
  var _enabled = false, _revision = 0;
  var _snapshot = '', _blocks = 0;

  @override
  void initState() {
    super.initState();
    _middle = SelectionSource.group(
      id: 'middle',
      revision: 0,
      children: [
        SelectionSourceChild(source: _decoration),
        SelectionSourceChild(source: _code),
      ],
    );
    _replace();
    _selection.addListener(_changed);
  }

  void _replace([SelectionSource? previous]) {
    _source = SelectionSource.group(
      id: 'root',
      revision: _revision,
      previous: previous,
      children: [
        SelectionSourceChild(source: _first),
        SelectionSourceChild(source: _middle, selectable: _enabled),
        SelectionSourceChild(source: _last),
      ],
    );
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _selection.removeListener(_changed);
    _selection.dispose();
    _scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final furniture = Column(
      children: [
        Text.fromSelectionSource(_decoration),
        Markdown.fromSelectionSource(_code),
      ],
    );
    return Actions(
      bindings: [
        Binding(
          'f2',
          'Toggle middle eligibility',
          () => setState(() {
            final old = _source;
            _enabled = !_enabled;
            _revision++;
            _replace(old);
          }),
        ),
        Binding(
          'ctrl+s',
          'Read current snapshot',
          () => setState(
            () => _snapshot =
                _selection.snapshot()?.text.replaceAll('\n', r'\n') ??
                'unresolved',
          ),
        ),
        Binding(
          'ctrl+b',
          'Query visible code',
          () => setState(() => _blocks = _selection.visibleCodeBlocks().length),
        ),
        Binding('ctrl+l', 'Clear selection', _selection.clear),
        Binding('ctrl+q', 'Quit', () => exitApp(context)),
        ...scrollBindings(_scroll),
      ],
      child: Column(
        children: [
          Text(
            'Source child · middle ${_enabled ? 'included' : 'excluded'} · phase ${_selection.value.phase.name}',
          ),
          Text(
            'Drag first to last: excluded decoration keeps its wrapped rows.',
          ),
          Text(
            'F2 eligibility · C-s snapshot · C-b code query · C-l clear · C-q quit',
          ),
          Expanded(
            child: SelectionArea(
              controller: _selection,
              selectionStyle: const Style(inverse: true),
              child: ListView.builder(
                controller: _scroll,
                itemCount: 1,
                itemVersion: (_) => _source.revision,
                selectionDelegate: SelectionChildDelegate(
                  itemCount: 1,
                  idAt: (_) => _source.id,
                  indexOfId: (id) => id == _source.id ? 0 : null,
                  sourceAt: (_) => _source,
                ),
                itemBuilder: (_, _) => Column(
                  children: [
                    Text.fromSelectionSource(_first),
                    if (_enabled)
                      furniture
                    else
                      SelectionContainer.disabled(child: furniture),
                    Text.fromSelectionSource(_last),
                  ],
                ),
              ),
            ),
          ),
          Text(
            'Snapshot: $_snapshot',
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text('Visible eligible code: $_blocks'),
        ],
      ),
    );
  }
}
