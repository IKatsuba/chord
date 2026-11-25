import 'package:chord_tui/chord_tui.dart';

// U2a visual fixture: run at 120x40 and 80x24; ctrl+o changes source-row cap.
void main() => runApp(const _Example());

class _Example extends StatefulWidget {
  const _Example();

  @override
  State<_Example> createState() => _ExampleState();
}

class _ExampleState extends State<_Example> {
  var expanded = false;
  final model = diffTexts(
    [for (var i = 1; i <= 30; i++) 'line $i'].join('\n'),
    [
      for (var i = 1; i <= 30; i++)
        i == 5 || i == 25
            ? 'changed $i: A message about terminal cells, 日本語, and preserving every grapheme while the source line wraps'
            : 'line $i',
    ].join('\n'),
  );

  @override
  Widget build(BuildContext context) {
    final view = model.view(maxRows: expanded ? null : 10);
    return Actions(
      bindings: [
        Binding(
          'ctrl+o',
          'Toggle diff details',
          () => setState(() => expanded = !expanded),
        ),
        Binding('ctrl+q', 'Quit', () => exitApp(context)),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Updated sample.ts with ${view.added} additions and ${view.removed} removals',
          ),
          Diff.fromView(view, title: 'sample.ts', showTitle: false),
          if (view.hidden > 0) Text('… ${view.hidden} more lines'),
          const KeyHelp(),
        ],
      ),
    );
  }
}
