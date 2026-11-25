import 'package:chord_tui/chord_tui.dart';

void main() => runApp(const KeyCaptureFixture());

/// Demonstrates printable capture before a focused editor, without port policy.
class KeyCaptureFixture extends StatefulWidget {
  /// Starts an empty focused editor and one captured printable chord.
  const KeyCaptureFixture({super.key});
  @override
  State<KeyCaptureFixture> createState() => _CaptureState();
}

class _CaptureState extends State<KeyCaptureFixture> {
  final _draft = TextAreaController();
  var _capture = true;
  var _actions = 0, _pastes = 0;

  @override
  void dispose() {
    _draft.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final action = Binding(
      'v c',
      'Capture printable action',
      () => setState(() => _actions++),
    );
    return Actions(
      bindings: [
        action,
        Binding(
          'f2',
          'Toggle key capture',
          () => setState(() => _capture = !_capture),
        ),
        Binding('ctrl+q', 'Quit', () => exitApp(context)),
      ],
      child: Focus(
        canRequestFocus: false,
        onKeyCapture: (event) =>
            _capture &&
            context.owner.focusManager
                .matchKey(event, where: (binding) => identical(binding, action))
                .dispatch(),
        onPasteCapture: (_) {
          setState(() => _pastes++);
          return false;
        },
        child: Column(
          children: [
            Text(
              'Key capture · ${_capture ? 'enabled' : 'disabled'} · actions $_actions · pastes $_pastes',
            ),
            Text(
              'When enabled, v then c invokes the action before the editor.',
            ),
            Text(
              'Other text edits normally; an unfinished chord drops a miss.',
            ),
            TextArea(
              controller: _draft,
              autofocus: true,
              maxHeight: 5,
              placeholder: 'Type here',
            ),
            KeyHelp.builder(
              builder: (_, bindings, pending) => Text(
                'v then c captured action · F2 toggle capture · C-q quit'
                '${pending.isEmpty ? '' : ' · pending ${pending.join(' ')}'}',
                style: Theme.of(context).dim,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
