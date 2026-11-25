import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const PickerExample());

/// A searchable picker of thirty choices, some of them two lines tall,
/// and what was chosen under it.
class PickerExample extends StatefulWidget {
  /// The example.
  const PickerExample({super.key});

  @override
  State<PickerExample> createState() => _PickerExampleState();
}

class _PickerExampleState extends State<PickerExample> {
  var _chosen = 'nothing yet';

  static final _items = [
    for (var i = 1; i <= 30; i++)
      PickerItem(
        value: 'choice $i',
        label: i % 7 == 0
            ? 'Choice $i, with a second line\n  under its label'
            : 'Choice $i',
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Actions(
      bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
      // The status and the keys keep their rows; the title and the gaps
      // go first where the window is short.
      child: LayoutBuilder(
        builder: (context, constraints) {
          final roomy = constraints.maxHeight >= 10;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (roomy) ...[
                Text(' Pick one', style: theme.accent.merge(Style.bold)),
                Text(''),
              ],
              // Bounded by the rows the lines below leave it.
              // Keyed: the rows above come and go with the height, and the
              // picker must keep its element, and with it its query.
              Expanded(
                key: const ValueKey('picker'),
                child: Align(
                  alignment: Alignment.topLeft,
                  child: Picker<String>(
                    items: _items,
                    searchable: true,
                    onSelected: (v) => setState(() => _chosen = v),
                    onCanceled: () => setState(() => _chosen = 'canceled'),
                    itemExtentVersion: _items,
                    itemExtentBuilder: (item, positions, width) =>
                        TextLayout.compute(
                          TextSpan(item.label),
                          maxWidth: width,
                        ).height,
                    itemBuilder: (_, item, _) => Text(item.label),
                  ),
                ),
              ),
              if (roomy) Text(''),
              Text('Chosen: $_chosen', style: theme.dim),
              const KeyHelp(),
            ],
          );
        },
      ),
    );
  }
}
