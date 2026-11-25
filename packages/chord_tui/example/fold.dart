import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const FoldExample());

/// A tool call's output under a fold, which ctrl+o opens and closes, over
/// an aligned table; a short window folds the output under a count.
class FoldExample extends StatefulWidget {
  /// The example.
  const FoldExample({super.key});

  @override
  State<FoldExample> createState() => _FoldExampleState();
}

class _FoldExampleState extends State<FoldExample> {
  var _open = true;

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding(
        'ctrl+o',
        'Toggle tool details',
        () => setState(() => _open = !_open),
      ),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // The rows the table and the keys leave it.
              Flexible(
                child: Fold(
                  title: 'Run checks',
                  open: _open,
                  child: Text(
                    [
                      r'$ dart analyze',
                      'Analyzing CTUI-2...',
                      'No issues found!',
                      r'$ dart format --output=none --set-exit-if-changed .',
                      'Formatted 205 files (0 changed) in 0.45 seconds.',
                      r'$ dart test test/widgets/fold_test.dart',
                      '00:00 +15: All tests passed!',
                    ].join('\n'),
                  ),
                ),
              ),
              Text(''),
              Table(
                columnGap: 2,
                columnWidths: const {
                  0: IntrinsicColumnWidth(maxWidth: 32),
                  1: FixedColumnWidth(9),
                  2: FlexColumnWidth(),
                },
                children: [
                  TableRow(
                    children: [
                      Text('Name'),
                      Text('Transport'),
                      Text('Command or URL'),
                    ],
                  ),
                  TableRow(
                    children: [
                      Text('memory'),
                      Text('stdio'),
                      Text('npx -y memory'),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),
        const KeyHelp(),
      ],
    ),
  );
}
