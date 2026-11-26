import 'package:chord_tui/chord_tui.dart';

/// The keys a phone has no keyboard for, as a row to tap: each tap is sent
/// as that key press, through the focus the app has.
class KeyRow extends StatelessWidget {
  /// The row.
  const KeyRow({super.key});

  /// What each tap sends, and how it is drawn.
  static const keys = [
    ('esc', 'esc'),
    ('tab', 'tab'),
    ('left', '←'),
    ('up', '↑'),
    ('down', '↓'),
    ('right', '→'),
    ('enter', 'enter'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        for (final (key, label) in keys) ...[
          Text(' '),
          Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: (_) => press(context, key),
            child: Text(' $label ', style: theme.text.merge(Style.inverse)),
          ),
        ],
      ],
    );
  }

  /// Sends [key] as a press to [context]'s focus; an unhandled Tab moves
  /// focus, as the terminal's own Tab does.
  static void press(BuildContext context, String key) {
    final focus = context.owner.focusManager;
    final handled = focus.dispatchKey(KeyCombo.parse(key).toEvent());
    if (!handled && key == 'tab') focus.focusNext();
  }
}
