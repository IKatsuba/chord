import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const LinkExample());

/// Links: one opening a page through the terminal, one by its action's key
/// shown after it, one running a callback, and a disabled one; Tab moves
/// focus, Enter or a click opens.
class LinkExample extends StatefulWidget {
  /// The example.
  const LinkExample({super.key});

  @override
  State<LinkExample> createState() => _LinkExampleState();
}

class _LinkExampleState extends State<LinkExample> {
  var _last = 'nothing yet';

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('g', 'Open GitHub', () {
        TerminalScope.of(context).openUrl('https://github.com/IKatsuba/chord');
        setState(() => _last = 'GitHub, by its key');
      }, id: 'github'),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Link(
            'pub.dev',
            uri: Uri.parse('https://pub.dev/packages/chord_tui'),
            autofocus: true,
          ),
          Link('GitHub', action: 'github', external: true),
          Link(
            'Read about chord_tui',
            onPressed: () => setState(() => _last = 'Read about chord_tui'),
          ),
          Link('Nowhere'),
          Text(''),
          Text('Last: $_last'),
          const Spacer(),
          const KeyHelp(),
        ],
      ),
    ),
  );
}
