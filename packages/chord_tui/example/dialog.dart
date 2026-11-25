import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const DialogExample());

/// A dialog anchored above a prompt, as chord asks for a permission: Esc
/// or a choice closes it, ctrl+o opens it again.
class DialogExample extends StatefulWidget {
  /// The example.
  const DialogExample({super.key});

  @override
  State<DialogExample> createState() => _DialogExampleState();
}

class _DialogExampleState extends State<DialogExample> {
  final _link = LayerLink();
  late OverlayState _overlay;
  OverlayEntry? _entry;
  // Entries are not rebuilt with this widget: the page listens itself.
  final _answer = ValueNotifier('none yet');
  var _first = true;

  void _open() {
    if (_entry != null) return;
    final entry = OverlayEntry(
      builder: (_) => CompositedTransformFollower(
        link: _link,
        followerAnchor: Alignment.bottomLeft,
        child: Dialog<String>(
          title: Text('Allow command?'),
          choices: const [
            PickerItem(value: 'allowed once', label: 'Allow once'),
            PickerItem(value: 'rejected', label: 'Reject'),
          ],
          onSelected: _close,
          onCanceled: () => _close('closed'),
          child: Text(
            'Run the requested command in this session.\n'
            '\$ dart analyze\n'
            '\$ dart format --output=none --set-exit-if-changed .\n'
            '\$ dart test',
          ),
        ),
      ),
    );
    _overlay.insert(entry);
    _entry = entry;
  }

  void _close(String answer) {
    final entry = _entry;
    if (entry == null) return;
    _entry = null;
    entry
      ..remove()
      ..dispose();
    _answer.value = answer;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Actions(
      bindings: [
        Binding('ctrl+o', 'Open the dialog', _open),
        Binding('ctrl+q', 'Quit', () => exitApp(context)),
      ],
      child: Overlay(
        initialEntries: [
          OverlayEntry(
            builder: (context) {
              _overlay = Overlay.of(context);
              // Opened on the first frame, once the overlay is laid out.
              if (_first) {
                _first = false;
                context.owner.afterLayout(_open);
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: ListenableBuilder(
                      listenable: _answer,
                      builder: (_) => Text(
                        'The transcript is here. Answer: ${_answer.value}',
                        style: theme.dim,
                      ),
                    ),
                  ),
                  CompositedTransformTarget(
                    link: _link,
                    child: const SizedBox(height: 0),
                  ),
                  Text(''),
                  Focus(
                    autofocus: true,
                    debugLabel: 'prompt',
                    child: Text('> /permission'),
                  ),
                  const KeyHelp(),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
