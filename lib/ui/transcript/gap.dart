import 'package:chord_tui/chord_tui.dart';

/// One row above a transcript block.
Widget blockGap(Widget child) => Padding(
  // Only gap.ts's margin form is needed: framework lists count padding.
  padding: const EdgeInsets.only(top: 1),
  child: child,
);
