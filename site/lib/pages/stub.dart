import 'package:chord_tui/chord_tui.dart';

/// A page whose text is still to come: its name, and one line on it.
class StubPage extends StatelessWidget {
  /// A page called [name], said in [line].
  const StubPage(this.name, this.line, {super.key});

  /// The page's name.
  final String name;

  /// What the page will hold.
  final String line;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: 2, top: 1),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: Theme.of(context).text.merge(Style.bold)),
        Text(line, style: Theme.of(context).dim),
      ],
    ),
  );
}
