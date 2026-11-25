import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/permission_prompt.dart';
import 'package:chord/ui/dialogs/permission_scroll.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/permission.dart';

void main() {
  group('tester: PermissionPrompt viewport and lifetime boundaries', () {
    test(
      'scroll configuration clamps silently and steps notify only on movement',
      () {
        final scroll = PermissionScroll();
        var notifications = 0;
        scroll.addListener(() => notifications++);
        try {
          scroll.configure(100, 6);
          scroll.step(ScrollStep.top);
          expect(notifications, 0);
          scroll.step(ScrollStep.bottom);
          expect(scroll.top, 95);
          expect(notifications, 1);
          scroll.step(ScrollStep.bottom);
          expect(notifications, 1);
          scroll.configure(2, 24);
          expect(scroll.top, 0);
          expect(notifications, 1);
          scroll.configure(0, 0);
          for (final step in ScrollStep.values) {
            scroll.step(step);
          }
          expect(scroll.top, 0);
          expect(notifications, 1);
        } finally {
          scroll.dispose();
        }
      },
    );

    for (final size in [const Size(80, 24), const Size(120, 40)]) {
      testWidgets(
        'scrolling and choices recover after zero/one-cell resize at $size',
        (t) async {
          final scroll = PermissionScroll();
          final picks = <String>[];
          final node = FocusNode();
          try {
            await t.pumpWidget(
              LayoutBuilder(
                builder: (context, constraints) => PermissionPrompt(
                  wait: PermissionWait(
                    'unicode',
                    title: 'Read 界👩‍💻e\u0301',
                    rawInput: [
                      for (var i = 0; i < 100; i++) 'row $i 界👩‍💻e\u0301',
                    ].join('\n'),
                    options: permissionFixture().options,
                  ),
                  windowRows: constraints.maxHeight,
                  maxRows: constraints.maxHeight,
                  scroll: scroll,
                  focusNode: node,
                  onChoose: picks.add,
                  onReject: () {},
                ),
              ),
              size: size,
            );
            for (var i = 0; i < 1000; i++) {
              scroll.step(ScrollStep.pageDown);
            }
            await t.pump();
            expect(t.screen, shows('row 99 界👩‍💻e\u0301'));
            expect(t.screen, shows('3. Deny'));
            await t.resize(const Size(0, 0));
            await t.resize(const Size(1, 1));
            await t.resize(size);
            scroll.step(ScrollStep.top);
            await t.pump();
            expect(t.screen, shows('Read 界👩‍💻e\u0301'));
            expect(t.screen, shows('row 0 界👩‍💻e\u0301'));
            await t.press('up enter');
            expect(picks, ['deny']);
            node.unfocus();
            await t.pump();
            expect(t.screen, isNot(shows('❯')));
            node.requestFocus();
            await t.pump();
            await t.press('down enter');
            expect(picks, ['deny', 'allow']);
            await t.pumpWidget(Text('removed'));
            scroll.step(ScrollStep.bottom);
            await t.pump();
            expect(t.screen.lines.first, 'removed');
          } finally {
            t.dispose();
            scroll.dispose();
            node.dispose();
          }
        },
      );
    }

    testWidgets('no agent options invent no answer but Escape still rejects', (
      t,
    ) async {
      final scroll = PermissionScroll();
      final picks = <String>[];
      var rejected = 0;
      try {
        await t.pumpWidget(
          PermissionPrompt(
            wait: const PermissionWait('empty', title: 'Tool call'),
            windowRows: 24,
            maxRows: 24,
            scroll: scroll,
            onChoose: picks.add,
            onReject: () => rejected++,
          ),
        );
        expect(t.screen, shows('No choices.'));
        await t.press('up down j k 1 enter');
        expect(picks, isEmpty);
        await t.press('esc');
        expect(rejected, 1);
      } finally {
        t.dispose();
        scroll.dispose();
      }
    });
  });
}
