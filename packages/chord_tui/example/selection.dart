import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const SelectionDemo());

/// A selection, lazy-source and held-scroll demo without clipboard access.
class SelectionDemo extends StatefulWidget {
  /// Starts a fixed virtual log with a focused multiline editor.
  const SelectionDemo({super.key});
  @override
  State<SelectionDemo> createState() => _FixtureState();
}

class _FixtureState extends State<SelectionDemo> {
  final _selection = SelectionController();
  final _scroll = ScrollController(follow: Follow.bottom);
  final _draft = TextAreaController(text: 'draft stays focused');
  final _sources = [
    for (var i = 0; i < 12; i++)
      SelectionSource.markdown(
        id: i,
        revision: 0,
        copyCodeBlocks: true,
        text:
            'Record $i · 日本語 👩‍💻 e\u0301\n\n'
            '```dart\n\tprint("record $i");\n\nend\n```',
      ),
  ];
  var _message = 'Drag header, log or draft; no clipboard is used.';
  var _overlay = false, _known = true;
  var _tone = 0;
  var _dragging = false, _wasFollowing = false, _moved = false;

  @override
  void dispose() {
    _dragging = false;
    _scroll.release();
    _selection.dispose();
    _scroll.dispose();
    _draft.dispose();
    super.dispose();
  }

  void _selectionChanged(SelectionValue value) {
    if (value.phase == SelectionPhase.changing && !_dragging) {
      _wasFollowing = _scroll.isFollowing;
      _moved = false;
      _dragging = true;
      _scroll.hold();
    } else if (value.phase != SelectionPhase.changing && _dragging) {
      _dragging = false;
      _scroll.release();
      if (_wasFollowing && !_moved) _scroll.toBottom();
    }
  }

  void _explicitScroll(void Function() action) {
    if (_dragging) _moved = true;
    action();
  }

  void _append() {
    final i = _sources.length;
    setState(
      () => _sources.add(
        SelectionSource.markdown(
          id: i,
          revision: 0,
          copyCodeBlocks: true,
          text:
              'Record $i · appended while following or held\n\n'
              '```dart\n\tprint("record $i");\n\nend\n```',
        ),
      ),
    );
    _scroll.markNews();
  }

  void _recordCode(MarkdownCodeBlock block) {
    _selection.clear();
    setState(
      () => _message = 'Code snapshot: ${block.text.replaceAll('\n', ' ↵ ')}',
    );
  }

  void _snapshot() {
    final value = _selection.snapshot();
    setState(
      () => _message = value == null
          ? 'Snapshot unresolved'
          : '${value.phase.name}: ${value.text.replaceAll('\n', ' ↵ ')}',
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = [
      ThemeData.dark(),
      ThemeData.light(),
      ThemeData.plain(),
    ][_tone];
    final delegate = SelectionChildDelegate(
      itemCount: _sources.length,
      idAt: (i) => i,
      indexOfId: (id) =>
          id is int && id >= 0 && id < _sources.length ? id : null,
      sourceAt: (i) => _sources[i],
    );
    return Theme(
      data: theme,
      child: Actions(
        bindings: [
          for (final binding in scrollBindings(
            _scroll,
            keys: const ScrollKeys(
              lineUp: ['shift+up'],
              lineDown: ['shift+down'],
            ),
          ))
            Binding(
              '${binding.chord}',
              binding.description,
              () => _explicitScroll(binding.onInvoke),
              enabled: binding.enabled,
            ),
          Binding('f2', 'Append log entry', _append),
          Binding('ctrl+l', 'Clear selection', _selection.clear),
          Binding('ctrl+s', 'Inspect synchronized snapshot', _snapshot),
          Binding(
            'ctrl+b',
            'Inspect last code block',
            () => _recordCode(_sources.last.codeBlocks.single),
          ),
          Binding(
            'ctrl+o',
            'Toggle known overlay',
            () => setState(() => _overlay = !_overlay),
          ),
          Binding(
            'ctrl+u',
            'Toggle unknown coverage',
            () => setState(() => _known = !_known),
          ),
          Binding(
            'ctrl+t',
            'Cycle theme',
            () => setState(() => _tone = (_tone + 1) % 3),
          ),
          Binding('ctrl+r', 'Reveal last code block', () {
            final revealed = _selection.revealCodeBlock(
              _sources.last.codeBlocks.single.id,
            );
            setState(() => _message = 'Reveal last: $revealed');
          }),
          Binding('ctrl+q', 'Quit', () => exitApp(context)),
        ],
        child: SelectionArea(
          controller: _selection,
          selectionStyle: theme.selection,
          onSelectionChanged: _selectionChanged,
          onSelectionFinalized: (value) => setState(
            () =>
                _message = 'Finalized ${value.text.length} characters; no copy',
          ),
          child: _CoverageGate(
            known: _known,
            child: Stack(
              children: [
                Column(
                  children: [
                    Text(
                      'Selection area · immutable source log',
                      style: theme.accent,
                    ),
                    SelectionContainer.disabled(
                      child: ListenableBuilder(
                        listenable: _scroll,
                        builder: (_) => Text(
                          'Known coverage: $_known · overlay: $_overlay · '
                          'held: ${_scroll.state.held} · following: ${_scroll.isFollowing}',
                          style: theme.dim,
                        ),
                      ),
                    ),
                    Expanded(
                      child: Listener(
                        onPointerSignal: (event) {
                          for (var i = 0; i < event.scrollDelta.y.abs(); i++) {
                            _explicitScroll(
                              event.scrollDelta.y < 0
                                  ? _scroll.lineUp
                                  : _scroll.lineDown,
                            );
                          }
                        },
                        child: ListView.builder(
                          controller: _scroll,
                          itemCount: _sources.length,
                          selectionDelegate: delegate,
                          itemVersion: (i) => _sources[i].revision,
                          itemBuilder: (_, i) => Markdown.fromSelectionSource(
                            _sources[i],
                            onCopyCodeBlock: _recordCode,
                          ),
                        ),
                      ),
                    ),
                    TextArea(
                      controller: _draft,
                      autofocus: true,
                      maxHeight: 3,
                      unhandledKeys: const {
                        'home',
                        'end',
                        'ctrl+l',
                        'ctrl+s',
                        'ctrl+b',
                        'ctrl+o',
                        'ctrl+u',
                        'ctrl+t',
                        'ctrl+r',
                      },
                    ),
                    SelectionContainer.disabled(
                      child: Text(
                        _message,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.dim,
                      ),
                    ),
                    SelectionContainer.disabled(
                      child: KeyHelp.builder(
                        builder: (_, bindings, pending) => Text(
                          'C-l clear · C-s snapshot · C-o overlay · C-u coverage · '
                          'C-t theme · C-r reveal · C-b code · F2 append · S-↑/↓ scroll · PgUp/PgDn · C-q quit',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.dim,
                        ),
                      ),
                    ),
                  ],
                ),
                if (_overlay)
                  Positioned(
                    left: 6,
                    top: 4,
                    child: SelectionContainer.disabled(
                      child: Box(
                        border: Border.single,
                        child: Text('Known overlay'),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _CoverageGate extends SingleChildRenderObjectWidget {
  const _CoverageGate({required this.known, required super.child});
  final bool known;
  @override
  RenderBox createRenderObject(BuildContext context) => _RenderGate(known);
  @override
  void updateRenderObject(BuildContext context, _RenderGate box) =>
      box.known = known;
}

class _RenderGate extends RenderProxyBox {
  _RenderGate(this.known);
  bool known;
  @override
  PaintCoverage? describePaintCoverage(Rect localClip) =>
      known ? const PaintCoverage.empty(_RenderGate) : null;
}
