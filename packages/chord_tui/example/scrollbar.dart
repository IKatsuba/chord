import 'package:chord_tui/chord_tui.dart';

void main(List<String> args) =>
    runApp(ScrollbarExample(quiet: args.contains('--quiet')));

/// A long list beside a [Scrollbar]: the scroll keys, the wheel, a press on
/// the track or a drag of the thumb move it; `--quiet` shows the thumb only
/// while the view moves.
class ScrollbarExample extends StatefulWidget {
  /// The example; [quiet] sets `thumbVisibility: false`.
  const ScrollbarExample({super.key, this.quiet = false});

  /// Whether the thumb hides while the view is still.
  final bool quiet;

  @override
  State<ScrollbarExample> createState() => _ScrollbarExampleState();
}

class _ScrollbarExampleState extends State<ScrollbarExample> {
  final _scroll = ScrollController();

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      ...scrollBindings(_scroll),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Column(
      children: [
        Expanded(
          child: Scrollbar(
            controller: _scroll,
            thumbVisibility: !widget.quiet,
            child: ListView.builder(
              controller: _scroll,
              itemCount: 200,
              itemBuilder: (context, i) => Text(
                'Row ${i + 1} of 200${i % 7 == 0 ? ' · a longer row that '
                          'wraps when the window is narrow enough to need it' : ''}',
              ),
            ),
          ),
        ),
        const KeyHelp(),
      ],
    ),
  );
}
