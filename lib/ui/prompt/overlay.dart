import 'dart:math' as math;

/// Choice rows fitting after a framed picker's original seven chrome rows.
int framedRows(int limit, int room, int count) {
  int fit(int around) => math.max(0, math.min(limit, room - 7 - around));
  final rows = fit(0);
  return count > rows ? fit(1) : rows;
}

/// Cuts body rows at a drawn part, leaving no trailing blank gap.
int cutRows(int room, int height, List<(int, int)> parts) {
  if (height <= room) return height;
  for (var rows = math.max(0, room); rows > 0; rows--) {
    if (parts.any(
      (part) => rows - 1 >= part.$1 && rows - 1 < part.$1 + part.$2,
    )) {
      return rows;
    }
  }
  return 0;
}
