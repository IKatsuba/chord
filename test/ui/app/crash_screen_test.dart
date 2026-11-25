import 'dart:io';

import 'package:chord/ui/app/crash_screen.dart';
import 'package:chord/ui/app/renderer.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../fixtures/fake.dart';

void main() {
  final error = StateError('window failed');
  final stack = StackTrace.fromString('#0 Throws (fixture.dart:1:1)');
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'boundary retains native rows/theme and removes failed actions at $size',
      (t) async {
        var caught = 0;
        var failedAction = 0;
        await t.pumpWidget(
          Theme(
            data: ThemeData.light(),
            child: CrashBoundary(
              onCrash: (failure, trace) {
                expect(failure, same(error));
                expect(trace, same(stack));
                caught++;
              },
              child: Actions(
                bindings: [Binding('x', 'Failed action', () => failedAction++)],
                child: Builder(
                  builder: (_) => Error.throwWithStackTrace(error, stack),
                ),
              ),
            ),
          ),
          size: size,
        );
        expect(t.screen.lines.take(5), [
          '',
          '  Bad state: window failed',
          '  #0 Throws (fixture.dart:1:1)',
          '',
          '  any key to quit · chord prints the error to stderr as it exits',
        ]);
        expect(t.screen.styleAt(2, 1).fg, ThemeData.light().error.fg);
        expect(t.focusManager.activeBindings, isEmpty);
        expect(caught, 1);
        await t.resize(const Size(20, 4));
        expect(t.screen.text, contains('…'));
        expect(caught, 1);
        await t.paste('x\x03');
        t.host.handleKey(const KeyEvent('shift'));
        await t.pump();
        expect(t.exitRequested, isFalse);
        await t.press('x');
        expect(t.exitRequested, isTrue);
        expect(failedAction, 0);
      },
    );
    for (final key in [
      'enter',
      'esc',
      'ctrl+c',
      'ctrl+d',
      'up',
      'space',
      'shift+left',
    ]) {
      testWidgets('$key quits the fallback exactly once at $size', (t) async {
        var quits = 0;
        await t.pumpWidget(
          CrashScreen(error: error, stackTrace: stack, onQuit: () => quits++),
          size: size,
        );
        await t.press('$key $key');
        expect(quits, 1);
      });
    }
  }
  test(
    'retained failure rethrows the same object and native stack after shutdown',
    () {
      final failure = WindowCrash();
      failure.rethrowIfCaught();
      failure.caught(error, stack);
      failure.caught(StateError('late'), StackTrace.empty);
      try {
        failure.rethrowIfCaught();
        fail('did not rethrow');
      } catch (caught, trace) {
        expect(caught, same(error));
        expect(trace, same(stack));
      }
    },
  );
  group('the crash fixture', () {
    // Compiled once and kept rather than with `dart run`, whose compile took
    // most of the case's budget under load, in setUpAll, which is bounded by
    // the test runner's own setUpAll limit, not by the case's.
    late List<String> crash;
    setUpAll(() {
      crash = fixtureCommand('test/fixtures/crash_window.dart');
    });
    test(
      'crash stderr follows terminal restoration and owned close, exits one',
      () async {
        final result = await Process.run(crash.first, crash.sublist(1));
        expect(result.exitCode, 1, reason: '${result.stdout}${result.stderr}');
        expect(result.stdout, contains('RESTORED'));
        expect(
          result.stderr.toString(),
          startsWith(
            'OWNED_CLOSED\nBad state: window failed\n#0 Throws (fixture.dart:1:1)',
          ),
        );
        expect(
          'Bad state: window failed'.allMatches(result.stderr.toString()),
          hasLength(1),
        );
      },
    );
  });

  group('tester: crash fallback input and rendering edges', () {
    testWidgets(
      'all modifier aliases and a thousand pastes are inert before one real key',
      (t) async {
        var quits = 0;
        await t.pumpWidget(
          CrashScreen(error: error, stackTrace: stack, onQuit: () => quits++),
        );
        for (final key in [
          'shift',
          'ctrl',
          'control',
          'alt',
          'meta',
          'super',
          'cmd',
        ]) {
          t.host.handleKey(KeyEvent(key));
        }
        for (var i = 0; i < 1000; i++) {
          t.host.handlePaste('x\x03\x04界🙂e\u0301');
        }
        await t.pump();
        expect(quits, 0);
        t.host.handleKey(const KeyEvent('f12', alt: true));
        t.host.handleKey(const KeyEvent('f24'));
        await t.pump();
        expect(quits, 1);
      },
    );

    for (final size in [const Size(0, 0), const Size(1, 1)]) {
      testWidgets(
        'a stackless fallback survives $size then resizes and quits',
        (t) async {
          var quits = 0;
          await t.pumpWidget(
            CrashScreen(
              error: 'plain failure',
              stackTrace: null,
              onQuit: () => quits++,
            ),
            size: size,
          );
          await t.resize(const Size(80, 24));
          expect(t.screen, shows('  plain failure'));
          expect(t.screen, isNot(shows('#0')));
          await t.paste('enter');
          expect(quits, 0);
          await t.press('alt+f12');
          expect(quits, 1);
        },
      );
    }

    for (final (name, theme) in [
      ('dark', ThemeData.dark()),
      ('plain', ThemeData.plain()),
    ]) {
      for (final size in [const Size(120, 40), const Size(80, 24)]) {
        testWidgets(
          'Unicode multiline fallback keeps error and frame roles, $name at $size',
          (t) async {
            await t.pumpWidget(
              Theme(
                data: theme,
                child: CrashScreen(
                  error: '界🙂e\u0301\nsecond line',
                  stackTrace: StackTrace.fromString(
                    '#0 worker (fixture.dart:1:1)',
                  ),
                  onQuit: () {},
                ),
              ),
              size: size,
            );
            expect(t.screen.lines.take(6), [
              '',
              '  界🙂e\u0301',
              '  second line',
              '  #0 worker (fixture.dart:1:1)',
              '',
              '  any key to quit · chord prints the error to stderr as it exits',
            ]);
            expect(t.screen.styleAt(2, 1).fg, theme.error.fg);
            expect(t.screen.styleAt(2, 3).fg, theme.dim.fg);
            await t.resize(const Size(12, 3));
            expect(t.screen.lines.length, 3);
            for (final line in t.screen.lines) {
              expect(cellWidth(line), lessThanOrEqualTo(12));
            }
            await t.resize(size);
            expect(t.screen, shows('界🙂e\u0301'));
          },
        );
      }
    }

    test(
      'non-Error thrown values retain their first native stack through later notifications',
      () {
        final failure = WindowCrash();
        final value = Object();
        failure.caught(value, stack);
        for (var i = 0; i < 1000; i++) {
          failure.caught(StateError('late $i'), StackTrace.empty);
        }
        try {
          failure.rethrowIfCaught();
          fail('did not throw');
        } catch (caught, trace) {
          expect(caught, same(value));
          expect(trace, same(stack));
        }
      },
    );
  });
}
