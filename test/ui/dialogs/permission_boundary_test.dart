import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/permission.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

void main() {
  group('tester: permission request boundaries', () {
    test('paging reaches every row for small totals and terminal rooms', () {
      for (var total = 0; total <= 64; total++) {
        for (var room = 1; room <= 40; room++) {
          for (final step in [ScrollStep.pageDown, ScrollStep.pageUp]) {
            var top = step == ScrollStep.pageDown
                ? 0
                : requestStep(ScrollStep.bottom, total, room, 0);
            final seen = <int>{};
            for (var attempt = 0; attempt <= total + 1; attempt++) {
              final view = requestView(total, room, top);
              expect(view.top, greaterThanOrEqualTo(0));
              expect(view.top + view.shown, lessThanOrEqualTo(total));
              expect(
                view.shown + (view.above ? 1 : 0) + (view.below ? 1 : 0),
                lessThanOrEqualTo(room),
              );
              seen.addAll(List.generate(view.shown, (i) => view.top + i));
              final next = requestStep(step, total, room, top);
              if (next == top) break;
              top = next;
            }
            expect(
              seen,
              hasLength(total),
              reason: '$total rows, $room room, $step',
            );
          }
        }
      }
    });

    test('resize clamps stale offsets and all scroll steps stay bounded', () {
      for (final total in [0, 1, 2, 3, 42, 1000]) {
        for (final room in [0, 1, 2, 3, 24, 40, 1200]) {
          for (final offset in [-100, 0, 1, 9999]) {
            for (final step in ScrollStep.values) {
              final top = requestStep(step, total, room, offset);
              expect(top, inInclusiveRange(0, total == 0 ? 0 : total - 1));
            }
          }
        }
        expect(requestView(total, double.infinity, 9999), (
          top: 0,
          shown: total,
          above: false,
          below: false,
        ));
      }
    });

    test(
      'Unicode clusters and empty lines survive title and input wrapping',
      () {
        // Expected rows from the original requestRows at the same width.
        final request = requestRows(
          const PermissionWait(
            'unicode',
            title: ' 界👩‍💻é\n\nend',
            rawInput: '  界👩‍💻é\n\nlast',
          ),
          8,
        );
        expect(request.pinned, ' 界👩‍💻é');
        expect(
          [
            for (final row in request.rows.cast<RequestText>())
              (row.kind, row.text),
          ],
          [
            ('title', ''),
            ('title', 'end'),
            ('input', '  界👩‍💻'),
            ('input', 'é'),
            ('input', ''),
            ('input', 'last'),
          ],
        );
        expect(requestHeight(request.rows, 8), 6);
      },
    );

    test('count reservation fits counts across decimal boundaries', () {
      for (final total in [1, 2, 9, 10, 49, 50, 99, 100, 499, 500, 999, 1000]) {
        final room = countRoom(total);
        for (var above = 0; above < total; above++) {
          expect(
            cellWidth(requestCount((above: above, below: total - above - 1))),
            lessThanOrEqualTo(room),
          );
        }
      }
    });
  });
}
