import 'package:characters/characters.dart';
import 'package:chord_tui/chord_tui.dart';

/// A form of seven fields, one of each kind, and what it gave under it;
/// `--narrow` gives the fields eight rows, so they scroll, and
/// `--long-list` gives Region twelve options, more than those rows hold.
void main(List<String> args) => runApp(
  FormExample(
    maxRows: args.contains('--narrow') ? 8 : null,
    longList: args.contains('--long-list'),
  ),
);

/// Region's twelve options under `--long-list`.
const longRegions = [
  PickerItem(value: 'eu', label: 'Europe'),
  PickerItem(value: 'us', label: 'United States'),
  PickerItem(value: 'ap', label: 'Asia Pacific'),
  PickerItem(value: 'ca', label: 'Canada'),
  PickerItem(value: 'jp', label: 'Japan'),
  PickerItem(value: 'in', label: 'India'),
  PickerItem(value: 'br', label: 'Brazil'),
  PickerItem(value: 'au', label: 'Australia'),
  PickerItem(value: 'za', label: 'South Africa'),
  PickerItem(value: 'me', label: 'Middle East'),
  PickerItem(value: 'mx', label: 'Mexico'),
  PickerItem(value: 'kr', label: 'Korea'),
];

final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// The example.
class FormExample extends StatefulWidget {
  /// The example, its fields given [maxRows], Region's list long with
  /// [longList].
  const FormExample({super.key, this.maxRows, this.longList = false});

  /// The most rows the fields take.
  final int? maxRows;

  /// Whether Region offers [longRegions].
  final bool longList;

  @override
  State<FormExample> createState() => _FormExampleState();
}

class _FormExampleState extends State<FormExample> {
  var _said = 'nothing yet';

  late final _form = FormController(
    fields: [
      TextFormItem(
        name: 'name',
        label: 'Project name',
        description: 'Lowercase, dashes allowed',
        required: true,
        validator: (text) => text.characters.length < 3
            ? 'At least 3 characters'
            : text.characters.length > 20
            ? 'At most 20 characters'
            : null,
      ),
      TextFormItem(
        name: 'email',
        label: 'Contact email',
        validator: (text) => _email.hasMatch(text)
            ? null
            : 'Not an email address, such as name@example.com',
      ),
      NumberFormItem(
        name: 'replicas',
        label: 'Replicas',
        integer: true,
        initialValue: 2,
        required: true,
        validator: (text) {
          final n = int.tryParse(text);
          return n != null && n >= 1 && n <= 9
              ? null
              : 'A whole number from 1 to 9';
        },
      ),
      NumberFormItem(
        name: 'ratio',
        label: 'Traffic share',
        description: 'Share of traffic sent here, from 0 to 1',
        validator: (text) {
          final n = num.tryParse(text);
          return n != null && n >= 0 && n <= 1 ? null : 'A number from 0 to 1';
        },
      ),
      const BoolFormItem(name: 'public', label: 'Public', initialValue: false),
      ChoiceFormItem<String>(
        name: 'region',
        label: 'Region',
        required: true,
        options: widget.longList
            ? longRegions
            : const [
                PickerItem(value: 'eu', label: 'Europe'),
                PickerItem(value: 'us', label: 'United States'),
                PickerItem(value: 'ap', label: 'Asia Pacific'),
              ],
      ),
      const MultiChoiceFormItem<String>(
        name: 'tags',
        label: 'Tags',
        options: [
          PickerItem(value: 'web', label: 'web'),
          PickerItem(value: 'api', label: 'api'),
          PickerItem(value: 'worker', label: 'worker'),
        ],
      ),
    ],
  );

  @override
  void dispose() {
    _form.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Actions(
      bindings: [Binding('ctrl+q', 'Quit', () => exitApp(context))],
      child: Padding(
        padding: const EdgeInsets.only(left: 1, right: 1),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(' New deployment', style: theme.accent.merge(Style.bold)),
            const SizedBox(height: 1),
            Form(
              controller: _form,
              maxRows: widget.maxRows,
              submitLabel: 'Accept',
              declineLabel: 'Decline',
              onSubmitted: (values) => setState(() => _said = '$values'),
              onDeclined: () => setState(() => _said = 'declined'),
              onCanceled: () => setState(() => _said = 'canceled'),
            ),
            const SizedBox(height: 1),
            Text('Gave: $_said', style: theme.dim),
            Text('Ctrl+Q quits', style: theme.dim),
          ],
        ),
      ),
    );
  }
}
