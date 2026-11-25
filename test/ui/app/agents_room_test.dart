// How a short window shares its rows between the transcript, the agents
// list and a request's box (design CTUI-35 section 6, "The room"): the
// transcript first, then the list to its floor, then a permission's body;
// a plan's Note and a held box shrink with the list, as the original's
// Yoga column does, which a capture of the original at 80x24 shows
// (docs/design/evidence/CTUI-35/room/).
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/waits.dart';
import 'package:chord/ui/agents/agents.dart';
import 'package:chord/ui/app/agents_room.dart';
import 'package:chord/ui/dialogs/plan_box.dart';
import 'package:test/test.dart';
import 'package:chord_tui/chord_tui.dart' show unbounded;

const _now = 100000;

AgentRow _row(String name, int key) => AgentRow(
  key: key,
  name: name,
  runtime: 'fake',
  model: 'Fake Large with a 1M context window',
  wait: idle,
);

/// `main` and [children] children, as the list draws them.
List<AgentRow> _agents(int children) => [
  _row('main', 1),
  for (var i = 0; i < children; i++) _row('child$i', i + 2),
];

/// The list's lines in a limit at [width], as the window counts them.
int Function(int) _linesOf(List<AgentRow> rows, {int width = 76}) =>
    (limit) => agentsLines(
      rows,
      limit: limit,
      width: width,
      focused: false,
      now: _now,
    );

/// The status line, the working line and the prompt box with one row.
const _fixed = 1 + 2 + 4;

void main() {
  _testerRoomBudgets();
  final three = _linesOf(_agents(3));

  group('with room', () {
    for (final rows in [40, 24]) {
      test('the list is whole and the transcript takes the rest at $rows', () {
        final room = agentsRoom(rows: rows, fixed: _fixed, linesAt: three);
        final full = agentsRowLimit(rows);
        expect(room.list, 4);
        expect(room.limit, 4, reason: "the lines it draws, under $full");
        expect(room.transcript, rows - _fixed - 4);
        expect(room.folded, isFalse);
      });
    }

    test('a permission and the list both whole leave the transcript the '
        'rest', () {
      final room = agentsRoom(
        rows: 40,
        fixed: _fixed,
        linesAt: three,
        requests: const [
          RoomRequest(fixed: 10, natural: 20, gives: RoomGives.afterList),
        ],
      );
      expect(room.requests, [20]);
      expect(room.list, 4);
      expect(room.transcript, 40 - _fixed - 20 - 4);
    });
  });

  group('short of room', () {
    test('the transcript gives all before the list gives a line', () {
      // 24 - 7 = 17: 13 for the request, 4 for the list.
      final room = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: three,
        requests: const [
          RoomRequest(fixed: 10, natural: 13, gives: RoomGives.afterList),
        ],
      );
      expect(room.transcript, 0);
      expect(room.list, 4);
      expect(room.requests, [13]);
    });

    test('the list shrinks alone while the transcript is 0', () {
      final room = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: three,
        requests: const [
          RoomRequest(fixed: 10, natural: 14, gives: RoomGives.afterList),
        ],
      );
      expect(room.transcript, 0);
      expect(room.list, 3);
      expect(room.limit, 3);
      expect(three(room.limit), 3, reason: 'two agents and `… +2 more`');
      expect(room.requests, [14]);
      expect(room.folded, isFalse);
    });

    test('the list reaches its floor before a permission gives a row', () {
      final room = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: three,
        requests: const [
          RoomRequest(fixed: 10, natural: 15, gives: RoomGives.afterList),
        ],
      );
      expect(room.list, 2);
      expect(room.limit, 2);
      expect(three(room.limit), 2, reason: 'one agent and `… +3 more`');
      expect(room.requests, [15]);
      expect(room.folded, isTrue);
    });

    test("a permission's body shrinks only past the floor, to its least", () {
      RoomRequest permission(int natural) =>
          RoomRequest(fixed: 10, natural: natural, gives: RoomGives.afterList);
      final past = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: three,
        requests: [permission(18)],
      );
      expect(past.list, 2);
      expect(past.requests, [15]);
      expect(past.transcript, 0);
      final least = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: three,
        requests: [permission(30)],
      );
      expect(least.list, 2);
      expect(least.requests, [15]);
      final saturated = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: three,
        requests: [
          const RoomRequest(fixed: 16, natural: 30, gives: RoomGives.afterList),
        ],
      );
      expect(saturated.requests, [16]);
      expect(saturated.list, 2);
    });

    test('a form, question or link with the keys never shrinks', () {
      final room = agentsRoom(
        rows: 24,
        fixed: 1 + 2,
        linesAt: three,
        requests: const [RoomRequest(fixed: 19, natural: 19)],
      );
      expect(room.requests, [19]);
      expect(room.list, 2);
      expect(room.transcript, 0);
    });

    test('a held one shrinks with the list, each by its natural height', () {
      // 17 rows for 18 + 4: 5 over, 18/22 of it the box's.
      final room = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: three,
        requests: const [
          RoomRequest(fixed: 6, natural: 18, gives: RoomGives.withList),
        ],
      );
      expect(room.requests, [14]);
      expect(room.list, 3);
      // Held to its least, it shows `… N more lines` alone.
      final least = agentsRoom(
        rows: 12,
        fixed: _fixed,
        linesAt: three,
        requests: const [
          RoomRequest(fixed: 6, natural: 18, gives: RoomGives.withList),
        ],
      );
      expect(least.requests, [6]);
      expect(least.list, 2);
    });
  });

  group('the plan box and the list share as the original does', () {
    final wait = PlanWait('p', PlanAgent.cursor, toolCallId: 'c');
    // The Note picked, as in the captures: the hint wraps to two rows.
    const onNote = (row: 2, note: 'word');
    // Note lines → (Note rows, list lines), from the captures' NOTE.md.
    const captured = {
      2: (note: 2, list: 4),
      3: (note: 2, list: 4),
      5: (note: 3, list: 3),
      6: (note: 3, list: 3),
      7: (note: 3, list: 3),
      10: (note: 3, list: 3),
    };
    for (final MapEntry(key: lines, value: drawn) in captured.entries) {
      test('a Note of $lines lines at 80x24', () {
        final pinned = planPinned(wait, 'fake', onNote, 80);
        expect(pinned, 11, reason: 'the hint wraps to two rows');
        final natural = planNatural(
          wait,
          'fake',
          80,
          windowRows: 24,
          shape: (state: onNote, noteLines: lines),
        );
        final room = agentsRoom(
          rows: 24,
          fixed: _fixed,
          linesAt: three,
          requests: [
            RoomRequest(
              fixed: natural.fixed,
              natural: natural.natural,
              gives: RoomGives.withList,
            ),
          ],
        );
        expect(room.requests.single - pinned, drawn.note);
        expect(room.list, drawn.list);
        expect(three(room.limit), drawn.list);
        expect(room.transcript, 0);
      });
    }

    test('the plan as asked, its Note empty, leaves the transcript two '
        'rows', () {
      final natural = planNatural(wait, 'fake', 80, windowRows: 24);
      final room = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: three,
        requests: [
          RoomRequest(
            fixed: natural.fixed,
            natural: natural.natural,
            gives: RoomGives.withList,
          ),
        ],
      );
      expect(room.requests, [11]);
      expect(room.list, 4);
      expect(room.transcript, 2);
    });
  });

  group('edges', () {
    test('no rows: everything at its least, the list at its floor', () {
      final room = agentsRoom(
        rows: 0,
        fixed: _fixed,
        linesAt: three,
        requests: const [
          RoomRequest(fixed: 10, natural: 20, gives: RoomGives.afterList),
        ],
      );
      expect(room.transcript, 0);
      expect(room.list, 2);
      expect(room.requests, [10]);
    });

    test('one row: as clipped as none', () {
      final room = agentsRoom(rows: 1, fixed: 1, linesAt: three);
      expect(room.transcript, 0);
      expect(room.list, 2);
      expect(room.limit, 2);
    });

    test('saturated, the column is taller than the window', () {
      final room = agentsRoom(
        rows: 24,
        fixed: 20,
        linesAt: three,
        requests: const [
          RoomRequest(fixed: 8, natural: 12, gives: RoomGives.withList),
          RoomRequest(fixed: 6, natural: 6),
        ],
      );
      expect(room.transcript, 0);
      expect(room.list, 2);
      expect(room.requests, [8, 6]);
    });

    test('wrapped rows are counted as lines', () {
      // At 20 columns each row wraps to two lines: in a limit of 4, the
      // list draws one row and `… +3 more`, three lines.
      final narrow = _linesOf(_agents(3), width: 20);
      expect(narrow(agentsRowLimit(24)), 3);
      expect(narrow(1), 2);
      final room = agentsRoom(rows: 24, fixed: _fixed, linesAt: narrow);
      expect(room.list, 3);
      expect(room.transcript, 24 - _fixed - 3);
      final short = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: narrow,
        requests: const [
          RoomRequest(fixed: 10, natural: 15, gives: RoomGives.afterList),
        ],
      );
      expect(short.list, 2);
      expect(short.requests, [15]);
      expect(narrow(short.limit), 2, reason: 'a row cut to a line and more');
    });

    test('one child: two rows, whole or at a floor of two', () {
      final one = _linesOf(_agents(1));
      expect(one(agentsRowLimit(24)), 2);
      expect(one(1), 2);
      final room = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: one,
        requests: const [
          RoomRequest(fixed: 10, natural: 20, gives: RoomGives.afterList),
        ],
      );
      expect(room.list, 2);
      expect(room.requests, [15], reason: 'no list to fold: it gives way');
    });

    test('no child: no list, the requests have its rows', () {
      final room = agentsRoom(
        rows: 24,
        fixed: _fixed,
        linesAt: _linesOf(const []),
        requests: const [
          RoomRequest(fixed: 10, natural: 20, gives: RoomGives.afterList),
        ],
      );
      expect(room.list, 0);
      expect(room.requests, [17]);
      expect(room.limit, agentsRowLimit(24));
    });

    test('an unbounded height is refused', () {
      expect(
        () => agentsRoom(rows: 1 << 30, fixed: 0, linesAt: three),
        throwsArgumentError,
      );
    });
  });
}

void _testerRoomBudgets() {
  group('CTUI-35 tester: mixed request budgets', () {
    test(
      'every finite room spends its budget or only its unclippable minimum',
      () {
        const requests = [
          RoomRequest(fixed: 3, natural: 11, gives: RoomGives.withList),
          RoomRequest(fixed: 5, natural: 16, gives: RoomGives.afterList),
          RoomRequest(fixed: 2, natural: 7),
        ];
        for (final width in [1, 20, 76, 116]) {
          final lines = _linesOf(_agents(3), width: width);
          for (var rows = 0; rows <= 64; rows++) {
            for (final fixed in [0, 1, 7, 20]) {
              final full = lines(agentsRowLimit(rows));
              final floor = lines(1).clamp(0, full);
              final room = agentsRoom(
                rows: rows,
                fixed: fixed,
                linesAt: lines,
                requests: requests,
              );
              final reason = 'width=$width rows=$rows fixed=$fixed: $room';
              expect(room.list, inInclusiveRange(floor, full), reason: reason);
              expect(room.transcript, greaterThanOrEqualTo(0), reason: reason);
              for (var i = 0; i < requests.length; i++) {
                expect(
                  room.requests[i],
                  inInclusiveRange(requests[i].fixed, requests[i].natural),
                  reason: reason,
                );
              }
              expect(room.requests[2], 7, reason: reason);
              final available = (rows - fixed).clamp(0, rows);
              final minimum = floor + 3 + 5 + 7;
              final used =
                  room.transcript +
                  room.list +
                  room.requests.fold<int>(0, (sum, n) => sum + n);
              expect(
                used,
                available < minimum ? minimum : available,
                reason: reason,
              );
            }
          }
        }
      },
    );

    test(
      'negative and unbounded rooms refuse; the largest finite room fits',
      () {
        for (final rows in [-1, unbounded, unbounded + 1]) {
          expect(
            () => agentsRoom(rows: rows, fixed: 7, linesAt: (limit) => 4),
            throwsArgumentError,
          );
        }
        final room = agentsRoom(
          rows: unbounded - 1,
          fixed: 7,
          linesAt: (limit) => limit == 1 ? 2 : 4,
        );
        expect(room.transcript, unbounded - 12);
        expect(room.list, 4);
      },
    );
  });
}
