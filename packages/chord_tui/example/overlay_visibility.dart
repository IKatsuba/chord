import 'package:chord_tui/chord_tui.dart';

void main(List<String> args) =>
    runApp(OverlayVisibilityExample(passive: args.contains('--passive')));

/// A passive completion whose Tab action checks its latest layout visibility.
class OverlayVisibilityExample extends StatefulWidget {
  /// The geometry-gated completion fixture.
  const OverlayVisibilityExample({super.key, this.passive = false});

  /// A linked geometry-only follower leaves numbered transcript rows untouched.
  final bool passive;

  @override
  State<OverlayVisibilityExample> createState() => _OverlayVisibilityState();
}

class _OverlayVisibilityState extends State<OverlayVisibilityExample> {
  final _link = LayerLink();
  final _input = TextAreaController(text: 'sta');
  String _result = 'not pressed';
  late final _page = OverlayEntry(requestFocus: false, builder: _buildPage);
  late final _completion = OverlayEntry(
    requestFocus: false,
    builder: (_) => CompositedTransformFollower(
      link: _link,
      opaque: !widget.passive,
      followerAnchor: Alignment.bottomLeft,
      child: widget.passive
          ? LayoutBuilder(
              builder: (_, constraints) =>
                  SizedBox(width: constraints.maxWidth, height: 1),
            )
          : Text('  status  Complete the word'),
    ),
  );

  Widget _buildPage(BuildContext context) => Column(
    children: [
      Expanded(
        child: LayoutBuilder(
          builder: (_, constraints) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Resize to five rows to hide the completion.'),
              for (var i = 1; i < constraints.maxHeight; i++)
                Text('Transcript row $i · underlying cells stay visible'),
            ],
          ),
        ),
      ),
      CompositedTransformTarget(link: _link, child: const SizedBox(height: 0)),
      SizedBox(
        height: 5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextArea(
              controller: _input,
              autofocus: true,
              maxHeight: 1,
              unhandledKeys: const {'tab', 'ctrl+r', 'ctrl+q'},
            ),
            ListenableBuilder(
              listenable: _input,
              builder: (_) => Text('Draft: ${_input.text}'),
            ),
            Text('Last Tab: $_result'),
            KeyHelp.builder(
              builder: (context, bindings, pending) => Text(
                bindings
                    .where(
                      (binding) => const {
                        'tab',
                        'ctrl+r',
                        'ctrl+q',
                      }.contains(binding.chord.toString()),
                    )
                    .map((binding) => '${binding.chord} ${binding.description}')
                    .join('  '),
                softWrap: false,
              ),
            ),
            Text('Typing keeps focus; Ctrl+R resets the seed.'),
          ],
        ),
      ),
    ],
  );

  @override
  void dispose() {
    _input.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('tab', 'Complete visible word', () {
        final visible = _completion.visible;
        if (visible) _input.text = 'status';
        setState(() => _result = visible ? 'completed' : 'ignored');
        _page.markNeedsBuild();
      }),
      Binding('ctrl+r', 'Reset draft', () {
        _input.text = 'sta';
        setState(() => _result = 'not pressed');
        _page.markNeedsBuild();
      }),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Overlay(initialEntries: [_page, _completion]),
  );
}
