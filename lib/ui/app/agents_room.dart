/// How a short window shares its rows between the transcript, the agents
/// list and a request's box, computed before layout and in lines, as the
/// original's Yoga column and CHD-464's latch settle them: the transcript
/// gives way first, to no rows; then the list, from its limit down to its
/// floor, together with a plan's Note and a held form, question or link,
/// each by its natural height; then, once the list is at its floor, a
/// permission's body.
library;

import 'dart:math' as math;

import 'package:chord_tui/chord_tui.dart' show unbounded;

import '../agents/agents.dart' show agentsRowLimit;

/// When a request's box gives up its shrinkable rows.
enum RoomGives {
  /// Never: it is drawn whole, its least its natural height (a form,
  /// question or link with the keys).
  never,

  /// With the list, each by its natural height, as Yoga shrinks two items
  /// of `flexShrink` 1 (a plan's Note; a held form, question or link).
  withList,

  /// Only once the list has folded to its floor (a permission's body,
  /// the original's `givesWay={listFolded}`).
  afterList,
}

/// What one request box asks of the window, in lines.
final class RoomRequest {
  /// A box [natural] lines high, never under [fixed], giving way as
  /// [gives] says.
  const RoomRequest({
    required this.fixed,
    required this.natural,
    this.gives = RoomGives.never,
  });

  /// The lines that never give way: its least.
  final int fixed;

  /// Its height with all the room it wants.
  final int natural;

  /// When its shrinkable lines give way.
  final RoomGives gives;
}

/// The window's rows as [agentsRoom] shares them.
final class AgentsRoom {
  /// A share of [transcript] rows, a list of [list] lines drawn in
  /// [limit], and each request's [requests] lines.
  const AgentsRoom({
    required this.transcript,
    required this.list,
    required this.limit,
    required this.requests,
    required this.folded,
  });

  /// The rows left to the transcript; 0 once anything else gives way.
  final int transcript;

  /// The lines the list's box takes; 0 with no child.
  final int list;

  /// The limit the list is drawn in: its box's lines, at least 1, at most
  /// `agentsRowLimit`.
  final int limit;

  /// Each request's lines, in the order asked: the `maxRows` its box is
  /// given.
  final List<int> requests;

  /// The list is held at its floor, so a permission's body gives way.
  final bool folded;

  @override
  String toString() =>
      'AgentsRoom(transcript: $transcript, list: $list, limit: $limit, '
      'requests: $requests, folded: $folded)';
}

/// The rows of a window [rows] high, of which [fixed] never give way (the
/// status line, the working line, the live plan, the queue and the prompt),
/// shared between the transcript, the agents list, whose lines drawn in a
/// limit [linesAt] counts (0 with no child), and [requests], drawn above
/// the list in this order.
///
/// With room, the list takes the lines its limit, `agentsRowLimit(rows)`,
/// draws and the transcript the rest. Short of it, the transcript gives
/// all; then the list and every request that gives [RoomGives.withList]
/// shrink together, each by its natural height, rounded to cells as Yoga
/// rounds edges; once the list is at its floor (one row and `… +N more`) it
/// stays there and the requests that give [RoomGives.afterList] shrink with
/// the rest. When even the least of each does not fit, everything is at its
/// least and the window clips at its bottom.
AgentsRoom agentsRoom({
  required int rows,
  required int fixed,
  required int Function(int limit) linesAt,
  List<RoomRequest> requests = const [],
}) {
  if (rows < 0 || rows >= unbounded) {
    throw ArgumentError.value(rows, 'rows', 'must be a finite height');
  }
  final avail = math.max(0, rows - fixed);
  final rowLimit = agentsRowLimit(rows);
  final full = linesAt(rowLimit);
  final floor = math.min(full, linesAt(1));
  final canFold = full > floor;

  final open = _share(avail, requests, full, floor, folded: !canFold);
  // The original's latch: a list laid out at its floor stays there, and a
  // permission's body gives way; it unfolds only while the transcript has
  // rows, which a folded list never leaves it.
  final settled = canFold && full > 0 && open.list <= floor
      ? _share(avail, requests, full, floor, folded: true)
      : open;
  final room = settled.transcript > 0 ? open : settled;
  return AgentsRoom(
    transcript: room.transcript,
    list: room.list,
    limit: full == 0 ? rowLimit : room.list.clamp(1, rowLimit),
    requests: room.requests,
    folded: identical(room, settled) && canFold && room.list <= floor,
  );
}

typedef _Shared = ({int transcript, int list, List<int> requests});

/// One layout of the column: Yoga's shrinking of the items that may, by
/// their basis, never under their least, then rounding of their edges.
_Shared _share(
  int avail,
  List<RoomRequest> requests,
  int full,
  int floor, {
  required bool folded,
}) {
  // The requests in order, then the list, which is drawn under them.
  final basis = [for (final r in requests) r.natural, folded ? floor : full];
  final least = [for (final r in requests) math.min(r.fixed, r.natural), floor];
  final shrinks = [
    for (final r in requests)
      r.fixed < r.natural &&
          switch (r.gives) {
            RoomGives.never => false,
            RoomGives.withList => true,
            RoomGives.afterList => folded,
          },
    !folded && full > floor,
  ];
  final total = basis.fold(0, (sum, b) => sum + b);
  final over = total - avail;
  if (over <= 0) {
    return (
      transcript: -over,
      list: basis.last,
      requests: basis.sublist(0, requests.length),
    );
  }

  // Shrink the flexible items by their basis; one that would go under its
  // least is held there and the rest share what is left, as Yoga does.
  final heights = [for (final b in basis) b.toDouble()];
  final frozen = [for (final s in shrinks) !s];
  var left = over.toDouble();
  while (left > _epsilon) {
    final weight = [
      for (var i = 0; i < basis.length; i++) frozen[i] ? 0 : basis[i],
    ].fold(0, (sum, w) => sum + w);
    if (weight == 0) break;
    var clamped = false;
    for (var i = 0; i < basis.length; i++) {
      if (frozen[i]) continue;
      if (basis[i] - left * basis[i] / weight < least[i]) {
        left -= basis[i] - least[i];
        heights[i] = least[i].toDouble();
        frozen[i] = true;
        clamped = true;
      }
    }
    if (clamped) continue;
    for (var i = 0; i < basis.length; i++) {
      if (!frozen[i]) heights[i] = basis[i] - left * basis[i] / weight;
    }
    break;
  }

  // Edges rounded where they fall: what lies between the items is whole
  // rows, so each item's bottom is the running sum of their heights.
  final rounded = <int>[];
  var edge = 0.0;
  var top = 0;
  for (final h in heights) {
    edge += h;
    final bottom = _round(edge);
    rounded.add(bottom - top);
    top = bottom;
  }
  return (
    transcript: 0,
    list: rounded.last,
    requests: rounded.sublist(0, requests.length),
  );
}

const _epsilon = 0.0001;

/// Yoga's rounding to the cell grid: whole within a hair, else half up.
int _round(double value) {
  final down = value.floorToDouble();
  final part = value - down;
  if (part < _epsilon) return down.toInt();
  if (part > 1 - _epsilon) return down.toInt() + 1;
  return part >= 0.5 ? down.toInt() + 1 : down.toInt();
}
