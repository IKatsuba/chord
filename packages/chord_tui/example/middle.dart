import 'package:chord_tui/chord_tui.dart';

// U4a fixture: fixed budgets and rich colors; ctrl+q quits.
void main() => runApp(const _Middle());

class _Middle extends StatelessWidget {
  const _Middle();
  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final width in [3, 4, 5, 6, 8, 9, 10, 11, 12, 13, 14])
          Row(
            children: [
              SizedBox(width: 8, child: Text('W=$width')),
              SizedBox(
                width: width,
                child: Text.ansi(
                  '\x1b[31mabc日本語👩‍💻\x1b[32mXYZ\x1b[0m',
                  softWrap: false,
                  overflow: TextOverflow.middle,
                ),
              ),
            ],
          ),
        Text(
          'A long full-width label preserving both ends and terminal cells 日本語 ' *
              4,
          softWrap: false,
          maxLines: 1,
          overflow: TextOverflow.middle,
        ),
      ],
    ),
  );
}
