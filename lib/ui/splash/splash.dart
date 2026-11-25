/// The startup splash, from the original's `ui/splash/splash.ts`: Chorded's
/// mark, dim, drifting round a small ellipse in the middle of the screen
/// until the first session is up, with one line under it.
library;

import 'package:chord_tui/chord_tui.dart' show cellWidth;

import '../../session/elapsed.dart';
import '../app/state.dart';
import '../header/mark.dart';
import '../start_state.dart';

/// How long the mark stays in each place on its path.
const splashStepMs = 300;

/// From when a start is slow: the line counts seconds and names the keys.
const slowStartMs = 5000;

/// The second line from [slowStartMs] on.
const slowHint = 'esc for the window · ctrl+c to quit';

/// One place on the path: columns right of the centre, half rows down.
typedef SplashPlace = ({int column, int half});

/// The circle sampled every 45°, counter-clockwise from the top centre: the
/// column is −round(sin θ), the half row 2 − round(2 cos θ). Every step
/// moves one half row, so nothing stands still and nothing jumps two places.
const List<SplashPlace> splashPath = [
  (column: 0, half: 0),
  (column: -1, half: 1),
  (column: -1, half: 2),
  (column: -1, half: 3),
  (column: 0, half: 4),
  (column: 1, half: 3),
  (column: 1, half: 2),
  (column: 1, half: 1),
];

/// The half rows and columns the mark travels inside its box.
const _travelHalves = 4;
const _travelColumns = 2;

/// The mark that fits: the 8-row one from 24×16, the header's 4-row one
/// from 16×9, none below that. The original's `splashMark`; the name is the
/// 8-row grid's here.
MarkGrid? splashMarkFor(int columns, int rows) {
  if (columns >= 24 && rows >= 16) return splashMark;
  if (columns >= 16 && rows >= 9) return mark;
  return null;
}

/// The mark's box at [step] of its path: the grid with empty half rows
/// above and empty columns to its left, padded to the box, so the box never
/// changes size and the lines under it never move. An odd half row pairs
/// the grid's half rows the other way, which makes the vertical step smooth.
MarkGrid splashFrame(MarkGrid grid, int step) {
  final place = splashPath[step % splashPath.length];
  final width = (grid.firstOrNull?.length ?? 0) + _travelColumns;
  final left = _travelColumns ~/ 2 + place.column;
  List<double?> empty() => List<double?>.filled(width, null);
  return [
    for (var i = 0; i < place.half; i++) empty(),
    for (final line in grid) empty()..setRange(left, left + line.length, line),
    for (var i = 0; i < _travelHalves - place.half; i++) empty(),
  ];
}

/// The two lines under the mark, in the status line's own words; the second
/// empty until the start is slow, so nothing above it moves when it comes.
/// [elapsed] counts from when the window opened; [armed] is an armed quit's
/// question, which takes the first line.
(String, String) splashLines({
  required String agent,
  required num elapsed,
  String? armed,
  required bool closing,
}) {
  final slow = elapsed >= slowStartMs;
  final first = closing
      ? 'Stopping $agent…'
      : armed ??
            (slow
                ? 'Starting $agent… ${formatElapsed(elapsed)}'
                : 'Starting $agent…');
  return (first, slow ? slowHint : '');
}

/// Where the splash's pieces go on a screen: empty rows above the block,
/// empty columns left of the mark's box and left of each line.
typedef SplashLayout = ({int top, int markLeft, (int, int) lineLefts});

/// The block (the box, a blank row and the two lines, or the lines alone)
/// centred on the screen, rounding up and left as the frames do. Worked out
/// on every draw, so a resize keeps it centred.
SplashLayout splashLayout(
  int columns,
  int rows,
  MarkGrid? grid,
  (String, String) lines,
) {
  final box = grid == null
      ? null
      : (
          width: (grid.firstOrNull?.length ?? 0) + _travelColumns,
          height: (grid.length + _travelHalves) ~/ 2,
        );
  final height = (box == null ? 0 : box.height + 1) + 2;
  int centred(int width) => ((columns - width) / 2).floor().clamp(0, columns);
  return (
    top: ((rows - height) / 2).floor().clamp(0, rows),
    markLeft: box == null ? 0 : centred(box.width),
    lineLefts: (centred(cellWidth(lines.$1)), centred(cellWidth(lines.$2))),
  );
}

/// Whether the splash holds the screen: until the first session is up or
/// has failed, or Esc [left] it; a quit asked for meanwhile keeps it, to
/// say so.
bool splashShown(bool enabled, bool left, AppState state) =>
    enabled &&
    !left &&
    (state.start.phase == StartPhase.starting || state.closing);
