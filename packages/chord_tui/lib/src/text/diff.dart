import 'package:dartdiff/dartdiff.dart' as dd;
import 'package:meta/meta.dart';

/// What a diff line does.
enum DiffKind {
  /// Unchanged, shown for context.
  context,

  /// Only in the new text.
  added,

  /// Only in the old text.
  removed,
}

/// How a diff wraps a code row longer than its room.
enum DiffWrap {
  /// Breaks only at spaces and drops none: spaces that do not fit start
  /// the next row. The default, as `Diff` has always drawn.
  keepSpaces,

  /// As wrap-ansi wraps with `hard` and `trim`: the row's leading indent is
  /// kept on its first row only, as much of it as leaves one cell for code;
  /// the rest wraps at spaces, drops the spaces at every break, and cuts a
  /// word wider than the room. The wrap chord's diffs use.
  wrapAnsi,
}

/// A source line or the separator between two diff hunks.
sealed class DiffRow {
  /// A row selected from a diff model.
  const DiffRow();
}

/// The separator between two hunks, consuming one source-row position.
final class DiffGap extends DiffRow {
  /// An inter-hunk separator.
  const DiffGap();
}

/// Selected source rows and full counts from a diff model.
final class DiffView {
  const DiffView._(
    this.model,
    this.rows,
    this.added,
    this.removed,
    this.hidden,
    this.numberWidth,
  );

  /// The complete sources and hunks, retained for highlighting.
  final DiffModel model;

  /// The selected rows, before wrapping, in an unmodifiable list.
  final List<DiffRow> rows;

  /// Added lines in the complete model.
  final int added;

  /// Removed lines in the complete model.
  final int removed;

  /// Unselected source lines, excluding gaps.
  final int hidden;

  /// Digits of the widest selected number, at least one.
  final int numberWidth;
}

/// One line of a hunk: its kind, its number and its text, and where its
/// text sits among the diff's sources, for highlighting it in place.
final class DiffLine extends DiffRow {
  /// A [kind] line numbered [number], line [line] of source [source].
  const DiffLine(this.kind, this.number, this.text, this.source, this.line);

  /// Unchanged, added or removed.
  final DiffKind kind;

  /// Its number: the old file's for a removal, the new file's otherwise.
  final int number;

  /// Its text, without its line break.
  final String text;

  /// Which of [DiffModel.sources] holds it: the old side's for a removal,
  /// the new side's otherwise.
  final int source;

  /// Its index among that source's lines.
  final int line;

  @override
  String toString() =>
      '${switch (kind) {
        DiffKind.context => ' ',
        DiffKind.added => '+',
        DiffKind.removed => '-',
      }}$number $text';
}

/// A run of changed lines with the unchanged lines around them.
final class DiffHunk {
  /// A hunk of [lines] at the given starts and counts.
  const DiffHunk({
    required this.oldStart,
    required this.oldCount,
    required this.newStart,
    required this.newCount,
    required this.lines,
  });

  /// Its first line in the old file, from 1.
  final int oldStart;

  /// How many old lines it covers.
  final int oldCount;

  /// Its first line in the new file, from 1.
  final int newStart;

  /// How many new lines it covers.
  final int newCount;

  /// Its lines, in order.
  final List<DiffLine> lines;
}

/// A line diff: its hunks, the texts to highlight them from, and the path
/// a unified diff named.
final class DiffModel {
  /// A diff of [hunks] whose lines index into [sources].
  const DiffModel(this.hunks, this.sources, {this.path});

  /// Its hunks, in order; none for equal texts.
  final List<DiffHunk> hunks;

  /// The texts its lines come from, each to be highlighted whole: the old
  /// and the new file for a generated diff, each hunk's old and new runs
  /// for a unified one.
  final List<String> sources;

  /// The file a unified diff's headers name; null for a generated diff or
  /// a bare hunk.
  final String? path;

  /// Selects at most [maxRows] source rows, excluding a trailing gap.
  /// Counts describe the complete model; wrapping never affects selection.
  DiffView view({int? maxRows}) {
    if (maxRows != null) RangeError.checkNotNegative(maxRows, 'maxRows');
    final all = <DiffRow>[];
    var added = 0, removed = 0, total = 0;
    for (final hunk in hunks) {
      if (hunk.lines.isEmpty) continue;
      if (all.isNotEmpty) all.add(const DiffGap());
      for (final line in hunk.lines) {
        all.add(line);
        total++;
        if (line.kind == DiffKind.added) added++;
        if (line.kind == DiffKind.removed) removed++;
      }
    }
    final rows = maxRows == null ? all : all.take(maxRows).toList();
    if (rows.isNotEmpty && rows.last is DiffGap) rows.removeLast();
    var selected = 0, widest = 1;
    for (final row in rows) {
      if (row is DiffLine) {
        selected++;
        final digits = row.number.toString().length;
        if (digits > widest) widest = digits;
      }
    }
    return DiffView._(
      this,
      List.unmodifiable(rows),
      added,
      removed,
      total - selected,
      widest,
    );
  }

  /// The widest number its lines show, in digits; at least 1.
  int get numberWidth {
    var widest = 1;
    for (final hunk in hunks) {
      for (final line in hunk.lines) {
        final w = '${line.number}'.length;
        if (w > widest) widest = w;
      }
    }
    return widest;
  }
}

/// The line diff from [oldText] to [newText], with [context] unchanged
/// lines around each change. A line ending is not an edit: CRLF and LF, or
/// a missing final line break, compare equal, as chord compares them.
DiffModel diffTexts(String oldText, String newText, {int context = 3}) {
  RangeError.checkNotNegative(context, 'context');
  final patch = dd.structuredPatch(
    '',
    '',
    _withFinalNewline(oldText),
    _withFinalNewline(newText),
    context: context,
    stripTrailingCr: true,
  )!;
  return DiffModel(
    [
      for (final hunk in patch.hunks)
        _hunk(hunk, 0, 1, hunk.oldStart, hunk.newStart),
    ],
    [_lf(oldText), _lf(newText)],
  );
}

/// One file's unified diff: optional `---`/`+++` headers, then hunks.
///
/// Throws a [FormatException] for a malformed patch, a patch of several
/// files, or text with no hunk; blank text is an empty diff.
DiffModel parseUnifiedDiff(String patch) {
  if (patch.trim().isEmpty) return const DiffModel([], []);
  final List<dd.StructuredPatch> files;
  try {
    files = dd.parsePatch(patch);
  } on StateError catch (e) {
    throw FormatException(e.message, patch);
  } on RangeError {
    // dartdiff 1.0.0 indexes an empty last line when a hunk promises more
    // lines than follow; jsdiff refuses that patch as having an invalid line.
    throw FormatException('A hunk has fewer lines than its counts', patch);
  }
  if (files.length != 1) {
    throw FormatException('A patch of ${files.length} files', patch);
  }
  final file = files.single;
  if (file.hunks.isEmpty) throw FormatException('No hunk', patch);

  final hunks = <DiffHunk>[];
  final sources = <String>[];
  var oldEnd = 0, newEnd = 0;
  for (final hunk in file.hunks) {
    if (hunk.oldStart <= oldEnd || hunk.newStart <= newEnd) {
      throw FormatException(
        'A hunk at -${hunk.oldStart} +${hunk.newStart} overlaps the one '
        'before it',
        patch,
      );
    }
    oldEnd = hunk.oldStart + hunk.oldLines - 1;
    newEnd = hunk.newStart + hunk.newLines - 1;
    // Each hunk's old and new runs are highlighted on their own: what lies
    // between hunks is not in the patch.
    final old = sources.length, fresh = sources.length + 1;
    final parsed = _hunk(hunk, old, fresh, 1, 1);
    sources
      ..add(_run(hunk.lines, '-'))
      ..add(_run(hunk.lines, '+'));
    hunks.add(
      DiffHunk(
        oldStart: hunk.oldStart,
        oldCount: hunk.oldLines,
        newStart: hunk.newStart,
        newCount: hunk.newLines,
        lines: [
          for (final line in parsed.lines)
            DiffLine(
              line.kind,
              line.number +
                  (line.kind == DiffKind.removed
                      ? hunk.oldStart - 1
                      : hunk.newStart - 1),
              line.text,
              line.source,
              line.line,
            ),
        ],
      ),
    );
  }
  return DiffModel(hunks, sources, path: _path(file));
}

/// [parseUnifiedDiff], remembered for the patches parsed last: a widget is
/// built again for the same patch on every rebuild above it, a theme change
/// included, and its patch is parsed when it is built. A malformed patch is
/// not remembered and throws each time.
DiffModel parseUnifiedDiffRemembered(String patch) {
  final known = _parsed[patch];
  if (known != null) return known;
  final model = parseUnifiedDiff(patch);
  unifiedParses++;
  if (_parsed.length >= _remembered) _parsed.remove(_parsed.keys.first);
  return _parsed[patch] = model;
}

final _parsed = <String, DiffModel>{};

/// How many patches [parseUnifiedDiffRemembered] has parsed; for tests.
@visibleForTesting
int unifiedParses = 0;

/// Enough for every diff on a screen, few enough that memory stays small.
const _remembered = 64;

/// A hunk's lines numbered from [oldFirst] and [newFirst], indexed into
/// the sources [old] and [fresh] by their numbers.
DiffHunk _hunk(
  dd.StructuredPatchHunk hunk,
  int old,
  int fresh,
  int oldFirst,
  int newFirst,
) {
  var oldNumber = oldFirst, newNumber = newFirst;
  final lines = <DiffLine>[];
  for (final line in hunk.lines) {
    final text = line.isEmpty ? '' : line.substring(1);
    switch (line.isEmpty ? ' ' : line[0]) {
      case '+':
        lines.add(
          DiffLine(DiffKind.added, newNumber, text, fresh, newNumber - 1),
        );
        newNumber++;
      case '-':
        lines.add(
          DiffLine(DiffKind.removed, oldNumber, text, old, oldNumber - 1),
        );
        oldNumber++;
      case ' ':
        lines.add(
          DiffLine(DiffKind.context, newNumber, text, fresh, newNumber - 1),
        );
        oldNumber++;
        newNumber++;
      // `\ No newline at end of file` is no line of either file.
    }
  }
  return DiffHunk(
    oldStart: hunk.oldStart,
    oldCount: hunk.oldLines,
    newStart: hunk.newStart,
    newCount: hunk.newLines,
    lines: lines,
  );
}

/// A hunk's old run (its context and removed lines) or new run (context
/// and added), as text.
String _run(List<String> lines, String sign) => [
  for (final line in lines)
    if (line.isEmpty || line[0] == ' ' || line[0] == sign)
      line.isEmpty ? '' : line.substring(1),
].join('\n');

/// The file a patch's headers name: the new one, or the old for a deleted
/// file, without git's `a/` or `b/`.
String? _path(dd.StructuredPatch file) {
  String? clean(String name) {
    if (name.isEmpty || name == '/dev/null') return null;
    return name.startsWith('a/') || name.startsWith('b/')
        ? name.substring(2)
        : name;
  }

  return clean(file.newFileName) ?? clean(file.oldFileName);
}

String _withFinalNewline(String text) =>
    text.isEmpty || text.endsWith('\n') ? text : '$text\n';

String _lf(String text) => text.replaceAll('\r\n', '\n');

/// Freezes the selected rows and all model lists for an immutable source lease.
@internal
DiffView freezeDiffView(DiffView view) => DiffView._(
  DiffModel(
    List.unmodifiable([
      for (final hunk in view.model.hunks)
        DiffHunk(
          oldStart: hunk.oldStart,
          oldCount: hunk.oldCount,
          newStart: hunk.newStart,
          newCount: hunk.newCount,
          lines: List.unmodifiable(hunk.lines),
        ),
    ]),
    List.unmodifiable(view.model.sources),
    path: view.model.path,
  ),
  List.unmodifiable(view.rows),
  view.added,
  view.removed,
  view.hidden,
  view.numberWidth,
);
