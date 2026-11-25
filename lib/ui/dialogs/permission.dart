import 'dart:convert';
import 'dart:math';

import 'package:chord_tui/chord_tui.dart';

import '../../acp/schema.dart' as acp;
import '../transcript/tools/diff.dart';
import '../transcript/message.dart' show wrapLine;
import '../transcript/tools/paths.dart';
import '../../session/transcript/types.dart';

/// The settled permission's wording and whether it allowed the call.
({String text, bool allowed}) permissionOutcome(PermissionEntry entry) {
  final option = entry.option;
  final allowed =
      option != null &&
      (option.kind == 'allow_once' || option.kind == 'allow_always');
  final what = entry.title ?? 'the tool call';
  final how = allowed ? ' · ${option!.name}' : '';
  return (
    text: '${allowed ? 'Allowed' : 'Rejected'} $what$how',
    allowed: allowed,
  );
}

/// The oldest unanswered request, when the turn waits on permission.
PermissionWait? askedPermission(TurnState turn) =>
    turn is AwaitingPermission && turn.permissions.isNotEmpty
    ? turn.permissions.first
    : null;

/// A numbered agent option and the wire value it answers with.
typedef Choice = ({String key, String label, String value});

/// The agent's options, numbered in its own order.
List<Choice> choicesFor(PermissionWait wait) => [
  for (final (i, option) in wait.options.indexed)
    (
      key: option.optionId,
      label: '${i + 1}. ${option.name}',
      value: option.optionId,
    ),
];

/// The cells between a save box's choice and the file it writes.
const _fileGap = 2;

/// The choices of chord's own question, as its save box asks it: each
/// numbered, the file it writes after it, in a column of its own.
List<Choice> saveChoices(PermissionWait wait) {
  final files = wait.save?.files ?? const {};
  final labels = [
    for (final (i, option) in wait.options.indexed) '${i + 1}. ${option.name}',
  ];
  var width = 0;
  for (final (i, option) in wait.options.indexed) {
    if (files.containsKey(option.optionId)) {
      width = max(width, labels[i].length);
    }
  }
  return [
    for (final (i, option) in wait.options.indexed)
      (
        key: option.optionId,
        label: switch (files[option.optionId]) {
          final file? => '${labels[i].padRight(width + _fileGap)}$file',
          null => labels[i],
        },
        value: option.optionId,
      ),
  ];
}

/// Locations not already named at the end of the title.
List<String> locationsShown(PermissionWait wait, [PathView? paths]) => [
  for (final location in wait.locations ?? <acp.ToolCallLocation>[])
    if (!(wait.title ?? '').endsWith(location.path))
      wait.kind == 'execute'
          ? 'in ${shownDirectory(location.path, paths)}'
          : location.path,
];

String _shown(Object? value) => value is String ? value : jsonEncode(value);

/// Arguments shown when the request has no content: strings unquoted.
List<String> inputLines(PermissionWait wait) {
  final input = wait.rawInput;
  if (input == null) return [];
  if (input is! Map) return [_shown(input)];
  return [
    for (final entry in input.entries) '${entry.key}: ${_shown(entry.value)}',
  ];
}

/// Cells argument and diff rows hang in from the request edge.
const inputIndent = 2;

/// A row in the scrolling request, before a diff's physical wrapping.
sealed class RequestRow {
  const RequestRow();
}

/// A wrapped title continuation, location or argument row.
final class RequestText extends RequestRow {
  const RequestText(this.text, this.kind);
  final String text;
  final String kind;
}

/// A proposed change drawn through the framework's reusable diff view.
final class RequestDiff extends RequestRow {
  const RequestDiff(this.view);
  final ToolDiffView view;
}

List<String> _wrapped(String text, int width) => [
  for (final line in text.split('\n')) ..._wrappedLine(line, width),
];

List<String> _wrappedLine(String line, int width) => [
  for (final row in wrapLine(TextSpan(line), width))
    row.map((g) => g.text).join(),
];

/// Pinned first title row followed by title, locations, arguments and diffs.
({String pinned, List<RequestRow> rows}) requestRows(
  PermissionWait wait,
  int width, {
  int? titleWidth,
  PathView? paths,
}) {
  final title = _wrapped(wait.title ?? 'Tool call', titleWidth ?? width);
  final diffs = [
    for (final item in wait.content ?? <acp.ToolCallContent>[])
      if (item.diff case final diff?)
        diffView(diff.path, diff.oldText, diff.newText),
  ];
  return (
    pinned: title.first,
    rows: [
      for (final text in title.skip(1)) RequestText(text, 'title'),
      for (final location in locationsShown(wait, paths))
        for (final text in _wrapped(location, width))
          RequestText(text, 'location'),
      for (final line in inputLines(wait))
        for (final text in _wrapped(line, width - inputIndent))
          RequestText(text, 'input'),
      if (diffs.isNotEmpty) const RequestText('', 'input'),
      for (final diff in diffs) ...[
        if (diffs.length > 1)
          for (final text in _wrapped(diff.path, width))
            RequestText(text, 'location'),
        RequestDiff(diff),
      ],
    ],
  );
}

/// Physical request rows, a diff's as the original's wrap-ansi wraps it.
int requestHeight(List<RequestRow> rows, int width) => rows.fold(
  0,
  (height, row) =>
      height +
      (row is RequestDiff
          ? Diff.measure(
              row.view.view,
              width - inputIndent,
              wrap: DiffWrap.wrapAnsi,
            )
          : 1),
);

/// The visible physical rows and the rules that share their room.
typedef RequestView = ({int top, int shown, bool above, bool below});

/// Clamps a request's view and leaves space for its hidden-row rules.
RequestView requestView(int total, num room, int top) {
  if (total <= room || room.isNaN) {
    return (top: 0, shown: total, above: false, below: false);
  }
  if (room <= 2) {
    final int shown = max(room, 0) == 0 ? 0 : 1;
    final at = min(max(top, 0), total - max(shown, 1)).toInt();
    final below = room == 2 && at < total - 1;
    return (top: at, shown: shown, above: room == 2 && !below, below: below);
  }
  final end = total - (room.toInt() - 1);
  if (top <= 0) {
    return (top: 0, shown: room.toInt() - 1, above: false, below: true);
  }
  return top >= end
      ? (top: end, shown: room.toInt() - 1, above: true, below: false)
      : (top: top, shown: room.toInt() - 2, above: true, below: true);
}

/// A key's next request offset, paging without passing over any row.
int requestStep(ScrollStep step, int total, int room, int top) {
  final view = requestView(total, room, top);
  int to(int next) => requestView(total, room, next).top;
  if (room == 1 && step != ScrollStep.top && step != ScrollStep.bottom) {
    return to(
      view.top +
          (step == ScrollStep.pageDown || step == ScrollStep.lineDown ? 1 : -1),
    );
  }
  return switch (step) {
    ScrollStep.pageDown => to(view.top + view.shown),
    ScrollStep.pageUp =>
      room >= 3 && view.top - 1 <= room - 2
          ? 0
          : to(view.top - max(room - 2, 1)),
    ScrollStep.lineDown => to(view.top + 1),
    ScrollStep.lineUp => to(view.top - 1),
    ScrollStep.top => 0,
    ScrollStep.bottom => to(total),
  };
}

/// Physical request rows outside the visible range.
({int above, int below}) hiddenRows(int total, int top, int view) =>
    (above: max(0, top), below: max(0, total - top - max(view, 0)));

/// Hidden counts beside the pinned title in a one-row request room.
String requestCount(({int above, int below}) hidden) {
  final (:above, :below) = hidden;
  String lines(int count) => '$count ${count == 1 ? 'line' : 'lines'}';
  return above == 0
      ? '↓ ${lines(below)} below'
      : below == 0
      ? '↑ ${lines(above)} above'
      : '↑ $above above · ↓ $below below';
}

/// Stable space for the widest count, allowing for extra title wrapping.
int countRoom(int total) {
  final most = pow(10, (total * 2).toString().length).toInt() - 1;
  return cellWidth(requestCount((above: most, below: most)));
}

/// A hidden-row rule, with its scroll key when it fits.
String requestRule(String way, int count, String? key, int width) {
  final words =
      '$way $count ${count == 1 ? 'line' : 'lines'} ${way == '↑' ? 'above' : 'below'}';
  final whole = '── $words${key == null ? '' : ' · $key to scroll'} ';
  final text = cellWidth(whole) < width ? whole : '── $words ';
  return text + '─' * max(0, width - cellWidth(text));
}
