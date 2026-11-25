import 'dart:async';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permission_review.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/transcript/tools/paths.dart';
import 'package:chord/ui/transcript/tools/tool.dart';
import 'package:chord/ui/transcript/tools/tools.dart';
import 'package:chord_tui/chord_tui.dart' hide Folded;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

acp.ToolCallContent _text(String value) => acp.ToolCallContent.fromJson({
  'type': 'content',
  'content': {'type': 'text', 'text': value},
});
acp.ToolCallContent _diff(String path, {int lines = 1}) =>
    acp.ToolCallContent.fromJson({
      'type': 'diff',
      'path': path,
      'oldText': '',
      'newText': List.generate(lines, (i) => 'added $i').join('\n'),
    });

void main() {
  group('tester U5 tool lifecycle and composition', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('review marker ordering across mixed outputs at $size', (
        t,
      ) async {
        for (final withText in [false, true]) {
          final call = model.ToolCall(
            'a',
            title: 'Run',
            status: 'completed',
            review: const PermissionReview('caution', 'check'),
            content: [if (withText) _text('summary'), _diff('a.ts')],
            terminals: const [model.Terminal('t', output: 'terminal')],
          );
          await t.pumpWidget(Tool(call, expanded: false), size: size);
          final rows = t.screen.lines;
          expect(rows[2], '  ⎿  Reviewed: caution');
          expect(
            rows.where((row) => row.contains('⎿')),
            hasLength(withText ? 1 : 2),
          );
          final terminal = rows.indexWhere((row) => row.contains('terminal'));
          final diff = rows.indexWhere((row) => row.contains('Updated a.ts'));
          expect(terminal, greaterThan(2));
          expect(diff, greaterThan(terminal));
          expect(rows[diff], startsWith('     Updated'));
        }
      });

      testWidgets('expansion keeps a large normal edit whole at $size', (
        t,
      ) async {
        final expanded = ValueNotifier(false);
        final call = model.ToolCall(
          'a',
          title: 'Edit a.ts',
          status: 'completed',
          content: [_diff('a.ts', lines: 15)],
        );
        await t.pumpWidget(
          ListenableBuilder(
            listenable: expanded,
            builder: (_) => Tool(call, expanded: expanded.value),
          ),
          size: size,
        );
        final before = t.screen.buffer.lines;
        expect(t.screen, shows('added 14'));
        expect(t.screen.text, isNot(contains('to expand')));
        expanded.value = true;
        await t.pump();
        expect(t.screen.buffer.lines, before);
        t.dispose();
        expanded.dispose();
      });

      testWidgets('tiny widths clip furniture and Unicode output at $size', (
        t,
      ) async {
        final call = model.ToolCall(
          'a',
          title: 'Read 界👩‍💻e\u0301',
          status: 'completed',
          content: [_text('界👩‍💻e\u0301')],
        );
        for (final width in [0, 1, 2, 5, 8]) {
          await t.pumpWidget(
            Row(
              children: [
                SizedBox(width: width, child: Tool(call, expanded: false)),
                Text('|'),
              ],
            ),
            size: size,
          );
          expect(t.screen.charAt(width, 0), '|');
          for (var y = 1; y < size.height; y++) {
            expect(t.screen.charAt(width, y), ' ');
            expect(t.screen.styleAt(width, y).bg, isNull);
          }
        }
      });

      testWidgets('Guardian presentation ignores title and output at $size', (
        t,
      ) async {
        final call = model.ToolCall(
          'a',
          title: 'Do not draw',
          guardian: 'approved',
          status: 'failed',
          content: [_text('secret output')],
        );
        await t.pumpWidget(Tool(call, expanded: true), size: size);
        expect(t.screen.text, isEmpty);
        await t.pumpWidget(
          const Tool(
            model.ToolCall('a', guardian: 'inProgress', title: 'Do not draw'),
            expanded: true,
          ),
          size: size,
        );
        expect(t.screen.lines.take(3), ['', '  Guardian reviewing…', '']);
      });
    }

    testWidgets('marker timers cancel on every tone transition and removal', (
      t,
    ) async {
      final timers = <Timer>[];
      final tone = ValueNotifier(Tone.running);
      await runZoned(
        () async {
          await t.pumpWidget(
            ListenableBuilder(
              listenable: tone,
              builder: (_) => ToolMarker(tone.value),
            ),
          );
          expect(timers.where((timer) => timer.isActive), hasLength(1));
          for (final next in [
            Tone.pending,
            Tone.running,
            Tone.failed,
            Tone.running,
            Tone.done,
            Tone.running,
          ]) {
            tone.value = next;
            await t.pump();
            expect(
              timers.where((timer) => timer.isActive),
              hasLength(next == Tone.running ? 1 : 0),
            );
          }
          await t.pumpWidget(Text('removed'));
          expect(timers.where((timer) => timer.isActive), isEmpty);
        },
        zoneSpecification: ZoneSpecification(
          createPeriodicTimer: (self, parent, zone, duration, callback) {
            final timer = parent.createPeriodicTimer(zone, duration, callback);
            timers.add(timer);
            return timer;
          },
        ),
      );
      tone.dispose();
    });

    testWidgets('path shortening and resize retain complete edit content', (
      t,
    ) async {
      final call = model.ToolCall(
        'a',
        title: 'Edit file',
        status: 'completed',
        content: [_diff('/fixture/project/${'long_directory/' * 7}界.ts')],
      );
      final paths = pathView('/fixture/project', '/fixture', real: (p) => p);
      await t.pumpWidget(
        Tool(call, expanded: false, paths: paths),
        size: const Size(120, 40),
      );
      expect(t.screen.text, isNot(contains('/fixture')));
      expect(t.screen, shows('added 0'));
      final wide = t.screen.buffer.lines;
      await t.resize(const Size(80, 24));
      // The original diff headline is plain OpenTUI text: paths break at '/'.
      expect(t.screen.lines.skip(2).take(3).map((row) => row.trimLeft()), [
        '⎿  Updated ${'long_directory/' * 4}',
        '${'long_directory/' * 3}界.ts with 1 addition and 0',
        'removals',
      ]);
      expect(t.screen, shows('added 0'));
      await t.resize(const Size(120, 40));
      expect(t.screen.buffer.lines, wide);
    });

    testWidgets('a thousand updates then end of turn removes running text', (
      t,
    ) async {
      final step = ValueNotifier(0);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: step,
          builder: (_) => Tool(
            model.ToolCall(
              'a',
              title: 'Run',
              status: 'in_progress',
              content: step.value == 1001
                  ? []
                  : [_text('update ${step.value}')],
            ),
            expanded: false,
            ended: step.value == 1001,
          ),
        ),
      );
      for (var i = 1; i <= 1000; i++) {
        step.value = i;
      }
      await t.pump();
      expect(t.screen, shows('update 1000'));
      step.value = 1001;
      await t.pump();
      expect(t.screen.lines.take(3), ['', '⏺ Run', '']);
      expect(t.screen.styleAt(0, 1).isDim, isTrue);
      await t.pumpWidget(Text('removed'));
      step.value = 1002;
      await t.pump();
      expect(t.screen.text, 'removed');
      step.dispose();
    });
  });
}
