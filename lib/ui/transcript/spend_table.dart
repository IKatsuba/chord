/// `/cost`'s table of what the window has spent, once it holds more than one
/// session: a row for the main session, then each agent beside it, closed
/// ones too, task agents under the session that started them, and the
/// window's total, each with a note; a cell that does not fit wraps inside
/// itself, and nothing is cut. From the original's
/// `ui/transcript/spend_table.ts`; team runs' rows come with their parts.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart';

import '../../js_trim.dart';
import '../../session/transcript/types.dart' show ReportRow;
import '../../session/turn_costs.dart' show Cost;
import 'reports.dart' show formatCost, formatDay, formatTokens;
import 'spend.dart';

/// A figure no part reported, in a cost or token column.
const _none = '—';

/// A row before it is laid out: its name, how deep under the session that
/// started it, its figures and notes.
typedef _Row = ({
  String name,
  int depth,
  String cost,
  String tokens,
  List<String> notes,
});

/// Whether the window holds more than one session, a task or a closed one
/// counted.
bool manySessions(List<SpendPart> parts) {
  int count(SpendPart part) =>
      (part.kind == SpendKind.team ? 0 : 1) +
      part.parts.fold(0, (all, under) => all + count(under));
  return parts.fold(0, (all, part) => all + count(part)) > 1;
}

/// [cost] as the table writes it: `~` ahead of chord's estimate.
String _costText(Cost cost, bool estimated) =>
    '${estimated ? '~' : ''}${formatCost(cost)}';

/// What a figure says beside itself: whose estimate, older sums, turns left
/// out; for an agent that gives running totals and no cost, that its
/// provider gives none, said of [runtime].
List<String> _figureNotes(Figure? figure, [String? runtime]) {
  final notes = <String>[];
  final totals = figure?.totals;
  final none = totals != null
      ? "${runtime ?? 'its agent'}'s provider reports no cost; "
      : '';
  final unpriced = totals?.unpriced ?? const <String>[];

  if (figure?.estimated == Estimated.all) {
    final models = figure!.models;
    final model = models.firstOrNull;
    notes.add(
      none +
          (unpriced.isNotEmpty
              ? "chord's estimate from its models' prices; no price for "
                    "${unpriced.join(' and ')}"
              : model != null && models.length == 1
              ? "chord's estimate from $model's price"
              : "chord's estimate from its models' prices"),
    );
  } else if (totals != null && figure!.cost == null) {
    final named = unpriced.isEmpty
        ? totals.model ?? 'its model'
        : unpriced.join(' and ');
    notes.add('${none}no price for $named');
  } else if (figure?.estimated == Estimated.part) {
    notes.add("part chord's estimate");
  }

  if (figure?.before case final before?) {
    final until = before.until;
    notes.add(
      until == null
          ? 'as last reported'
          : 'as last reported before ${formatDay(until)}',
    );
  }

  // An agent that gives running totals says what it left out by the models
  // chord has no price for.
  if (figure != null && figure.uncounted > 0 && totals == null) {
    notes.add(
      '${figure.uncounted} ${figure.uncounted == 1 ? 'turn' : 'turns'} '
      'not counted',
    );
  }

  return notes;
}

/// A session's or task's own row.
_Row _ownRow(
  String name,
  int depth,
  Figure? figure, [
  List<String> kind = const [],
  String? runtime,
]) => (
  name: name,
  depth: depth,
  cost: figure?.cost == null
      ? 'not reported'
      : _costText(figure!.cost!, figure.estimated != Estimated.none),
  tokens: figure?.tokens == null ? _none : formatTokens(figure!.tokens!),
  notes: [...kind, ..._figureNotes(figure, runtime)],
);

/// A group's row: what is under it added up.
_Row _sumRow(
  String name,
  int depth,
  Summed summed, [
  List<String> notes = const [],
]) => (
  name: name,
  depth: depth,
  cost: summed.cost == null
      ? 'not reported'
      : _costText((
          amount: summed.cost!,
          currency: 'USD',
        ), summed.estimated != Estimated.none),
  tokens: summed.tokens == null ? _none : formatTokens(summed.tokens!),
  notes: notes,
);

/// A task agent's row, under the session that started it, and the rows of
/// any under it; [owner] names that session where the row above is not it,
/// as under a team run.
List<_Row> _taskRows(SpendPart task, int depth, [String? owner]) {
  final kind = owner == null ? 'task agent' : 'task agent of $owner';
  return [
    task.running
        ? (
            name: task.name,
            depth: depth,
            cost: _none,
            tokens: _none,
            notes: ['$kind, running: counted when it ends'],
          )
        : _ownRow(task.name, depth, task.figure, ['$kind, ended']),
    for (final under in task.parts) ..._taskRows(under, depth + 1, owner),
  ];
}

/// A session's row, its own spend, and its task agents' rows under it.
List<_Row> _sessionRows(
  SpendPart part,
  String name,
  int depth, [
  List<String> kind = const [],
]) => [
  _ownRow(name, depth, part.figure, kind, part.runtime ?? part.agent),
  for (final task in part.parts) ..._taskRows(task, depth + 1),
];

/// A team run's rows: its lead and members added up, each named in its
/// note, then the task agents they started, each with its owner.
List<_Row> _teamRows(SpendPart team, int depth) {
  final members = team.parts;
  final each = [
    for (final member in members)
      '${member.name} ${member.figure?.cost == null ? 'not reported' : _costText(member.figure!.cost!, member.figure!.estimated != Estimated.none)}',
  ].join(' · ');
  return [
    _sumRow(
      team.name,
      depth,
      sum([for (final member in members) member.alone]),
      ['team run${team.ended ? ', ended' : ''}: $each'],
    ),
    for (final member in members)
      for (final task in member.parts)
        ..._taskRows(task, depth + 1, member.name),
  ];
}

/// The rows of a long-lived agent, open or closed, of a team run, or of a
/// task.
List<_Row> _childRows(SpendPart part, int depth) => switch (part.kind) {
  SpendKind.team => _teamRows(part, depth),
  SpendKind.task => _taskRows(part, depth),
  _ => _sessionRows(part, part.name, depth, [
    part.ended ? 'agent, closed' : 'agent',
  ]),
};

/// The window's rows: the main session open now, the sessions `/clear` let
/// go as one row, `before /clear`, and each agent, every row its own spend,
/// task agents under the session that started them.
List<_Row> _windowRows(List<SpendPart> parts) {
  final mains = parts.where((part) => part.kind == SpendKind.main).toList();
  final own = mains.where((part) => !part.ended).firstOrNull;
  final cleared = mains.where((part) => !identical(part, own)).toList();
  final rest = parts.where((part) => part.kind != SpendKind.main);

  return [
    if (own != null) ..._sessionRows(own, 'main', 0),
    if (cleared.isNotEmpty) ...[
      _sumRow(
        'before /clear',
        0,
        sum([for (final session in cleared) session.alone]),
        cleared.length > 1 ? ['${cleared.length} sessions'] : const [],
      ),
      for (final session in cleared)
        for (final task in session.parts) ..._taskRows(task, 1),
    ],
    for (final part in rest) ..._childRows(part, 0),
  ];
}

/// The tasks still running anywhere under [parts].
int _running(List<SpendPart> parts) => parts.fold(
  0,
  (all, part) => all + (part.running ? 1 : 0) + _running(part.parts),
);

/// Whether a figure under [parts] holds an older record's sum.
bool _lastReported(List<SpendPart> parts) => parts.any(
  (part) => part.figure?.before != null || _lastReported(part.parts),
);

/// The Total row: the window's sum, and what its figures leave out.
_Row _totalRow(List<SpendPart> parts) {
  final summed = sum(parts);
  final tasks = _running(parts);
  final notes = [
    if (summed.estimated == Estimated.all)
      "chord's estimate"
    else if (summed.estimated == Estimated.part)
      "part chord's estimate",
    if (_lastReported(parts)) 'part as last reported',
    if (summed.uncounted != 0)
      '${summed.uncounted} ${summed.uncounted == 1 ? 'turn' : 'turns'} '
          'not counted',
    for (final name in summed.missing) '$name not reported',
    for (final name in summed.providers) "$name's provider reports no cost",
    if (tasks != 0) '$tasks running',
  ];

  return _sumRow('Total', 0, summed, notes);
}

final _spaces = RegExp(r'\s+');
final _endSpaces = RegExp(r'\s+$');

/// [text] on one line, as a name a person or an agent gave may span
/// several: every run of whitespace one space, as a prompt's line is shown.
String _oneLine(String text) => jsTrim(text.replaceAll(_spaces, ' '));

/// [text] without JavaScript's whitespace at its end, as `trimEnd` drops it.
String _trimEnd(String text) => text.replaceAll(_endSpaces, '');

/// [text] wrapped to [cells] at its spaces, a word wider broken.
List<String> _wrapped(String text, int cells) {
  final lines = [
    for (final line in TextLayout.wrapAnsi(
      TextSpan(text),
      math.max(1, cells),
      hard: true,
    ).lines)
      line.map((glyph) => glyph.text).join(),
  ];
  // wrap-ansi gives an empty string one empty line.
  return lines.isEmpty ? [''] : lines;
}

final _noteBreaks = RegExp(r'(?<=;|·) ');

/// A note's lines in [cells]: it breaks between its parts, after a `; ` or
/// a ` · `, where it can, and inside a part only where that part alone is
/// wider, so `1 turn not counted` stays whole on a line.
List<String> _noteLines(String note, int cells) {
  final lines = <String>[];
  for (final part in note.split(_noteBreaks)) {
    final last = lines.lastOrNull;
    if (last != null && cellWidth('$last $part') <= cells) {
      lines[lines.length - 1] = '$last $part';
    } else {
      lines.addAll(_wrapped(part, cells));
    }
  }
  return lines;
}

/// [text] padded with spaces to [cells] columns, at its end or its start.
String _pad(String text, int cells, [bool start = false]) {
  final fill = ' ' * math.max(0, cells - cellWidth(text));
  return start ? fill + text : text + fill;
}

/// Two spaces for each level a row is under the session that started it.
String _indent(_Row row) => '  ' * row.depth;

/// The least a note's cell keeps beside the figures; narrower, the note
/// goes below them.
const _noteLeast = 20;

/// The name column's heading.
const _heading = 'This session';

/// The header's name, which the name column is never narrower than.
final _nameLeast = _heading.length;

/// The table's lines for the window's spend in [width] cells: the cost and
/// token columns as wide as their widest figure, on a row's first line; the
/// name column at most a third of the table, a longer name wrapping in it;
/// the note the rest, wrapping between its parts, or below the figures
/// where that leaves it fewer than 20 cells. A row is as tall as its
/// tallest cell, and nothing is cut.
List<ReportRow> spendTable(List<SpendPart> parts, int width) {
  final rows = [..._windowRows(parts), _totalRow(parts)];
  final costWidth = rows.fold(
    cellWidth('Cost'),
    (n, row) => math.max(n, cellWidth(row.cost)),
  );
  final tokenWidth = rows.fold(
    cellWidth('Tokens'),
    (n, row) => math.max(n, cellWidth(row.tokens)),
  );
  final figures = 2 + costWidth + 2 + tokenWidth;
  // At most a third of the table, the figures never moved.
  final nameWidth = [
    rows.fold(
      _nameLeast,
      (n, row) => math.max(n, cellWidth(_indent(row) + _oneLine(row.name))),
    ),
    math.max(_nameLeast, width ~/ 3),
    math.max(1, width - figures),
  ].reduce(math.min);
  final noteWidth = width - nameWidth - figures - 2;
  String line(String name, String cost, String tokens) =>
      '${_pad(name, nameWidth)}  ${_pad(cost, costWidth, true)}  '
      '${_pad(tokens, tokenWidth, true)}';

  return [
    (label: '', text: line(_heading, 'Cost', 'Tokens')),
    for (final row in rows)
      ..._rowLines(row, width, nameWidth, noteWidth, line),
  ];
}

/// [row]'s lines: its name wrapped in its column, and its note beside the
/// figures, or below them when [noteWidth] is under 20 cells.
List<ReportRow> _rowLines(
  _Row row,
  int width,
  int nameWidth,
  int noteWidth,
  String Function(String name, String cost, String tokens) line,
) {
  // The name's next lines under its first letter, the indent held.
  final indent = _indent(row);
  final names = [
    for (final each in _wrapped(
      _oneLine(row.name),
      nameWidth - cellWidth(indent),
    ))
      indent + each,
  ];
  final note = _oneLine(row.notes.join('; '));

  // Too narrow beside the figures, the note goes below them: from the row's
  // second line, at the cost column's left edge, beside the name's next
  // lines, to the table's end; under the name it would read as a row of
  // its own.
  if (noteWidth < _noteLeast) {
    final below = note.isEmpty
        ? const <String>[]
        : _noteLines(note, width - nameWidth - 2);
    return [
      for (var at = 0; at < math.max(names.length, 1 + below.length); at++)
        (
          label: '',
          text: _trimEnd(switch ((
            at,
            at == 0 ? null : below.elementAtOrNull(at - 1),
          )) {
            (0, _) => line(names[0], row.cost, row.tokens),
            (_, null) => names.elementAtOrNull(at) ?? '',
            (_, final said?) =>
              '${_pad(names.elementAtOrNull(at) ?? '', nameWidth)}  $said',
          }),
        ),
    ];
  }

  final notes = note.isEmpty ? const <String>[] : _noteLines(note, noteWidth);
  return [
    for (var at = 0; at < math.max(names.length, notes.length); at++)
      (
        label: '',
        text: _trimEnd(switch ((
          at == 0
              ? line(names[0], row.cost, row.tokens)
              : line(names.elementAtOrNull(at) ?? '', '', ''),
          notes.elementAtOrNull(at),
        )) {
          (final shown, null) => shown,
          (final shown, final said?) => '$shown  $said',
        }),
      ),
  ];
}
