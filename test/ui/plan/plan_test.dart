import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/ui/plan/plan.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../../tool/plan.dart' as fixture;

List<acp.PlanEntry> steps() => [
  for (final (status, text) in [
    ('completed', 'Read the code'),
    ('in_progress', 'Write the change'),
    ('pending', 'Run the tests'),
  ])
    acp.PlanEntry.fromJson({
      'content': text,
      'priority': 'medium',
      'status': status,
    }),
];

void main() {
  group('tester CTUI-44: completed plan separator after resize', () {
    for (final record in [false, true]) {
      testWidgets(
        '${record ? 'record' : 'live'} keeps mark and space through narrow and wide frames',
        (t) async {
          final entries = [
            for (final content in [
              'Write the change',
              'Done',
              '界🙂e\u0301${'x' * 40}END',
            ])
              acp.PlanEntry.fromJson({
                'content': content,
                'status': 'completed',
                'priority': 'medium',
              }),
          ];
          await t.pumpWidget(
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 1),
              child: Column(
                children: [
                  if (record)
                    PlanRecord(entries)
                  else
                    Plan(plan: entries, limit: 4, running: true),
                ],
              ),
            ),
            size: const Size(120, 40),
          );
          for (final size in [
            const Size(20, 8),
            const Size(21, 8),
            const Size(80, 24),
            const Size(120, 40),
            const Size(20, 8),
          ]) {
            await t.resize(size);
            final row = t.screen.lines.indexWhere((line) => line.contains('⎿'));
            expect(row, greaterThanOrEqualTo(0));
            expect(t.screen.lines[row], startsWith('   ⎿  ☒ '));
            expect(t.screen.lines[row + 1], '      ☒ Done');
            expect(t.screen.lines[row + 2], startsWith('      ☒ '));
            expect(t.screen.styleAt(6, row).isStrikethrough, isFalse);
            expect(t.screen.styleAt(7, row).isStrikethrough, isFalse);
            expect(t.screen.styleAt(8, row).isStrikethrough, isTrue);
            if (size.width == 20) {
              expect(t.screen.lines[row], '   ⎿  ☒ Writ...ange');
            }
            if (size.width >= 80) {
              expect(t.screen.lines[row], '   ⎿  ☒ Write the change');
              expect(t.screen.lines[row + 2], contains('界🙂e\u0301'));
            }
          }
        },
      );
    }
  });

  for (final record in [false, true]) {
    testWidgets(
      'completed ${record ? 'record' : 'live'} plan keeps its separator at 20 columns',
      (t) async {
        final entries = [
          for (final content in ['Write the change', 'Done'])
            acp.PlanEntry.fromJson({
              'content': content,
              'status': 'completed',
              'priority': 'medium',
            }),
        ];
        await t.pumpWidget(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 1),
            child: Column(
              children: [
                if (record)
                  PlanRecord(entries)
                else
                  Plan(plan: entries, limit: 3, running: true),
              ],
            ),
          ),
          size: const Size(20, 8),
        );
        expect(t.screen.lines, contains('   ⎿  ☒ Writ...ange'));
        expect(t.screen.lines, contains('      ☒ Done'));
      },
    );
  }

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'live plan hangs under working and bolds only current step at $size',
      (t) async {
        await t.pumpWidget(
          Column(
            children: [
              Text(' ››› Working…'),
              Plan(plan: steps(), limit: 3, running: true),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines.take(4), [
          ' ››› Working…',
          '  ⎿  ☒ Read the code',
          '     ◐ Write the change',
          '     ☐ Run the tests',
        ]);
        expect(t.screen.styleAt(7, 1).isStrikethrough, isTrue);
        expect(t.screen.styleAt(5, 1).isStrikethrough, isFalse);
        expect(t.screen.styleAt(7, 2).isBold, isTrue);
        expect(t.screen.styleAt(7, 3).isBold, isFalse);
        expect(t.screen, isNot(shows('Plan ·')));
      },
    );
    testWidgets('unknown live status leaves only the outer gutter at $size', (
      t,
    ) async {
      await t.pumpWidget(
        Column(
          children: [
            Plan(
              plan: [
                acp.PlanEntry.fromJson({
                  'content': 'Do not invent a pending step',
                  'status': 'paused',
                  'priority': 'medium',
                }),
                ...steps(),
              ],
              limit: 4,
              running: true,
            ),
          ],
        ),
        size: size,
      );
      expect(t.screen.lines.first, '  ⎿');
      expect(t.screen, isNot(shows('Do not invent')));
      expect(t.screen.lines[1], '     ☒ Read the code');
    });
    testWidgets('idle plan has a summary and folds long plans at $size', (
      t,
    ) async {
      await t.pumpWidget(
        Column(
          children: [
            Plan(plan: [...steps(), ...steps()], limit: 3, running: false),
          ],
        ),
        size: size,
      );
      expect(t.screen.lines.take(5), [
        '',
        '  Plan · 2 of 6 done',
        '  ⎿  ☒ Read the code',
        '     ◐ Write the change',
        '     … +4 more',
      ]);
      expect(t.screen.styleAt(7, 3).isBold, isFalse);
    });
  }
  group('tester U9 live plan presentation', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'actual plan fixture toggles without replacing a live controller at $size',
        (t) async {
          await t.pumpWidget(const fixture.PlanFixture(), size: size);
          expect(t.screen, shows('Working…'));
          await t.type('unsent draft');
          await t.press('ctrl+t');
          expect(t.screen, shows('Plan · 1 of 3 done'));
          expect(t.screen, shows('│ › unsent draft'));
          await t.press('ctrl+t');
          expect(t.screen, shows('Working…'));
          expect(t.screen, shows('│ › unsent draft'));
        },
      );
    }

    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'same mounted plan changes running styles without stale rows at $size',
        (t) async {
          final running = ValueNotifier(true);
          addTearDown(running.dispose);
          await t.pumpWidget(
            ListenableBuilder(
              listenable: running,
              builder: (_) => Column(
                children: [
                  Plan(plan: steps(), limit: 3, running: running.value),
                ],
              ),
            ),
            size: size,
          );
          expect(t.screen.styleAt(7, 1).isBold, isTrue);
          expect(t.screen.styleAt(5, 0).isStrikethrough, isFalse);
          expect(t.screen.styleAt(7, 0).isStrikethrough, isTrue);
          running.value = false;
          await t.pump();
          expect(t.screen.lines.first, '');
          expect(t.screen.lines[1], '  Plan · 1 of 3 done');
          expect(t.screen.styleAt(7, 3).isBold, isFalse);
          expect(t.screen.styleAt(5, 2).isStrikethrough, isFalse);
          expect(t.screen.styleAt(7, 2).isStrikethrough, isTrue);
          running.value = true;
          await t.pump();
          expect(t.screen, isNot(shows('Plan ·')));
          expect(t.screen.styleAt(7, 1).isBold, isTrue);
        },
      );

      testWidgets(
        'long Unicode steps cut in the middle and fold completed prefixes at $size',
        (t) async {
          final entries = [
            for (var i = 0; i < 7; i++)
              acp.PlanEntry.fromJson({
                'content': i == 5 ? '界🙂e\u0301${'x' * 200}END' : 'Step $i',
                'priority': 'medium',
                'status': i < 5
                    ? 'completed'
                    : i == 5
                    ? 'in_progress'
                    : 'pending',
              }),
          ];
          await t.pumpWidget(
            Column(children: [Plan(plan: entries, limit: 3, running: true)]),
            size: size,
          );
          expect(t.screen.lines[0], '  ⎿  … 5 done');
          expect(t.screen.lines[1], startsWith('     ◐ 界🙂e\u0301'));
          expect(t.screen.lines[1], contains('...'));
          expect(t.screen.lines[1], endsWith('END'));
          expect(t.screen.lines[2], '     ☐ Step 6');
          await t.resize(const Size(20, 8));
          expect(t.screen.lines[1], endsWith('END'));
          expect(t.screen.lines[2], '     ☐ Step 6');
        },
      );
    }
  });
}
