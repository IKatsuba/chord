import 'dart:async';

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('tester U4 entry boundaries', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('user graphemes wrap beyond a fixed gutter at $size', (
        t,
      ) async {
        for (final cluster in ['界', '👩‍💻', 'e\u0301']) {
          for (var edge = 0; edge <= 3; edge++) {
            final width = 2 + edge + graphemeWidth(cluster);
            await t.pumpWidget(
              Row(
                children: [
                  SizedBox(
                    width: width,
                    child: TranscriptEntry(
                      model.UserEntry('a', '${'x' * edge}${cluster}z'),
                    ),
                  ),
                  Text('|'),
                ],
              ),
              size: size,
            );
            expect(t.screen.charAt(2 + edge, 1), cluster);
            expect(t.screen.lines[2], '  z');
            expect(t.screen.charAt(width, 0), '|');
            for (var y = 1; y < 4; y++) {
              expect(t.screen.charAt(width, y), ' ');
              expect(t.screen.styleAt(width, y).bg, isNull);
            }
          }
        }
      });

      testWidgets('zero and one-cell room clip every U4 entry at $size', (
        t,
      ) async {
        final entries = <model.Entry>[
          const model.UserEntry('a', '界👩‍💻e\u0301'),
          model.AssistantEntry('a', TextRun.empty.plus('**reply**')),
          model.ThoughtEntry('a', TextRun.empty.plus('thinking')),
          const model.CancelledEntry('a'),
          const model.StoppedEntry('a', 'reason'),
          const model.ErrorEntry('a', 'error'),
          const model.WarningEntry('a', 'warning'),
          const model.PermissionEntry('a'),
          const model.FinishedPlanEntry('a', []),
        ];
        for (final width in [0, 1]) {
          for (final entry in entries) {
            await t.pumpWidget(
              Row(
                children: [
                  SizedBox(
                    width: width,
                    child: TranscriptEntry(entry, expanded: true),
                  ),
                  Text('|'),
                ],
              ),
              size: size,
            );
            expect(t.screen.charAt(width, 0), '|');
            for (var y = 1; y < size.height; y++) {
              expect(t.screen.charAt(width, y), ' ');
            }
          }
        }
      });

      testWidgets('outcomes wrap under their words and retain tone at $size', (
        t,
      ) async {
        await t.pumpWidget(
          Row(
            children: [
              SizedBox(
                width: 15,
                child: const TranscriptEntry(
                  model.StoppedEntry('a', 'one two three four'),
                ),
              ),
            ],
          ),
          size: size,
        );
        expect(t.screen.lines.take(4), [
          '  ⎿  Stopped:',
          '     one two',
          '     three four',
          '',
        ]);
        expect(t.screen.styleAt(5, 1).isDim, isTrue);
      });
    }

    testWidgets('entry resize settles growing markdown without losing text', (
      t,
    ) async {
      final entry = model.AssistantEntry(
        'a',
        TextRun.empty.plus('**opening** ${'word ' * 45}👩‍💻 e\u0301 final'),
      );
      final growing = ValueNotifier(true);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: growing,
          builder: (_) => TranscriptEntry(entry, growing: growing.value),
        ),
        size: const Size(120, 40),
      );
      expect(t.screen, shows('opening'));
      await t.resize(const Size(80, 24));
      expect(t.screen, shows('final'));
      growing.value = false;
      await t.pump();
      expect(t.screen, shows('final'));
      expect(t.screen.styleAt(2, 1).isBold, isTrue);
      await t.resize(const Size(0, 0));
      expect(t.screen.text, isEmpty);
      await t.resize(const Size(120, 40));
      expect(t.screen, shows('final'));
      t.dispose();
      growing.dispose();
    });

    testWidgets('thousand live updates and removal keep thought state local', (
      t,
    ) async {
      final text = ValueNotifier('start');
      final stream = StreamController<String>(sync: true);
      final sub = stream.stream.listen((value) => text.value = value);
      addTearDown(() async {
        await sub.cancel();
        await stream.close();
        text.dispose();
      });
      await t.pumpWidget(
        ListenableBuilder(
          listenable: text,
          builder: (_) => TranscriptEntry(
            model.ThoughtEntry('a', TextRun.empty.plus(text.value)),
            expanded: true,
          ),
        ),
      );
      for (var i = 0; i < 1000; i++) {
        stream.add('thought $i');
      }
      await t.pump();
      expect(t.screen, shows('thought 999'));
      await t.pumpWidget(Text('removed'));
      stream.add('late');
      await t.pump();
      expect(t.screen.text, 'removed');
    });

    testWidgets('entry focus and keys do not implement window actions', (
      t,
    ) async {
      final first = FocusNode();
      final second = FocusNode();
      await t.pumpWidget(
        Column(
          children: [
            Focus(
              focusNode: first,
              child: TranscriptEntry(
                model.ThoughtEntry('a', TextRun.empty.plus('hidden thought')),
              ),
            ),
            Focus(focusNode: second, child: Text('other')),
          ],
        ),
      );
      final before = t.screen.buffer.lines;
      for (final node in [first, second, first]) {
        node.requestFocus();
        for (final key in [
          'ctrl+o',
          'esc',
          'enter',
          'pageup',
          'pagedown',
          'home',
          'end',
          'shift+up',
          'shift+down',
        ]) {
          await t.press(key);
          expect(t.screen.buffer.lines, before);
        }
      }
      t.dispose();
      first.dispose();
      second.dispose();
    });
  });
}
