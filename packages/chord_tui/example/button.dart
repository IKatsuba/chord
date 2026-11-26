import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const ButtonExample());

/// Filled and outlined buttons: two pressed by their action's key, shown
/// under each, one by focus and Enter alone, and one disabled; Tab moves
/// focus and the last press shows below.
class ButtonExample extends StatefulWidget {
  /// The example.
  const ButtonExample({super.key});

  @override
  State<ButtonExample> createState() => _ButtonExampleState();
}

class _ButtonExampleState extends State<ButtonExample> {
  var _last = 'nothing yet';

  void _say(String what) => setState(() => _last = what);

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [
      Binding('i', 'Install chord', () => _say('Install chord'), id: 'install'),
      Binding('w', 'Watch it run', () => _say('Watch it run'), id: 'watch'),
      Binding('ctrl+q', 'Quit', () => exitApp(context)),
    ],
    child: Padding(
      padding: const EdgeInsets.all(2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            spacing: 3,
            children: [
              FilledButton(
                action: 'install',
                autofocus: true,
                child: Text('Install chord'),
              ),
              OutlinedButton(action: 'watch', child: Text('Watch it run')),
            ],
          ),
          Text(''),
          Row(
            spacing: 3,
            children: [
              FilledButton(onPressed: () => _say('Save'), child: Text('Save')),
              OutlinedButton(child: Text('Disabled')),
            ],
          ),
          Text(''),
          Text('Pressed: $_last'),
          const Spacer(),
          const KeyHelp(),
        ],
      ),
    ),
  );
}
