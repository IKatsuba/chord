import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

/// The paint role of one crash-screen row.
enum CrashRole { error, dim, blank }

/// One crash-screen row and the role that paints it.
final class CrashRow {
  const CrashRow(this.text, this.role);
  final String text;
  final CrashRole role;
}

/// The last row of the crash screen.
const crashHint =
    'any key to quit · chord prints the error to stderr as it exits';

/// The original's crash rows, with native Dart frames and its height priorities.
List<CrashRow> crashRows(
  Object error,
  StackTrace? stackTrace,
  int columns,
  int rows,
) {
  if (rows <= 0 || columns <= 0) return const [];
  const blank = CrashRow('', CrashRole.blank);
  String cut(String text) => truncate(text, columns);
  final message = [
    for (final line in TextLayout.wrapAnsi(
      TextSpan(error.toString()),
      math.max(1, columns - 2),
      hard: true,
    ).lines)
      CrashRow(
        cut('  ${line.map((glyph) => glyph.text).join()}'),
        CrashRole.error,
      ),
  ];
  final frames = [
    for (final frame in (stackTrace?.toString() ?? '').split('\n'))
      if (RegExp(r'^#\d+\s').hasMatch(frame))
        CrashRow(cut('  $frame'), CrashRole.dim),
  ];
  final hint = CrashRow(cut('  $crashHint'), CrashRole.dim);
  CrashRow more(int count) => CrashRow(
    cut('      … $count more frame${count == 1 ? '' : 's'}'),
    CrashRole.dim,
  );
  final fixed = message.length + 3;
  if (rows >= fixed + frames.length) {
    return [blank, ...message, ...frames, blank, hint];
  }
  if (frames.isNotEmpty && rows >= fixed + 1) {
    final shown = rows - fixed - 1;
    return [
      blank,
      ...message,
      ...frames.take(shown),
      more(frames.length - shown),
      blank,
      hint,
    ];
  }
  if (rows >= fixed - 1) {
    return rows == fixed
        ? [blank, ...message, blank, hint]
        : [...message, blank, hint];
  }
  final kept = message.take(math.max(0, rows - 1)).toList();
  if (kept.isNotEmpty && kept.length < message.length) {
    kept[kept.length - 1] = CrashRow(
      cut('${kept.last.text}…'),
      CrashRole.error,
    );
  }
  return [...kept, hint];
}
