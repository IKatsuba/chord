import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const MouseExample());

/// Typed mouse reports alongside a keyboard-scrolled log and a focused draft.
class MouseExample extends StatefulWidget {
  /// The public Listener fixture, with keyboard equivalents for log actions.
  const MouseExample({super.key});
  @override
  State<MouseExample> createState() => _MouseState();
}

class _MouseState extends State<MouseExample> {
  final _capture = PointerCaptureController();
  final _scroll = ScrollController(initialOffset: 5);
  final _draft = TextAreaController(text: 'draft stays here');
  final _lines = [for (var i = 0; i < 100; i++) 'Sample log row $i'];
  var _reports = 0;
  var _last = 'none';

  @override
  void dispose() {
    _capture.dispose();
    _scroll.dispose();
    _draft.dispose();
    super.dispose();
  }

  void _record(MouseEvent event) {
    final modifiers = [
      if (event.shift) 'shift',
      if (event.alt) 'alt',
      if (event.ctrl) 'ctrl',
    ].join('+');
    final line =
        '${event.kind.name} at (${event.position.x},${event.position.y}) '
        'delta (${event.scrollDelta.x},${event.scrollDelta.y}) ${event.button.name}'
        '${modifiers.isEmpty ? '' : ' $modifiers'}';
    setState(() {
      _reports++;
      _last = line;
      _lines.add('#$_reports $line');
    });
    if (event.kind == MouseEventKind.wheel) {
      if (event.scrollDelta.y < 0) _scroll.lineUp();
      if (event.scrollDelta.y > 0) _scroll.lineDown();
    }
  }

  @override
  Widget build(BuildContext context) => Listener(
    behavior: HitTestBehavior.opaque,
    captureController: _capture,
    onPointerDown: (event) {
      if (event.button == MouseButton.primary) _capture.capture();
      _record(event);
    },
    onPointerMove: _record,
    onPointerCancel: _record,
    onPointerUp: _record,
    onPointerSignal: _record,
    child: Actions(
      bindings: [
        ...scrollBindings(
          _scroll,
          keys: const ScrollKeys(
            lineUp: ['shift+up'],
            lineDown: ['shift+down'],
          ),
        ),
        Binding('ctrl+l', 'Clear event log', () {
          setState(() {
            _lines.clear();
            _reports = 0;
            _last = 'none';
          });
          _scroll.toTop();
        }),
        Binding('ctrl+q', 'Quit', () => exitApp(context)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Pointer events · reports: $_reports',
            style: Theme.of(context).accent,
          ),
          Text('Last event: $_last'),
          Expanded(
            child: ListView.builder(
              controller: _scroll,
              itemCount: _lines.length,
              itemVersion: (i) => _lines[i],
              itemBuilder: (_, i) => Text(_lines[i]),
            ),
          ),
          SizedBox(
            height: 5,
            child: Box(
              border: Border.single,
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: TextArea(
                controller: _draft,
                autofocus: true,
                maxHeight: 3,
              ),
            ),
          ),
          KeyHelp.builder(
            builder: (context, bindings, pending) => Text(
              [
                for (final binding in bindings)
                  if (const {
                    'shift+up',
                    'shift+down',
                    'pageup',
                    'pagedown',
                    'home',
                    'end',
                    'ctrl+l',
                    'ctrl+q',
                    'super+left',
                    'super+right',
                  }.contains('${binding.chord}'))
                    '${binding.chord} ${binding.description}',
              ].join(' · '),
              style: Theme.of(context).dim,
            ),
          ),
        ],
      ),
    ),
  );
}
