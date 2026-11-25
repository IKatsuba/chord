/// A held box's lines above its hint, which give way where the window has
/// no room for them, from the original's `ui/dialogs/fold.ts` and
/// `Fold.tsx`: they fold from the bottom under `… N more lines`, as the
/// framework's [foldOf] counts them. Not held, they are drawn whole.
library;

import 'package:chord_tui/chord_tui.dart';

/// A box's height around its [lines] and [chrome], what it draws besides
/// them: [natural] whole; [fixed], what it keeps while [held], its lines
/// folded to `… N more lines` alone; not held it never folds.
({int fixed, int natural}) heldNatural(
  int lines, {
  required int chrome,
  required bool held,
}) {
  final natural = chrome + lines;
  return (fixed: held && lines > 0 ? chrome + 1 : natural, natural: natural);
}

/// [child], [lines] rows tall, folded into [room] rows while [held].
class HeldFold extends StatelessWidget {
  const HeldFold({
    super.key,
    required this.held,
    required this.lines,
    required this.room,
    required this.child,
  });
  final bool held;
  final int lines;
  final int? room;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final room = this.room;
    if (!held || room == null) return child;
    final (:shown, :more) = foldOf(lines, room);
    if (more == 0) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (shown > 0)
          SizedBox(
            height: shown,
            child: Stack(
              children: [
                Positioned(
                  left: 0,
                  right: 0,
                  top: 0,
                  height: lines,
                  child: child,
                ),
              ],
            ),
          ),
        Text('  ${moreLines(more)}', style: Theme.of(context).dim),
      ],
    );
  }
}
