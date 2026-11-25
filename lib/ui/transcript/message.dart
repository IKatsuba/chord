import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../../session/tasks.dart';
import '../../session/transcript/types.dart';
import 'code_pick.dart' show runnableCodeLanguages;
import 'tools/tools.dart' show Tone;

/// The line that closes a turn the agent started on its own with a
/// message, which chord cancelled: whose turn it was, the person's with no
/// [from], and where the message went, cut at its end to [cells], as what
/// matters comes first.
String selfStartedLine(int cells, [MessageFrom? from]) => truncate(
  from == null
      ? SelfStartedEntry.message
      : 'Interrupted · the agent started this on its own; '
            "${senderName(from)}'s message goes as the next turn",
  cells,
);

/// The one line a team part draws as: whose instructions, for whom, and
/// how long, with the [key] that shows them while they are folded:
/// `bugfix's instructions for tester · 41 lines (ctrl+o to expand)`.
String teamPartLine(TeamPart part, bool expanded, String? key) {
  final lines = part.text.split('\n').length;
  return "${part.team}'s instructions for ${part.member ?? 'the lead'} · "
      '$lines ${lines == 1 ? 'line' : 'lines'}'
      '${expanded || key == null ? '' : ' ($key to expand)'}';
}

/// Where a fork parted from [from], at [at] in local time, cut to [cells]:
/// `── forked from main · 22:10 ──`.
String forkedLine(String from, num at, int cells) {
  final when = DateTime.fromMillisecondsSinceEpoch(at.toInt());
  String two(int part) => part.toString().padLeft(2, '0');
  return truncate(
    '── forked from $from · ${two(when.hour)}:${two(when.minute)} ──',
    cells,
  );
}

/// The header after `←`: `from `, dim, so the row reads as one that came
/// in whichever way the arrow is remembered, then the sender bold, `@` and
/// all, then the rest dim.
({String word, String name, String rest}) messageHeader(MessageFrom from) => (
  word: 'from ',
  name: senderName(from),
  rest: fromLine(from).substring(from.name.length),
);

/// How a message's arrow is drawn: as the text is, dim, or in the error
/// colour. The direction is the arrow's shape, so no tone carries it.
enum ArrowTone { plain, dim, failed }

/// `←`: a failed report's in the error colour, chord's own dim, and a
/// monitor's end by how it ended.
ArrowTone inArrow(MessageFrom from) => switch (from.monitor?.end) {
  final end? => _monitorArrow(end),
  null when from.note == MessageNote.failed => ArrowTone.failed,
  null when from.name == 'chord' => ArrowTone.dim,
  null => ArrowTone.plain,
};

/// A monitor's end: a clean exit plain, the person's stop and its own
/// timeout dim, as stops, and whatever else cut it short an error.
ArrowTone _monitorArrow(MonitorEnd end) => switch (end) {
  MonitorExited(:final code) => code == 0 ? ArrowTone.plain : ArrowTone.failed,
  MonitorStopped() || MonitorTimedOut() => ArrowTone.dim,
  MonitorKilled() || MonitorFlooded() => ArrowTone.failed,
};

/// A monitor's event as its row draws it, [width] wide: the lines it
/// printed, verbatim, as a log's `*` and `_` are no emphasis, each wrapped
/// after its own indent, folded after [messageLines] unless [expanded], with
/// how many the fold left out; and on its end, chord's sentence, which its
/// message carries last and the row draws dim and never folds.
({List<String> lines, int hidden, String? sentence}) monitorMessage(
  String text, {
  required bool ended,
  required bool expanded,
  required int width,
}) {
  final all = text.split('\n');
  final sentence = ended ? all.removeLast() : null;
  String row(List<Glyph> glyphs) => [for (final g in glyphs) g.text].join();
  final rows = [
    for (final line in all)
      for (final glyphs in wrapLine(TextSpan(line), width)) row(glyphs),
  ];
  final (:lines, :hidden) = rows.isEmpty
      ? (lines: const <String>[], hidden: 0)
      : _foldMessage(rows, expanded);
  return (
    lines: lines,
    hidden: hidden,
    sentence: sentence == null
        ? null
        : [
            for (final glyphs in wrapLine(TextSpan(sentence), width))
              row(glyphs),
          ].join('\n'),
  );
}

final _trailing = RegExp(r'\s+$');

/// [rows], their last blank ones dropped, the first [messageLines] of them
/// unless [expanded], and how many were left out.
({List<String> lines, int hidden}) _foldMessage(
  List<String> rows,
  bool expanded,
) {
  // A last blank line would hide a line for nothing.
  final kept = rows.join('\n').replaceFirst(_trailing, '').split('\n');
  if (expanded || kept.length <= messageLines) return (lines: kept, hidden: 0);
  // A fold that ends on a blank line reads as a gap before the fold line.
  final shown = kept
      .take(messageLines)
      .join('\n')
      .replaceFirst(_trailing, '')
      .split('\n');
  return (lines: shown, hidden: kept.length - shown.length);
}

/// `→`, from its call's tone: dim until it is delivered, in the error
/// colour when chord refused it.
ArrowTone outArrow(Tone tone) => switch (tone) {
  Tone.pending || Tone.running => ArrowTone.dim,
  Tone.failed => ArrowTone.failed,
  Tone.done => ArrowTone.plain,
};

/// What a message held to go into the running turn waits on: the person's
/// answer, or the turn's tool calls open as it came.
enum QueueHold { answer, calls }

/// A queued message's row after its `←`: its header,
/// `from @parser · codex: `, and its first line apart, as the row draws the
/// header whole and cuts only the text to the width, so a long name never
/// cuts away why it waits. One held to go into the running turn says in
/// its header what it waits on.
({String header, String text}) queuedMessage(
  MessageFrom from,
  String text, [
  QueueHold? held,
]) {
  final lines = text.split('\n');
  final (:word, :name, :rest) = messageHeader(from);
  final waits = switch (held) {
    null => '',
    QueueHold.answer => ' · after your answer',
    QueueHold.calls => ' · after the running calls',
  };
  return (
    header: '$word$name$rest$waits: ',
    text: lines.length > 1 ? '${lines.first} …' : lines.first,
  );
}

/// [line] wrapped to [width] as the original's `wrapLine`, its indent kept
/// on its first row: as much of it as leaves a cell for the text, so no row
/// is wider than [width].
List<List<Glyph>> wrapLine(TextSpan line, int width) {
  final glyphs = TextLayout.compute(
    line,
    softWrap: false,
    tabWidth: 8,
  ).lines.first;
  var indent = 0;
  while (indent < glyphs.length && glyphs[indent].text.runes.every(_space)) {
    indent++;
  }
  var lead = glyphs.sublist(0, indent);
  while (lead.isNotEmpty && TextLayout.lineWidth(lead) > width - 1) {
    lead = lead.sublist(0, lead.length - 1);
  }
  final rows = TextLayout.wrapAnsi(
    _trimStart(line),
    math.max(1, width - TextLayout.lineWidth(lead)),
    hard: true,
  ).lines;
  return [
    for (final (i, row) in rows.indexed) i == 0 ? [...lead, ...row] : row,
  ];
}

/// Whether JavaScript's `\s` matches [c]: Dart's whitespace less U+0085.
bool _space(int c) => c != 0x85 && String.fromCharCode(c).trim().isEmpty;

/// [line] without its leading whitespace, each run keeping its style, as
/// the original's `trimStart` before wrap-ansi.
TextSpan _trimStart(TextSpan line) {
  final children = <TextSpan>[];
  for (final (part, style) in line.flatten(Style.plain)) {
    var text = part;
    if (children.isEmpty) {
      final runes = part.runes.toList();
      var i = 0;
      while (i < runes.length && _space(runes[i])) {
        i++;
      }
      text = String.fromCharCodes(runes.skip(i));
      if (text.isEmpty) continue;
    }
    children.add(TextSpan(text, style: style));
  }
  return TextSpan('', children: children);
}

/// Each line of [text] through [wrapLine], as the original wraps a
/// headline or a summary line by line, a style holding across lines.
List<List<Glyph>> wrapLines(TextSpan text, int width) {
  final lines = <List<TextSpan>>[[]];
  for (final (part, style) in text.flatten(Style.plain)) {
    for (final (i, piece) in part.split('\n').indexed) {
      if (i > 0) lines.add([]);
      if (piece.isNotEmpty) lines.last.add(TextSpan(piece, style: style));
    }
  }
  return [
    for (final line in lines) ...wrapLine(TextSpan('', children: line), width),
  ];
}

/// The rows a launch's prompt shows before it folds.
const messageLines = 6;

/// A message's words as its body draws them, from the original's
/// `MessageBody`: Markdown, its escapes stripped and its quotes read as the
/// rest of it, with a code block's copy and run unless a fold hides them.
SelectionSource messageSource(
  String text, {
  required Object id,
  required Object revision,
  bool copyCodeBlocks = false,
  bool runCodeBlocks = false,
  SelectionSource? previous,
}) => SelectionSource.markdown(
  id: id,
  revision: revision,
  text: stripAnsi(text),
  quoteBars: false,
  copyCodeBlocks: copyCodeBlocks,
  runCodeBlockLanguages: runCodeBlocks ? runnableCodeLanguages : const {},
  previous: previous,
);

/// The rows of a message's [text] that a fold hides at [width], the item's
/// cells: none unless it [folds].
int messageHidden(String text, int width, {required bool folds}) {
  if (!folds) return 0;
  final rows = Markdown.heightOf(
    messageSource(text, id: 'message', revision: text),
    math.max(width - 5, 1),
  );
  return rows > messageLines ? rows - messageLines : 0;
}
