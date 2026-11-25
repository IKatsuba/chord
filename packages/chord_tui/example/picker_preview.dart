import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const PickerPreviewExample());

/// A picker whose highlighted value previews before it is accepted.
class PickerPreviewExample extends StatefulWidget {
  /// The highlight callback example.
  const PickerPreviewExample({super.key});

  @override
  State<PickerPreviewExample> createState() => _PickerPreviewExampleState();
}

class _PickerPreviewExampleState extends State<PickerPreviewExample> {
  var _highlighted = 'Choice 1';
  var _accepted = 'Nothing yet';
  static final _items = [
    for (var i = 1; i <= 30; i++)
      PickerItem(value: 'Choice $i', label: 'Choice $i'),
  ];

  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Highlight a choice to preview it; Enter accepts it.'),
        Expanded(
          child: Picker<String>(
            items: _items,
            searchable: true,
            onChanged: (value) => setState(() => _highlighted = value),
            onSelected: (value) => setState(() => _accepted = value),
            onCanceled: () => setState(() => _accepted = 'Canceled'),
          ),
        ),
        Text('Highlighted: $_highlighted'),
        Text('Accepted: $_accepted'),
        const KeyHelp(),
      ],
    ),
  );
}
