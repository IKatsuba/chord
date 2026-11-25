// ↓ from a box's last choice into the list of the window's agents, as the
// original's ChoiceList with `onLeave`: where there is a list to go to, the
// last choice does not wrap to the first.
import 'package:chord_tui/chord_tui.dart';

/// Whether [event] is ↓ or `j` as a choice list reads it, unmodified.
bool leavesDown(KeyEvent event) =>
    !event.ctrl &&
    !event.alt &&
    !event.shift &&
    (event.key == 'down' || event.key == 'j');

/// [picker] of [values], with ↓ and `j` on its last choice handed to
/// [onLeave]; [highlighted] is the choice highlighted now, none the first.
/// As it is without [onLeave].
Widget leavingLast<T>({
  required List<T> values,
  required T? Function() highlighted,
  required void Function()? onLeave,
  required Widget picker,
}) {
  final leave = onLeave;
  if (leave == null || values.isEmpty) return picker;
  return Focus(
    canRequestFocus: false,
    onKeyCapture: (event) {
      if (!leavesDown(event) ||
          (highlighted() ?? values.first) != values.last) {
        return false;
      }
      leave();
      return true;
    },
    child: picker,
  );
}
