import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../../session/record.dart' show promptLine;
import '../../session/sessions.dart';

/// Frozen opening facts; agent titles wrap while fallback prompt labels cut.
final class ResumedHeader {
  const ResumedHeader(this.text, {required this.wrap});
  final String text;
  final bool wrap;
}

/// Resolves the original resumed label once, without later live title changes.
ResumedHeader resumedHeader(Resume resume, num now, {String? firstPrompt}) {
  final title = resume.title == null
      ? resume.name ??
            resume.prompt ??
            (firstPrompt == null ? null : promptLine(firstPrompt))
      : sessionLabel(
          prompt: resume.prompt ?? '',
          name: resume.name,
          title: resume.title,
        );
  final age = resume.lastUsedAt == null
      ? null
      : lastUsed(
          DateTime.fromMillisecondsSinceEpoch(
            resume.lastUsedAt!.toInt(),
            isUtc: true,
          ).toIso8601String(),
          now,
        );
  return ResumedHeader(
    [
      'resumed',
      if (age != null && age.isNotEmpty) age,
      if (title != null && title.isNotEmpty) title,
    ].join(' · '),
    wrap: resume.title != null,
  );
}

/// [facts] as drawn [width] cells wide: an agent title's rows as the
/// original's wrap-ansi breaks them, one row per line; a cut label as it is.
String resumedRows(ResumedHeader facts, int width) => facts.wrap
    ? [
        for (final row in TextLayout.wrapAnsi(
          TextSpan(facts.text),
          math.max(1, width),
          hard: true,
        ).lines)
          row.map((g) => g.text).join(),
      ].join('\n')
    : facts.text;
