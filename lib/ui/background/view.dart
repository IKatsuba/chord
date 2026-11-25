/// The background view, kept out of its widget: a row per item with its
/// name, kind, state with time and owner, the name wrapping inside its
/// column, the columns giving way at a narrow width and nothing cut; which
/// rows are in sight around the `❯`; where ↑ ↓ move it; a monitor's detail;
/// and how a followed log steps. From the original's `ui/background/view.ts`,
/// for monitors and tasks; an agent item's stop offer is CTUI-83's.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart'
    show
        Glyph,
        ScrollStep,
        TextLayout,
        TextSpan,
        cellWidth,
        stripAnsi,
        truncate;

import '../../session/elapsed.dart';
import '../../session/monitors.dart';
import '../../session/transcript/types.dart';
import '../dialogs/permission.dart'
    show hiddenRows, requestCount, requestRule, requestStep, requestView;
import '../transcript/agents/subagents.dart' show toolUses;
import '../transcript/message.dart' show wrapLine;
import 'background.dart';

/// Whether [item] is the one [ref] names.
bool sameItem(BackgroundItem item, ItemRef ref) =>
    item.key == ref.key && item.id == ref.id;

ItemRef _ref(BackgroundItem item) => (key: item.key, id: item.id);

/// The item with the `❯`: the one [focus] names, else the first.
BackgroundItem? focusedItem(List<BackgroundItem> items, ItemRef? focus) =>
    (focus == null
        ? null
        : items.where((item) => sameItem(item, focus)).firstOrNull) ??
    items.firstOrNull;

/// Where the `❯` goes once [focus]'s row has left [before], the rows now
/// being [items]: to the row that took its place, or the one above when it
/// was the last; none while its row is still listed, or with no row left.
ItemRef? focusAfter(
  List<BackgroundItem> before,
  List<BackgroundItem> items,
  ItemRef? focus,
) {
  if (focus == null ||
      items.isEmpty ||
      items.any((item) => sameItem(item, focus))) {
    return null;
  }
  final was = before.indexWhere((item) => sameItem(item, focus));
  if (was < 0) return null;
  // The rows above it that are still listed, the first after them being
  // the one that took its place.
  final above = before
      .take(was)
      .where((item) => items.any((each) => sameItem(each, _ref(item))))
      .length;
  return _ref(items[math.min(above, items.length - 1)]);
}

/// Where an open detail on [detail] goes for ↑ ↓ ([by]) over [items].
sealed class DetailStep {
  const DetailStep();
}

/// To the detail of [to].
final class DetailTo extends DetailStep {
  const DetailTo(this.to);
  final ItemRef to;
}

/// Closed: its item left and none is left to take its place.
final class DetailClosed extends DetailStep {
  const DetailClosed();
}

/// Where ↑ ↓ ([by]) take an open detail on [detail] over [items]: the item
/// [by] on, whole items, not lines, as a page key scrolls a tall one; at an
/// end, nowhere, unless its item has ended and leaves once left, when it
/// goes to the item that takes its place, or, none left, closes.
DetailStep? stepDetail(List<BackgroundItem> items, ItemRef detail, int by) {
  final at = items.indexWhere((item) => sameItem(item, detail));
  final item = at < 0 ? null : items[at];
  final next = at < 0 || at + by < 0 || at + by >= items.length
      ? null
      : items[at + by];
  if (next != null) return DetailTo(_ref(next));
  if (item == null || !leavesList(item)) return null;
  final after = focusAfter(items, [
    for (final each in items)
      if (!identical(each, item)) each,
  ], detail);
  return after == null ? const DetailClosed() : DetailTo(after);
}

/// Where a log that follows its end, a task's detail, is read from: its
/// end, as work comes.
const num following = double.infinity;

/// Where [step] takes a log of [total] lines in [room] from [top]: back to
/// [following] once it reaches the end, and `end` back to it always.
num logStep(ScrollStep step, int total, int room, int top) {
  if (step == ScrollStep.bottom) return following;
  final next = requestStep(step, total, room, top);
  final view = requestView(total, room, next);
  // The rows still below, not whether a rule says so: a room of one row
  // has none to draw it in.
  return hiddenRows(total, view.top, view.shown).below > 0 ? next : following;
}

/// A run of a row's line, by what it is, which its colour follows.
enum CellRole { mark, edge, name, kind, state, owner, gap, text }

/// A run of a row's line: its text, what it is, and a state's group for
/// its colour.
typedef ViewCell = ({String text, CellRole role, BackgroundGroup? group});

ViewCell _cell(String text, CellRole role, [BackgroundGroup? group]) =>
    (text: text, role: role, group: group);

/// The two lines pinned on top of a task's detail, which the title, naming
/// no item, leaves to say whose log it is: its name on one line, then its
/// state in its colour, its tool uses, its kind and its owner, dotted, at
/// [width], wrapping after a ` · `; or, [short], on one line cut with `…`,
/// leaving [reserve] cells at its end for the work's count.
List<List<ViewCell>> workHead(
  BackgroundItem item,
  Subagent subagent, {
  required int width,
  required num now,
  bool short = false,
  int reserve = 0,
}) {
  final state = stateText(item, now);
  final uses = toolUses(subagent);
  final parts = [
    _cell(_oneLine(state.text), CellRole.state, state.group),
    _cell('$uses ${uses == 1 ? 'tool use' : 'tool uses'}', CellRole.kind),
    if (item.kind == BackgroundKind.task)
      _cell(['task', ?item.runtime, ?item.model].join(' · '), CellRole.kind),
    _cell(_ownerText(item), CellRole.owner),
  ];
  final name = [_cell(pinnedName(item, width).text, CellRole.name)];
  if (!short) return [name, ..._dotted(parts, width)];
  // On one line, cut where the count, set at its end, leaves it.
  final room = math.max(1, width - reserve);
  final line = <ViewCell>[];
  var used = 0;
  for (final (index, part) in parts.indexed) {
    final text = '${index == 0 ? '' : ' · '}${part.text}';
    final wide = cellWidth(text);
    if (used + wide <= room) {
      line.add(
        index == 0 ? part : (text: text, role: part.role, group: part.group),
      );
      used += wide;
      continue;
    }
    // A part that exactly filled the room gives its last cell to the `…`
    // that says more was cut, rather than the line passing its room.
    final last = line.lastOrNull;
    if (used == room && last != null) {
      line.last = (
        text: truncate('${last.text}$text', cellWidth(last.text)),
        role: last.role,
        group: last.group,
      );
    } else {
      line.add((
        text: truncate(text, room - used),
        role: part.role,
        group: part.group,
      ));
    }
    break;
  }
  return [name, line];
}

/// A task's name as its detail pins it: one line, cut at its end with `…`
/// when longer, so the work keeps its room; whether it was cut, as its
/// whole task is then said under it.
({String text, bool cut}) pinnedName(BackgroundItem item, int width) {
  final whole = _oneLine(stripAnsi(item.name));
  final text = truncate(whole, math.max(1, width));
  return (text: text, cut: text != whole);
}

/// The hint line on an agent item whose agent offers no stop of its own.
const noStopHint = 'this agent offers no stop';

/// The focused agent, when the hint still says it offers no stop and it now
/// offers one.
ItemRef? stopNowOffered(
  List<BackgroundItem> items,
  ItemRef? focus,
  String? hint,
) {
  final item = hint == noStopHint ? focusedItem(items, focus) : null;
  return item != null && item.kind == BackgroundKind.agent && item.stoppable
      ? (key: item.key, id: item.id)
      : null;
}

/// What the frame says of a stop that could not be sent: its error whole,
/// every line of it.
String stopRefused(Object error) =>
    'could not stop: ${switch (error) {
      StateError(:final message) => message,
      _ => '$error',
    }}';

/// A name's column at most; a longer name wraps inside it.
const nameCells = 24;

const _gap = '  ';

/// `no events`, `1 event`, `3 events`.
String _eventsWords(int events) =>
    events == 0 ? 'no events' : '$events ${events == 1 ? 'event' : 'events'}';

/// How long, as an end says it: `3m`, `3m 12s`.
String _after(num ms) => timeoutWords(math.max(0, ms).toInt());

/// An item's state with its time, in its group's colour; [events], a
/// monitor's count after it, left out by its detail, which says it apart.
({String text, BackgroundGroup group}) stateText(
  BackgroundItem item,
  num now, {
  bool events = true,
}) {
  final counted = !events || item.events == null
      ? ''
      : ' · ${_eventsWords(item.events!)}';
  switch (item.status) {
    case ItemRunning(:final stopping):
      final ran = formatElapsed(now - item.startedAt);
      return (
        text: switch (item.kind) {
          BackgroundKind.monitor => 'running $ran$counted',
          BackgroundKind.agent when stopping => '■ stopping $ran',
          BackgroundKind.agent => 'running $ran',
          BackgroundKind.task => 'working $ran',
        },
        group: BackgroundGroup.running,
      );
    case ItemEnded(group: BackgroundGroup.untracked, :final endedAt):
      return (
        text: '? untracked ${formatElapsed(endedAt - item.startedAt)}',
        group: BackgroundGroup.untracked,
      );
    case ItemAsking(:final on, :final since):
      return (
        text: '● ${on.name} ${formatElapsed(now - since)}',
        group: BackgroundGroup.asking,
      );
    // An item is drawn once ended only in its detail, until the person
    // leaves it; a row leaves as it ends.
    // An agent's and a task's end in their own words.
    case ItemEnded(:final group, :final endedAt, :final end, word: final said):
      final ran = _after(endedAt - item.startedAt);
      if (item.kind != BackgroundKind.monitor) {
        return (
          text: switch (group) {
            BackgroundGroup.stopped =>
              '■ ${said?.name ?? 'stopped'} after $ran',
            BackgroundGroup.done when item.kind == BackgroundKind.agent =>
              '✓ done in $ran',
            BackgroundGroup.done => '✓ reported after $ran',
            _ => '✗ ${said?.name ?? 'failed'} after $ran',
          },
          group: group,
        );
      }
      final word = end == null ? group.name : endWord(end);
      // A monitor's timeout is a stop in its own words.
      final glyph = switch (group) {
        BackgroundGroup.stopped => '■',
        BackgroundGroup.done => '✓',
        _ => '✗',
      };
      return (text: '$glyph $word after $ran$counted', group: group);
  }
}

final _space = RegExp(r'\s+');

/// [text] on one line: every run of whitespace one space, as a title is
/// shown.
String _oneLine(String text) => text.replaceAll(_space, ' ').trim();

/// An item's kind as its row says it: a monitor's with its id, which tells
/// monitors of one description apart and names it as its messages do; a
/// task's with its runtime and model; each on one line.
String _kindText(BackgroundItem item) => [
  item.kind.name,
  if (item.kind == BackgroundKind.monitor) item.id,
  ?item.runtime,
  ?item.model,
].map(_oneLine).join(' · ');

/// A kind in lines of at most [width] cells: broken after a ` · `, the `·`
/// ending the line, or starting the next where even it does not fit; a part
/// wider than a line wraps at its spaces.
List<String> _kindIn(String kind, int width) {
  final lines = <String>[];
  for (final part in kind.split(' · ')) {
    final last = lines.lastOrNull;
    if (last == null) {
      lines.addAll(_wrapped(part, width));
    } else if (cellWidth('$last · $part') <= width) {
      lines.last = '$last · $part';
    } else if (cellWidth('$last ·') <= width) {
      lines.last = '$last ·';
      lines.addAll(_wrapped(part, width));
    } else {
      lines.addAll(_wrapped('· $part', width));
    }
  }
  return lines;
}

/// The frame's hint, or an error in its place, in lines of at most [width]
/// cells: its own line breaks kept, each line broken after a ` · ` and at
/// its spaces, never cut.
List<String> hintLines(String text, int width) => [
  for (final line in text.split(RegExp(r'\r\n|\r|\n')))
    ..._kindIn(_oneLine(line), math.max(1, width)),
];

/// The least a state's column holds: its widest word, with a `·` beside it.
int _stateLeast(List<String> states) => states
    .expand((state) => state.split(' '))
    .map((word) => cellWidth(word) + 2)
    .fold(0, math.max);

/// The least a kind's column holds: its widest part with a `·` beside it,
/// after it or, where the line before is full, ahead of it, so a part never
/// breaks inside itself there.
int _kindLeast(List<String> kinds) => kinds
    .expand((kind) {
      final parts = kind.split(' · ');
      return parts.map((part) => cellWidth(part) + (parts.length > 1 ? 2 : 0));
    })
    .fold(0, math.max);

/// One item's row, on as many lines as its name or a narrow width takes.
typedef ViewRow = ({
  BackgroundItem item,
  bool focused,
  List<List<ViewCell>> lines,
});

/// `main`, or the child's name.
String _ownerText(BackgroundItem item) => item.owner?.name ?? 'main';

String _pad(String text, int width) =>
    text + ' ' * math.max(0, width - cellWidth(text));

String _glyphs(List<Glyph> line) => [for (final g in line) g.text].join();

/// [text] in lines of at most [width] cells, broken between words.
List<String> _wrapped(String text, int width) => [
  for (final line in TextLayout.wrapAnsi(
    TextSpan(text),
    math.max(1, width),
    hard: true,
  ).lines)
    _glyphs(line),
];

/// A name in its column: whole on one line where it fits, else wrapped two
/// cells short of the column, as every line after the first is drawn two
/// cells in, so a wrapped name reads as one and stays inside its column.
List<String> _nameIn(String name, int width) =>
    cellWidth(name) <= width && !name.contains('\n')
    ? [name]
    : _wrapped(name, math.max(1, width - 2));

int _widest(Iterable<String> texts) => texts.map(cellWidth).fold(0, math.max);

/// What every line of a row after its first starts with: under the name,
/// two in.
const ViewCell _under = (text: '    ', role: CellRole.gap, group: null);

/// Every item's row in [width] cells: the columns padded to their widest,
/// two cells apart. Where they do not fit the kind wraps in its column,
/// after a ` · `, then the state in its own, and the row grows a line;
/// where even the kind's widest part or the state's widest word does not
/// fit, the state and the owner go under the name, so nothing is cut.
List<ViewRow> viewRows(
  List<BackgroundItem> items, {
  required int width,
  required ItemRef? focus,
  required num now,
}) {
  final focused = focusedItem(items, focus);
  final names = [for (final item in items) stripAnsi(item.name)];
  final nameWidth = math.min(nameCells, _widest(names));
  final owners = [for (final item in items) _ownerText(item)];
  final ownerWidth = _widest(owners);
  ViewCell mark(BackgroundItem item) =>
      _cell(identical(item, focused) ? '❯ ' : '  ', CellRole.mark);
  final kinds = [for (final item in items) _kindText(item)];
  final states = [
    for (final item in items)
      if (stateText(item, now) case (:final text, :final group))
        (text: _oneLine(text), group: group),
  ];
  final fullKind = _widest(kinds);
  final fullState = _widest(states.map((s) => s.text));
  // What the kind and the state share, the name and owner columns kept.
  final room = width - (2 + nameWidth + _gap.length * 3 + ownerWidth);
  // The kind first: as narrow as it goes with no line of it starting with
  // a `·`, or as the state leaves it; then the state, in what is left.
  final least = _kindLeast(kinds);
  int? neat;
  for (var each = least; each <= fullKind; each++) {
    if (kinds.every(
      (kind) => _kindIn(
        kind,
        each,
      ).indexed.every((line) => line.$1 == 0 || !line.$2.startsWith('·')),
    )) {
      neat = each;
      break;
    }
  }
  final kindWidth = fullKind + fullState <= room
      ? fullKind
      : math.max(math.min(fullKind, room - fullState), neat ?? least);
  final stateWidth = math.min(fullState, room - kindWidth);

  // Not even the kind's widest part, or the state's widest word, fits in
  // its column: the state and owner go under the name.
  if (kindWidth < least ||
      stateWidth < _stateLeast([for (final s in states) s.text])) {
    final stacked = _stackedRows(
      names: names,
      kinds: kinds,
      states: states,
      owners: owners,
      nameWidth: nameWidth,
      width: width,
    );
    return [
      for (final (index, lines) in stacked.indexed)
        (
          item: items[index],
          focused: identical(items[index], focused),
          lines: [
            [mark(items[index]), ...lines.first],
            ...lines.skip(1),
          ],
        ),
    ];
  }

  return [
    for (final (index, item) in items.indexed)
      () {
        final nameLines = _nameIn(names[index], nameWidth);
        final kindLines = _kindIn(kinds[index], kindWidth);
        final state = states[index];
        final stateLines = _kindIn(state.text, stateWidth);
        final count = [
          nameLines.length,
          kindLines.length,
          stateLines.length,
        ].reduce(math.max);
        return (
          item: item,
          focused: identical(item, focused),
          lines: [
            for (var at = 0; at < count; at++)
              () {
                final name = at < nameLines.length ? nameLines[at] : '';
                final kind = at < kindLines.length ? kindLines[at] : null;
                final said = at < stateLines.length ? stateLines[at] : null;
                if (at == 0) {
                  return [
                    mark(item),
                    _cell(_pad(name, nameWidth), CellRole.name),
                    _cell(_gap, CellRole.gap),
                    _cell(_pad(kind ?? '', kindWidth), CellRole.kind),
                    _cell(_gap, CellRole.gap),
                    _cell(
                      _pad(said ?? '', stateWidth),
                      CellRole.state,
                      state.group,
                    ),
                    _cell(_gap, CellRole.gap),
                    _cell(owners[index], CellRole.owner),
                  ];
                }
                // Under the name two in, the kind's and the state's next
                // lines in their columns.
                return kind == null && said == null
                    ? [_under, _cell(name, CellRole.name)]
                    : [
                        _under,
                        _cell(_pad(name, nameWidth - 2), CellRole.name),
                        _cell(_gap, CellRole.gap),
                        _cell(_pad(kind ?? '', kindWidth), CellRole.kind),
                        if (said != null) ...[
                          _cell(_gap, CellRole.gap),
                          _cell(said, CellRole.state, state.group),
                        ],
                      ];
              }(),
          ],
        );
      }(),
  ];
}

/// Rows too wide for one line, two lines each: the name with its kind,
/// then the state and the owner, every line after the first two cells
/// further in than the name, so each name alone is at the left edge. Where
/// a name and its kind do not fit, the kind goes to lines of its own,
/// wrapped after a ` · `; a part longer than a line wraps, never cut. The
/// `❯` is the caller's, ahead of the first line.
List<List<List<ViewCell>>> _stackedRows({
  required List<String> names,
  required List<String> kinds,
  required List<({String text, BackgroundGroup group})> states,
  required List<String> owners,
  required int nameWidth,
  required int width,
}) {
  final room = math.max(1, width - _under.text.length);
  // The kinds beside the names where every one fits there.
  final beside = 2 + nameWidth + _gap.length + _widest(kinds) <= width;
  final kindWidth = beside ? _widest(kinds) : 0;
  List<List<ViewCell>> under(
    String text,
    CellRole role, [
    BackgroundGroup? group,
  ]) => [
    for (final line in _wrapped(text, room)) [_under, _cell(line, role, group)],
  ];
  return [
    for (final (index, state) in states.indexed)
      () {
        final owner = owners[index];
        final nameLines = _nameIn(names[index], math.min(nameWidth, width - 2));
        final first = beside
            ? [
                _cell(_pad(nameLines.first, nameWidth), CellRole.name),
                _cell(_gap, CellRole.gap),
                _cell(_pad(kinds[index], kindWidth), CellRole.kind),
              ]
            : [_cell(nameLines.first, CellRole.name)];
        final together =
            cellWidth(state.text) + _gap.length + cellWidth(owner) <= room;
        return [
          first,
          for (final line in nameLines.skip(1))
            [_under, _cell(line, CellRole.name)],
          if (!beside)
            for (final line in _kindIn(kinds[index], room))
              [_under, _cell(line, CellRole.kind)],
          if (together)
            [
              _under,
              _cell(state.text, CellRole.state, state.group),
              _cell(_gap, CellRole.gap),
              _cell(owner, CellRole.owner),
            ]
          else ...[
            ...under(state.text, CellRole.state, state.group),
            ...under(owner, CellRole.owner),
          ],
        ];
      }(),
  ];
}

/// The lines in sight: the rows they are of, how many rows are wholly out
/// of sight above and below, and which of those rows' lines are shown,
/// [height] of them from [from], the frame keeping its height while open.
typedef ViewWindow = ({
  List<ViewRow> rows,
  int above,
  int below,
  int from,
  int height,
});

/// Where the frame is: the item with the `❯`, and the line of all the
/// rows' on top, for the size it was laid out at; at another size the
/// window is found again from the `❯`, a tall row from its first line.
typedef ViewAt = ({ItemRef? focus, int? top, String? laid});

/// The size the rows' lines were laid out at, which a line on top is of.
String laidAt(int width, int height) => '${width}x$height';

/// Each row's first line among all the rows' lines, and how many there are.
({List<int> starts, int total}) _lineStarts(List<ViewRow> rows) {
  final starts = <int>[];
  var total = 0;
  for (final row in rows) {
    starts.add(total);
    total += row.lines.length;
  }
  return (starts: starts, total: total);
}

/// The line on top: [at]'s where it was laid out at this size, else the
/// first that shows the `❯`'s row, from its first line if it is taller than
/// the frame; moved only as far as keeps that row in sight.
({int top, int height}) _topOf(
  List<ViewRow> rows,
  int limit,
  ViewAt? at,
  String? laid,
) {
  final (:starts, :total) = _lineStarts(rows);
  final height = math.min(total, limit);
  final focused = math.max(0, rows.indexWhere((row) => row.focused));
  final first = focused < starts.length ? starts[focused] : 0;
  final end = first + (focused < rows.length ? rows[focused].lines.length : 0);
  final tall = end - first > height;
  final kept = laid != null && at?.laid == laid ? at?.top : null;
  var top = kept ?? (tall ? first : math.max(0, end - height));
  if (tall) {
    top = math.min(math.max(top, first), end - height);
  } else {
    top = math.min(top, first);
    top = math.max(top, end - height);
  }
  return (top: math.min(math.max(0, top), total - height), height: height);
}

/// The lines that fit [limit] with the `❯`'s row in sight, or as much of
/// it as fits where it is taller, from the line on top [at] keeps.
ViewWindow viewWindow(
  List<ViewRow> rows,
  int limit, [
  ViewAt? at,
  String? laid,
]) {
  final (:starts, total: _) = _lineStarts(rows);
  final (:top, :height) = _topOf(rows, limit, at, laid);
  bool inSight(int index) =>
      starts[index] < top + height &&
      starts[index] + rows[index].lines.length > top;
  final firstIn = [for (var i = 0; i < rows.length; i++) i].where(inSight);
  final first = firstIn.firstOrNull ?? 0;
  var end = first;
  while (end < rows.length && inSight(end)) {
    end += 1;
  }
  return (
    rows: rows.sublist(first, end),
    above: first,
    below: rows.length - end,
    from: top - (first < starts.length ? starts[first] : 0),
    height: height,
  );
}

/// ↑ ↓ in the frame: through the lines of a focused row taller than it
/// first, a line at a time, then to the next row, scrolling only as far as
/// brings that row whole into sight; a tall row reached with ↓ shows from
/// its first line, and with ↑ from its last. None with nothing listed.
ViewAt? moveView(
  List<BackgroundItem> items,
  ViewAt? at,
  int by, {
  required int width,
  required int height,
  required num now,
}) {
  final laid = laidAt(width, height);
  final rows = viewRows(items, width: width, focus: at?.focus, now: now);
  final index = rows.indexWhere((row) => row.focused);
  if (index < 0) return null;
  final row = rows[index];
  final (:starts, total: _) = _lineStarts(rows);
  final (:top, height: shown) = _topOf(rows, height, at, laid);
  final first = starts[index];
  final end = first + row.lines.length;
  if (row.lines.length > shown &&
      ((by > 0 && top + shown < end) || (by < 0 && top > first))) {
    return (focus: _ref(row.item), top: top + by, laid: laid);
  }
  final at2 = index + by;
  if (at2 < 0 || at2 >= rows.length) {
    return (focus: _ref(row.item), top: top, laid: laid);
  }
  final next = rows[at2];
  final nextFirst = starts[at2];
  final nextEnd = nextFirst + next.lines.length;
  final nextTop = next.lines.length > shown
      ? by > 0
            ? nextFirst
            : nextEnd - shown
      : nextFirst < top
      ? nextFirst
      : nextEnd > top + shown
      ? nextEnd - shown
      : top;
  return (focus: _ref(next.item), top: nextTop, laid: laid);
}

/// A line in sight, with the row it is of.
typedef ViewLine = ({ViewRow row, List<ViewCell> cells});

/// The lines in sight, the pickers' `↑` on the first where anything is out
/// of sight above and `↓` on the last where anything is below, in the
/// gutter the `❯` stands in, which keeps its place.
List<ViewLine> edgeMarked(ViewWindow shown) {
  final all = [
    for (final row in shown.rows)
      for (final line in row.lines) (row: row, cells: [...line]),
  ];
  final lines = all.skip(shown.from).take(shown.height).toList();
  final above = shown.above > 0 || shown.from > 0;
  final below = shown.below > 0 || shown.from + shown.height < all.length;
  void mark(ViewLine? line, String edge) {
    final first = line?.cells.firstOrNull;
    if (line == null || first == null || first.text.startsWith('❯')) return;
    line.cells.replaceRange(0, 1, [
      _cell(edge, CellRole.edge),
      (
        text: first.text.substring(math.min(edge.length, first.text.length)),
        role: first.role,
        group: first.group,
      ),
    ]);
  }

  if (above) mark(lines.firstOrNull, '↑ ');
  if (below) mark(lines.lastOrNull, '↓ ');
  return lines;
}

/// How long ago, as the agents list says it, to the minute once past one:
/// `16m`, `3h 46m`, `41s`.
String _agoWords(num ms) {
  final words = formatElapsed(math.max(0, ms)).split(' ');
  return (words.length > 1 ? words.where((word) => !word.endsWith('s')) : words)
      .join(' ');
}

/// [parts] joined by ` · ` in lines of at most [width] cells, as a kind
/// breaks: a line broken only between parts, the `·` ending it, or starting
/// the next where even it does not fit; a part wider than a line wraps at
/// its spaces. Each part is wrapped alone and placed whole, so every run
/// keeps its part's role.
List<List<ViewCell>> _dotted(List<ViewCell> parts, int width) {
  final room = math.max(1, width);
  final lines = <List<ViewCell>>[];
  int cells(List<ViewCell> line) => cellWidth(line.map((c) => c.text).join());
  List<ViewCell> pieces(ViewCell part, int within) => [
    for (final text in _wrapped(part.text, within))
      (text: text, role: part.role, group: part.group),
  ];
  for (final part in parts) {
    final last = lines.lastOrNull;
    if (last == null) {
      lines.addAll([
        for (final piece in pieces(part, room)) [piece],
      ]);
      continue;
    }
    final [head, ...rest] = pieces(part, room);
    if (cells(last) + 3 + cellWidth(head.text) <= room) {
      last.addAll([_cell(' · ', CellRole.kind), head]);
      lines.addAll([
        for (final piece in rest) [piece],
      ]);
    } else if (cells(last) + 2 <= room) {
      last.add(_cell(' ·', CellRole.kind));
      lines.addAll([
        for (final piece in pieces(part, room)) [piece],
      ]);
    } else {
      final [first, ...after] = pieces(part, math.max(1, room - 2));
      lines.addAll([
        [_cell('· ', CellRole.kind), first],
        for (final piece in after) [piece],
      ]);
    }
  }
  return lines;
}

/// [text] wrapped after [first], a two-cell lead such as `$ `, its later
/// lines two in under it; with no lead, at the whole width.
List<List<ViewCell>> _wrappedIn(
  String first,
  String text,
  int width,
  CellRole role,
) {
  final indent = first.isEmpty ? '' : '  ';
  // Its own indent on its first line, as an event's is part of what it
  // said, as a monitor's message wraps it.
  return [
    for (final (at, line) in wrapLine(
      TextSpan(text),
      math.max(1, width - cellWidth(indent)),
    ).indexed)
      [_cell('${at == 0 ? first : indent}${_glyphs(line)}', role)],
  ];
}

/// The lines of [item]'s detail in the background frame, in its place of
/// the rows: a monitor's description whole, its state with its events,
/// start, timeout and owner, its command, its last batch with how long ago
/// it came, and, ended, chord's sentence for its end; a task's, its list
/// row alone.
List<List<ViewCell>> detailLines(
  BackgroundItem item, {
  required int width,
  required num now,
}) {
  if (item.kind != BackgroundKind.monitor) {
    return [
      for (final row in viewRows([item], width: width, focus: null, now: now))
        for (final line in row.lines)
          [
            for (final cell in line)
              if (cell.role != CellRole.mark) cell,
          ],
    ];
  }
  final state = stateText(item, now, events: false);
  final name = [
    for (final line in _wrapped(stripAnsi(item.name), width))
      [_cell(line, CellRole.name)],
  ];
  final facts = _dotted([
    // The row's state in its colour, its events after it dim.
    _cell(_oneLine(state.text), CellRole.state, state.group),
    _cell(_eventsWords(item.events ?? 0), CellRole.kind),
    _cell('started ${_agoWords(now - item.startedAt)} ago', CellRole.kind),
    if (item.timeoutMs case final timeout?)
      _cell('timeout ${timeoutWords(timeout)}', CellRole.kind),
    _cell(_ownerText(item), CellRole.owner),
  ], width);
  final command = item.command == null
      ? const <List<ViewCell>>[]
      : _wrappedIn('\$ ', stripAnsi(item.command!), width, CellRole.text);
  final last = item.lastEvent;
  final event = last == null || last.lines.isEmpty
      ? _wrappedIn('← ', 'no events yet', width, CellRole.text)
      : [
          for (final (at, line) in last.lines.indexed)
            ..._wrappedIn(
              at == 0 ? '← ' : '  ',
              '${stripAnsi(line)}'
              '${at == last.lines.length - 1 ? ' · ${_agoWords(now - last.at)} ago' : ''}',
              width,
              CellRole.text,
            ),
        ];
  final end = switch (item.status) {
    ItemEnded(:final end?, :final endedAt) => _wrappedIn(
      '',
      endSentence(end, (endedAt - item.startedAt).toInt()),
      width,
      CellRole.kind,
    ),
    _ => const <List<ViewCell>>[],
  };
  return [...name, ...facts, ...command, ...event, ...end];
}

/// The frame's lines besides its rows: the border, the title and the gap
/// under it, and the gap above the hint.
const _chrome = 6;

/// The lines the frame's rows and its hint share: half the window less its
/// other lines.
int _frameRoom(int windowRows) => windowRows ~/ 2 - (_chrome - 1);

/// The lines the frame's rows take at most: half the window less its other
/// lines, a hint of [hintHeight] lines among them; the rows give way to a
/// hint that wraps, down to one line.
int backgroundRowLimit(int windowRows, [int hintHeight = 1]) =>
    math.max(1, _frameRoom(windowRows) - hintHeight);

/// Which keys the frame's hint names: on a row, enter to its details; in a
/// detail, its own, and none to stop once its item has ended.
enum HintMode { details, detail, ended }

/// Whether [item] has ended, as an open detail keeps one until it is left.
bool _ended(BackgroundItem? item) => switch (item?.status.group) {
  BackgroundGroup.done ||
  BackgroundGroup.failed ||
  BackgroundGroup.stopped => true,
  _ => false,
};

/// The hint's mode for the view open on [detail] over [items].
HintMode hintMode(List<BackgroundItem> items, ItemRef? detail) {
  if (detail == null) return HintMode.details;
  // Its item ended: nothing is left to stop.
  return _ended(items.where((item) => sameItem(item, detail)).firstOrNull)
      ? HintMode.ended
      : HintMode.detail;
}

/// What the frame says under its rows: [hint], a stop's error, in place of
/// its keys, or the keys [mode] names: [stop] the key that stops, [close]
/// and [back] the words of the key that closes and goes back.
String backgroundHint(
  String? hint,
  HintMode mode, {
  String? stop,
  String? close,
  String? back,
}) {
  if (hint != null) return hint;
  final stopping = stop == null ? null : '$stop to stop';
  return switch (mode) {
    HintMode.details => ['Enter for details', ?stopping, ?close].join(' · '),
    HintMode.detail || HintMode.ended => [
      'Enter to go to its call',
      '↑ ↓ for the others',
      if (mode == HintMode.detail) ?stopping,
      ?back,
    ].join(' · '),
  };
}

/// A line of the frame's body: its runs, the item it is of, whose owner
/// colours it, and whether that item has the `❯`, or its detail is open.
typedef FrameLine = ({
  List<ViewCell> cells,
  BackgroundItem? item,
  bool focused,
});

/// The background frame as drawn: its [title] and dim [note], its [body]
/// lines (the rows in sight, or a detail's lines with its rules), its
/// [hint] lines in sight, and the [height] it takes, its gap above
/// included; [detailRoom] and [hintRoom] are the rows a page key scrolls
/// the detail and the hint in, [detailTop] and [hintTop] where they are.
typedef BackgroundFrame = ({
  String title,
  String note,
  List<FrameLine> body,
  List<String> hint,
  int height,
  int detailLines,
  int detailRoom,
  int hintLines,
  int hintRoom,
  bool errorTall,
  ({Subagent subagent, String? task, int rows})? log,
});

/// The frame [view] draws over [items] in a window [columns] by [rows]:
/// the rows around the `❯`, or the open detail paged from [detailTop]; the
/// hint, [said] whole, paged from [hintTop] where it is taller than what
/// the rows leave it. [pageUp] and [pageDown] name the keys its rules say.
BackgroundFrame backgroundFrame(
  List<BackgroundItem> items, {
  required ItemRef? focus,
  required ItemRef? detail,
  required ViewAt? at,
  required String said,
  required bool hinted,
  required int columns,
  required int rows,
  required num now,
  int detailTop = 0,
  int hintTop = 0,
  String? pageUp,
  String? pageDown,
  Subagent? work,
  int? logLines,
  int? logTop,
}) {
  final width = math.max(1, columns - 4);
  final shownAt = detail == null
      ? -1
      : items.indexWhere((item) => sameItem(item, detail));
  final detailed = shownAt < 0 ? null : items[shownAt];
  final hint = hintLines(said, width);
  final height = backgroundRowLimit(rows, hint.length);
  final body = <FrameLine>[];
  var detailCount = 0;
  final detailRoom = math.max(1, height);
  var errorTall = false;
  ({Subagent subagent, String? task, int rows})? log;
  int used;
  final logged =
      detailed != null &&
      detailed.kind != BackgroundKind.monitor &&
      work != null;
  if (logged) {
    errorTall = hinted && hint.length > _frameRoom(rows) - 1;
  }
  if (logged && !errorTall) {
    // Its name and state pinned, then its log in the room left: the state
    // line gives way to one line first, then the log to one row, then to
    // none.
    final full = workHead(detailed, work, width: width, now: now);
    final short = full.length + 1 > detailRoom;
    final logRows = math.max(0, detailRoom - (short ? 2 : full.length));
    // With no row for its log, what is out of view is said at the state
    // line's end, the log read from its end.
    String? count;
    if (logRows == 0 && logLines != null && logLines > 1) {
      final view = requestView(logLines, 1, logTop ?? logLines);
      count = requestCount(hiddenRows(logLines, view.top, view.shown));
    }
    final cells = short
        ? workHead(
            detailed,
            work,
            width: width,
            now: now,
            short: true,
            reserve: count == null ? 0 : cellWidth(count) + 1,
          )
        : full;
    // Not even its name and state: its state line alone.
    final head = [
      ...(detailRoom < 2 ? [cells.last] : cells),
    ];
    if (count != null) {
      final last = head.removeLast();
      final used = cellWidth(last.map((c) => c.text).join());
      head.add([
        ...last,
        _cell(' ' * math.max(1, width - used - cellWidth(count)), CellRole.gap),
        _cell(count, CellRole.edge),
      ]);
    }
    body.addAll([
      for (final line in head) (cells: line, item: detailed, focused: true),
    ]);
    final whole = (work.prompt ?? work.description)?.trim();
    // Its task, unless the pinned name already says it whole.
    final task =
        whole == null ||
            whole.isEmpty ||
            (!pinnedName(detailed, width).cut &&
                whole.replaceAll(_space, ' ') ==
                    detailed.name.replaceAll(_space, ' ').trim())
        ? null
        : whole;
    // As tall as its lines, once they are laid out, up to its room.
    final shown = logLines == null ? logRows : math.min(logRows, logLines);
    log = (subagent: work, task: task, rows: shown);
    used = head.length + shown;
  } else if (detailed == null) {
    final lines = edgeMarked(
      viewWindow(
        viewRows(items, width: width, focus: focus, now: now),
        height,
        at,
        laidAt(width, height),
      ),
    );
    body.addAll([
      for (final line in lines)
        (cells: line.cells, item: line.row.item, focused: line.row.focused),
    ]);
    used = lines.length;
  } else {
    final detailRows = detailLines(detailed, width: width, now: now);
    detailCount = detailRows.length;
    // A stop's error taller than what a detail of one line leaves it: the
    // detail gives way to its first line, which says whose it is, and does
    // not page; the error takes the page keys alone.
    errorTall = hinted && hint.length > _frameRoom(rows) - 1;
    final shown = errorTall
        ? (top: 0, shown: 1, above: false, below: false)
        : requestView(detailRows.length, detailRoom, detailTop);
    final hidden = hiddenRows(detailRows.length, shown.top, shown.shown);
    FrameLine of(List<ViewCell> cells) =>
        (cells: cells, item: detailed, focused: true);
    if (shown.above) {
      body.add(
        of([
          _cell(requestRule('↑', hidden.above, pageUp, width), CellRole.edge),
        ]),
      );
    }
    body.addAll(detailRows.skip(shown.top).take(shown.shown).map(of));
    if (shown.below) {
      body.add(
        of([
          _cell(requestRule('↓', hidden.below, pageDown, width), CellRole.edge),
        ]),
      );
    }
    used = shown.shown + (shown.above ? 1 : 0) + (shown.below ? 1 : 0);
  }
  // An error taller than what the rows leave it scrolls in that room, as a
  // request does in its box.
  final hintRoom = math.max(1, _frameRoom(rows) - used);
  final shown = requestView(hint.length, hintRoom, hintTop);
  final hidden = hiddenRows(hint.length, shown.top, shown.shown);
  final hintShown = [
    if (shown.above) requestRule('↑', hidden.above, pageUp, width),
    ...hint.skip(shown.top).take(shown.shown),
    if (shown.below) requestRule('↓', hidden.below, pageDown, width),
  ];
  return (
    title: 'Background',
    note: detailed == null
        ? ' · ${items.length} in this session'
        : ' · ${detailed.kind == BackgroundKind.monitor ? '${detailed.id}, ' : ''}'
              '${shownAt + 1} of ${items.length}'
              '${_ended(detailed) ? ' · ended' : ''}',
    body: body,
    hint: hintShown,
    // Its gap above, the border, the title and the gap under it, the body
    // and a task's log, the gap above the hint, and the hint.
    height:
        1 + 2 + 1 + 1 + body.length + (log?.rows ?? 0) + 1 + hintShown.length,
    log: log,
    detailLines: detailCount,
    detailRoom: detailRoom,
    hintLines: hint.length,
    hintRoom: hintRoom,
    errorTall: errorTall,
  );
}
