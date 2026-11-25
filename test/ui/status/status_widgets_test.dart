import 'dart:async';

import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/status/status.dart';
import 'package:chord/ui/status/status_line.dart';
import 'package:chord/ui/status/working.dart';
import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:clock/clock.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final (name, base, palette) in [
      ('dark', ThemeData.dark(), chordDark),
      ('light', ThemeData.light(), chordLight),
    ]) {
      testWidgets('$name working and status use original styles at $size', (
        t,
      ) async {
        await withClock(
          Clock.fixed(DateTime.fromMillisecondsSinceEpoch(12000)),
          () async {
            await t.pumpWidget(
              Theme(
                data: base,
                child: ChordThemeScope(
                  child: Column(
                    children: [
                      const Working(turn: model.Working('turn', 0)),
                      const StatusLine(
                        facts: StatusFacts(
                          model: 'Fake',
                          effort: 'high',
                          mode: 'plan',
                          usage: model.Usage(1, 100),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              size: size,
            );
            expect(t.screen.lines[1], ' ››› Working… (12s · esc to interrupt)');
            expect(t.screen.lines[2], startsWith('⏸ plan mode on'));
            expect(
              t.screen.lines[2],
              endsWith('Fake · high effort · 1% context used'),
            );
            expect(t.screen.styleAt(0, 2).fg, palette.plan.fg);
            expect(
              t.screen.styleAt(1, 1).fg,
              markColor(palette.mark.stops![0]),
            );
            expect(
              t.screen.styleAt(2, 1).fg,
              markColor(palette.mark.stops![2]),
            );
            expect(t.screen.styleAt(5, 1).fg, base.accent.fg);
          },
        );
      });
    }
    testWidgets(
      'unwrapped plain status and spinner have no explicit colors at $size',
      (t) async {
        await t.pumpWidget(
          Theme(
            data: ThemeData.plain(),
            child: Column(
              children: [
                const Working(turn: model.Working('turn', 0)),
                const StatusLine(
                  facts: StatusFacts(mode: 'plan', usage: model.Usage(81, 100)),
                ),
              ],
            ),
          ),
          size: size,
        );
        for (var y = 0; y < 3; y++) {
          for (var x = 0; x < size.width; x++) {
            expect(t.screen.styleAt(x, y).fg, isNull);
            expect(t.screen.styleAt(x, y).bg, isNull);
          }
        }
        expect(t.screen.styleAt(1, 1).isDim, isFalse);
        expect(t.screen.styleAt(2, 1).isDim, isTrue);
      },
    );
  }
  testWidgets('a mounted palette change follows resolved base brightness', (
    t,
  ) async {
    final theme = ValueNotifier(ThemeData.dark());
    await t.pumpWidget(
      ListenableBuilder(
        listenable: theme,
        builder: (_) => Theme(
          data: theme.value,
          child: const ChordThemeScope(
            child: StatusLine(facts: StatusFacts(mode: 'acceptEdits')),
          ),
        ),
      ),
    );
    expect(t.screen.styleAt(0, 0).fg, chordDark.edits.fg);
    theme.value = ThemeData.light();
    await t.pump();
    expect(t.screen.styleAt(0, 0).fg, chordLight.edits.fg);
    t.dispose();
    theme.dispose();
  });
  test(
    'app palettes preserve every original missing role and spinner stop',
    () {
      expect(chordDark.plan.fg, RgbColor.hex('#48968c'));
      expect(chordDark.edits.fg, RgbColor.hex('#af87ff'));
      expect(chordDark.auto.fg, RgbColor.hex('#ffd700'));
      expect(chordDark.bash.fg, RgbColor.hex('#fd5db1'));
      expect(chordLight.plan.fg, RgbColor.hex('#006b66'));
      expect(chordLight.edits.fg, RgbColor.hex('#7a3fd6'));
      expect(chordLight.auto.fg, RgbColor.hex('#8a6100'));
      expect(chordLight.bash.fg, RgbColor.hex('#d1006f'));
      expect(chordDark.mark.stops, ['#d2ffe4', '#3fdc9c', '#0a7470']);
      expect(chordLight.mark.stops, ['#1e9a5e', '#147d55', '#0a5e57']);
      expect(markColor(chordDark.mark.tone), Colors.brightGreen);
      expect(markColor(chordLight.mark.tone), Colors.green);
      expect(chordPlain.mark.stops, isNull);
      expect(chordPlain.mark.tone, isNull);
    },
  );
  test('working timers advance separately and stop on idle and dispose', () {
    fakeAsync((async) {
      final since = clock.now().millisecondsSinceEpoch;
      final turn = ValueNotifier<model.TurnState>(model.Working('turn', since));
      final host = AppHost(
        ListenableBuilder(
          listenable: turn,
          builder: (_) => Column(children: [Working(turn: turn.value)]),
        ),
      );
      var screen = Screen(host.drawFrame(const Size(80, 24)));
      expect(screen, shows('Working… (0s · esc to interrupt)'));
      expect(async.periodicTimerCount, 2);
      async.elapse(const Duration(seconds: 1));
      screen = Screen(host.drawFrame(const Size(80, 24)));
      expect(screen, shows('Working… (1s · esc to interrupt)'));
      for (var x = 1; x <= 3; x++) {
        expect(screen.styleAt(x, 1).isDim, isTrue);
      }
      turn.value = const model.Cancelling('turn', 0, 0);
      host.drawFrame(const Size(80, 24));
      turn.value = const model.Idle();
      screen = Screen(host.drawFrame(const Size(80, 24)));
      expect(screen.text, isEmpty);
      expect(async.periodicTimerCount, 0);
      turn.value = model.Working('again', since);
      host.drawFrame(const Size(80, 24));
      expect(async.periodicTimerCount, 2);
      host.dispose();
      turn.dispose();
      expect(async.periodicTimerCount, 0);
    });
  });
  test(
    'NO_COLOR overrides an explicit light selection through runApp',
    () async {
      final term = _MemoryTerminal();
      ChordTheme? palette;
      final running = runApp(
        ChordThemeScope(
          child: Builder(
            builder: (context) {
              palette = chordThemeOf(context);
              context.owner.afterLayout(() => exitApp(context));
              return const Column(
                children: [
                  Working(turn: model.Working('t', 0)),
                  StatusLine(facts: StatusFacts(mode: 'auto')),
                ],
              );
            },
          ),
        ),
        terminal: term,
        exitProcess: false,
        theme: ThemeData.light(),
        environment: {'NO_COLOR': '1'},
      );
      await running.timeout(const Duration(seconds: 2));
      expect(identical(palette, chordPlain), isTrue);
      expect(term.output.toString(), isNot(contains('38;')));
      expect(term.output.toString(), isNot(contains('48;')));
      await term.events.close();
    },
  );
  group('tester U11 status geometry and timer lifetime', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets(
        'right facts stay aligned through narrow and zero resize at $size',
        (t) async {
          await t.pumpWidget(
            const StatusLine(
              facts: StatusFacts(
                model: '界🙂e\u0301 model with a very long descriptive name',
                effort: 'high',
                mode: 'plan',
                usage: model.Usage(81, 100),
              ),
            ),
            size: size,
          );
          expect(t.screen.lines.first, startsWith('⏸ plan mode on'));
          expect(
            t.screen.lines.first,
            endsWith(size.width == 120 ? '81% context used' : '81% used'),
          );
          expect(t.screen.charAt(size.width - 1, 0), 'd');
          expect(t.screen.lines.skip(1).every((line) => line.isEmpty), isTrue);
          await t.resize(const Size(20, 4));
          expect(t.screen.lines.first, '⏸ plan mode on');
          await t.resize(const Size(1, 1));
          expect(t.screen.text, '');
          await t.resize(const Size(0, 0));
          await t.resize(size);
          expect(t.screen.charAt(size.width - 1, 0), 'd');
        },
      );

      testWidgets(
        'unwrapped modes use plain fallback even below colored base at $size',
        (t) async {
          await t.pumpWidget(
            Theme(
              data: ThemeData.dark(),
              child: const StatusLine(facts: StatusFacts(mode: 'auto')),
            ),
            size: size,
          );
          expect(t.screen, shows('⏵⏵ auto mode on'));
          expect(t.screen.styleAt(0, 0).fg, isNull);
          expect(t.screen.styleAt(0, 0).bg, isNull);
          expect(t.screen.styleAt(0, 0).isDim, isFalse);
        },
      );
    }

    test(
      'tester drives exact spinner and elapsed timer boundaries and cancels both',
      () {
        fakeAsync((async) {
          final t = WidgetTester();
          final now = clock.now().millisecondsSinceEpoch;
          final turn = ValueNotifier<model.TurnState>(
            model.Working('t', now - 900),
          );
          void draw(Future<void> future) {
            var done = false;
            future.then((_) => done = true);
            async.elapse(Duration.zero);
            async.flushMicrotasks();
            expect(done, isTrue);
          }

          draw(
            t.pumpWidget(
              ListenableBuilder(
                listenable: turn,
                builder: (_) => Column(children: [Working(turn: turn.value)]),
              ),
            ),
          );
          expect(async.periodicTimerCount, 2);
          expect(t.screen.styleAt(1, 1).isDim, isFalse);
          async.elapse(const Duration(milliseconds: 139));
          draw(t.pump());
          expect(t.screen.styleAt(1, 1).isDim, isFalse);
          expect(t.screen, shows('(0s · esc to interrupt)'));
          async.elapse(const Duration(milliseconds: 1));
          draw(t.pump());
          expect(t.screen.styleAt(1, 1).isDim, isTrue);
          expect(t.screen.styleAt(2, 1).isDim, isFalse);
          expect(t.screen, shows('(0s · esc to interrupt)'));
          async.elapse(const Duration(milliseconds: 110));
          draw(t.pump());
          expect(t.screen, shows('(1s · esc to interrupt)'));
          for (var i = 0; i < 1000; i++) {
            turn.value = model.Working('t', now - 900);
          }
          draw(t.pump());
          expect(async.periodicTimerCount, 2);
          turn.value = const model.Idle();
          draw(t.pump());
          expect(async.periodicTimerCount, 0);
          turn.value = model.Working('again', now);
          draw(t.pump());
          expect(async.periodicTimerCount, 2);
          draw(t.pumpWidget(Text('removed')));
          expect(async.periodicTimerCount, 0);
          async.elapse(const Duration(seconds: 10));
          draw(t.pump());
          expect(t.screen, shows('removed'));
          t.dispose();
          turn.dispose();
        });
      },
    );
  });
}

class _MemoryTerminal extends Terminal {
  final events = StreamController<String>();
  final output = StringBuffer();
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => events.stream;
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
  @override
  void write(String data) {
    output.write(data);
    if (data == '\x1b]11;?\x07') events.add('\x1b]11;rgb:ffff/ffff/ffff\x07');
  }
}
