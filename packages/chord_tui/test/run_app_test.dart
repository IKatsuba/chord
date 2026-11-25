import 'dart:async';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

/// A terminal that records what is written and answers the background
/// question with [answer], split into parts [gap] apart, if given.
class FakeTerminal extends Terminal {
  FakeTerminal({this.answer = const [], this.gap = Duration.zero});

  final List<String> answer;
  final Duration gap;
  final input$ = StreamController<String>();
  final written = StringBuffer();
  final clock = Stopwatch();
  Duration? askedAt;
  Duration? firstFrameAt;

  @override
  Size get size => const Size(80, 24);

  @override
  Stream<String> get input => input$.stream;

  @override
  Stream<Size> get resizes => const Stream.empty();

  @override
  void enter() => clock.start();

  @override
  Future<void> leave() async {}

  @override
  void write(String data) {
    if (data == '\x1b]11;?\x07') {
      askedAt = clock.elapsed;
      unawaited(_answer());
    } else if (data.isNotEmpty && data != '\x1b[?u') {
      firstFrameAt ??= clock.elapsed;
    }
    written.write(data);
  }

  Future<void> _answer() async {
    for (final part in answer) {
      await Future<void>.delayed(gap);
      input$.add(part);
    }
  }

  void type(String text) => input$.add(text);
  Future<void> close() => input$.close();
}

/// What the app saw.
class Seen {
  TerminalBackground? background;
  bool? noColor;
  ThemeData? theme;
  final keys = <String>[];
}

Widget probe(Seen seen) => Builder(
  builder: (context) {
    seen
      ..background = Theme.backgroundOf(context)
      ..noColor = Theme.noColorOf(context)
      ..theme = Theme.of(context);
    return Focus(
      autofocus: true,
      onKey: (e) {
        seen.keys.add(e.combo.toString());
        return true;
      },
      child: Text('app'),
    );
  },
);

Future<Seen> run(
  FakeTerminal term, {
  Map<String, String> environment = const {},
  ThemeData? theme,
  Future<void> Function()? during,
  Duration until = const Duration(milliseconds: 200),
}) async {
  final seen = Seen();
  final running = runApp(
    probe(seen),
    terminal: term,
    exitProcess: false,
    environment: environment,
    theme: theme,
  );
  await during?.call();
  await Future<void>.delayed(until);
  await term.close();
  await running;
  return seen;
}

const _light = '\x1b]11;rgb:ffff/ffff/ffff\x07';
const _dark = '\x1b]11;rgb:1e1e/1e1e/1e1e\x1b\\';

void main() {
  _beforeExitTests();

  group('tester beforeExit lifecycle boundaries', () {
    test(
      'input ending before mount still awaits the hook exactly once',
      () async {
        final term = _TesterTerminal();
        final hookEntered = Completer<void>();
        final release = Completer<void>();
        var mounts = 0;
        var calls = 0;
        var returned = false;
        final running = runApp(
          Builder(
            builder: (_) {
              mounts++;
              return Text('unused');
            },
          ),
          terminal: term,
          exitProcess: false,
          environment: const {},
          beforeExit: () async {
            calls++;
            expect(term.leaves, 1);
            hookEntered.complete();
            await release.future;
          },
        ).then((_) => returned = true);
        await term.query.future;
        await term.close();
        await hookEntered.future;
        expect(mounts, 0);
        expect(returned, isFalse);
        release.complete();
        await running;
        expect(calls, 1);
      },
    );

    test('an asynchronous terminal restore finishes before the hook', () async {
      final term = _TesterDelayedLeave();
      var calls = 0;
      final running = runApp(
        Text('ready'),
        terminal: term,
        exitProcess: false,
        environment: const {},
        beforeExit: () async {
          calls++;
          expect(term.leaves, 1);
        },
      );
      await term.frame.future;
      term.type('\x03\x04\x03');
      await term.restoring.future;
      expect(calls, 0);
      term.release.complete();
      await running;
      expect(calls, 1);
      expect(term.leaves, 1);
      await term.close();
    });

    test(
      'a rejected hook is consumed and called once without process exit',
      () async {
        final term = _TesterTerminal();
        var calls = 0;
        final running = runApp(
          Text('ready'),
          terminal: term,
          exitProcess: false,
          environment: const {},
          beforeExit: () async {
            calls++;
            throw StateError('tester hook failed');
          },
        );
        await term.frame.future;
        term.type('\x03');
        await running;
        expect(calls, 1);
        expect(term.leaves, 1);
        await term.close();
      },
    );
  });

  group('runApp asks the terminal for its background', () {
    test(
      'a light answer gives the light theme, before the first frame',
      () async {
        final term = FakeTerminal(answer: [_light]);
        final seen = await run(term);
        expect(term.askedAt, isNotNull);
        expect(term.firstFrameAt, greaterThanOrEqualTo(term.askedAt!));
        expect(term.written.toString(), contains('app'));
        expect(
          seen.background,
          const TerminalBackground(Brightness.light, BrightnessSource.terminal),
        );
        expect(seen.theme, ThemeData.light());
        expect(seen.noColor, isFalse);
      },
    );

    test(
      'a dark answer gives the dark theme, even with COLORFGBG light',
      () async {
        final seen = await run(
          FakeTerminal(answer: [_dark]),
          environment: {'COLORFGBG': '0;15'},
        );
        expect(seen.background!.source, BrightnessSource.terminal);
        expect(seen.theme, ThemeData.dark());
      },
    );

    test('no answer: COLORFGBG after 100 ms', () async {
      final term = FakeTerminal();
      final seen = await run(term, environment: {'COLORFGBG': '0;15'});
      expect(
        seen.background,
        const TerminalBackground(Brightness.light, BrightnessSource.colorFgBg),
      );
      expect(seen.theme, ThemeData.light());
      expect(
        term.firstFrameAt! - term.askedAt!,
        greaterThanOrEqualTo(const Duration(milliseconds: 95)),
      );
    });

    test('no answer and no COLORFGBG: dark by default', () async {
      final seen = await run(FakeTerminal());
      expect(
        seen.background,
        const TerminalBackground(Brightness.dark, BrightnessSource.fallback),
      );
      expect(seen.theme, ThemeData.dark());
    });

    test('a theme given is used whatever the background', () async {
      final mine = ThemeData.dark().copyWith(accent: Style.bold);
      final seen = await run(FakeTerminal(answer: [_light]), theme: mine);
      expect(seen.theme, mine);
      expect(seen.background!.brightness, Brightness.light);
    });

    test('NO_COLOR wins over a theme given, and still asks', () async {
      final seen = await run(
        FakeTerminal(answer: [_light]),
        environment: {'NO_COLOR': '1'},
        theme: ThemeData.dark(),
      );
      expect(seen.theme, ThemeData.plain(brightness: Brightness.light));
      expect(seen.noColor, isTrue);
      expect(seen.background!.source, BrightnessSource.terminal);
    });

    test('NO_COLOR set but empty does not count', () async {
      final seen = await run(
        FakeTerminal(answer: [_light]),
        environment: {'NO_COLOR': ''},
      );
      expect(seen.noColor, isFalse);
      expect(seen.theme, ThemeData.light());
    });

    test(
      'a reply split 40 ms apart, past a lone escape\'s 30, is still read, never typed',
      () async {
        final seen = await run(
          FakeTerminal(
            answer: ['\x1b]11;rgb:ff', 'ff/ffff/ffff\x07'],
            gap: const Duration(milliseconds: 40),
          ),
        );
        expect(seen.background!.source, BrightnessSource.terminal);
        expect(seen.keys, isEmpty);
      },
    );

    test('keys typed during the wait reach the app, in order', () async {
      final term = FakeTerminal(
        answer: [_light],
        gap: const Duration(milliseconds: 50),
      );
      final seen = await run(
        term,
        during: () async {
          await Future<void>.delayed(const Duration(milliseconds: 10));
          term.type('ab');
        },
      );
      expect(seen.keys, ['a', 'b']);
      expect(seen.theme, ThemeData.light());
    });

    test('a late reply is dropped, never typed', () async {
      final term = FakeTerminal();
      final seen = await run(
        term,
        during: () async {
          await Future<void>.delayed(const Duration(milliseconds: 150));
          term.type(
            'x$_light'
            'y',
          );
        },
      );
      expect(seen.background!.source, BrightnessSource.fallback);
      expect(seen.keys, ['x', 'y']);
    });
  });

  group('tester: startup lifecycle and held input', () {
    test(
      'input closes during the ask without mounting and leaves once',
      () async {
        final term = _TesterTerminal();
        var mounts = 0;
        final running = runApp(
          Builder(
            builder: (_) {
              mounts++;
              return Text('unexpected');
            },
          ),
          terminal: term,
          exitProcess: false,
          environment: const {},
        );
        await term.query.future;
        await term.close();
        await running.timeout(const Duration(seconds: 2));
        expect(mounts, 0);
        expect(term.leaves, 1);
        expect(term.written.toString(), '\x1b]11;?\x07\x1b[?u');
      },
    );

    test(
      'held keys and paste are delivered once in order after one mount',
      () async {
        final term = _TesterTerminal();
        final events = <String>[];
        var mounts = 0;
        final running = runApp(
          Builder(
            builder: (c) {
              mounts++;
              return Focus(
                autofocus: true,
                onKey: (e) {
                  events.add(e.combo.toString());
                  return true;
                },
                onPaste: (text) {
                  events.add('paste:$text');
                  return true;
                },
                child: Text('ready'),
              );
            },
          ),
          terminal: term,
          exitProcess: false,
          environment: const {},
        );
        await term.query.future;
        term.type(
          'a\x1b[200~日本語🙂\x1b]11;literal\x07\x1b[201~b$_light'
          'c',
        );
        await term.frame.future;
        expect(mounts, 1);
        expect(events, ['a', 'paste:日本語🙂\x1b]11;literal\x07', 'b', 'c']);
        await term.close();
        await running;
        expect(term.leaves, 1);
      },
    );

    test(
      'other OSC does not resolve the ask and malformed OSC 11 falls back',
      () async {
        final term = _TesterTerminal();
        final seen = Seen();
        final running = runApp(
          probe(seen),
          terminal: term,
          exitProcess: false,
          environment: const {'COLORFGBG': '0;15', 'NO_COLOR': '0'},
        );
        await term.query.future;
        term.type('\x1b]10;#000000\x07');
        await Future<void>.delayed(Duration.zero);
        expect(seen.theme, isNull);
        term.type(
          'a\x1b]11;invalid\x07$_dark'
          'b',
        );
        await term.frame.future;
        expect(
          seen.background,
          const TerminalBackground(
            Brightness.light,
            BrightnessSource.colorFgBg,
          ),
        );
        expect(seen.theme, ThemeData.plain(brightness: Brightness.light));
        expect(seen.noColor, isTrue);
        expect(seen.keys, ['a', 'b']);
        await term.close();
        await running;
      },
    );

    test('held quit cancels pending escape and frame timers', () async {
      final term = _TesterTerminal();
      final running = runApp(
        Text('ready'),
        terminal: term,
        exitProcess: false,
        environment: const {},
      );
      await term.query.future;
      term.type('\x03$_light\x1b]11;partial');
      await running.timeout(const Duration(seconds: 2));
      expect(term.leaves, 1);
      final output = term.written.toString();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(term.written.toString(), output);
      await term.close();
    });

    test('input error during the ask leaves without mounting', () async {
      final term = _TesterTerminal();
      var mounts = 0;
      final running = runApp(
        Builder(
          builder: (_) {
            mounts++;
            return Text('unexpected');
          },
        ),
        terminal: term,
        exitProcess: false,
        environment: const {},
      );
      await term.query.future;
      term.input$.addError(StateError('tester input failure'));
      await running.timeout(const Duration(seconds: 2));
      expect(mounts, 0);
      expect(term.leaves, 1);
      await term.close();
    });
  });
}

class _TesterTerminal extends FakeTerminal {
  final query = Completer<void>();
  final frame = Completer<void>();
  var leaves = 0;

  @override
  void write(String data) {
    super.write(data);
    if (data == '\x1b]11;?\x07') {
      if (!query.isCompleted) query.complete();
    } else if (data.isNotEmpty && data != '\x1b[?u' && !frame.isCompleted) {
      frame.complete();
    }
  }

  @override
  Future<void> leave() async {
    leaves++;
  }
}

void _beforeExitTests() {
  group('runApp beforeExit', () {
    test('is awaited after the app is unmounted and the terminal left, '
        'before runApp returns', () async {
      final term = _TesterTerminal();
      final order = <String>[];
      final running = runApp(
        _Disposed(() => order.add('unmounted')),
        terminal: term,
        exitProcess: false,
        environment: const {},
        beforeExit: () async {
          order.add('before exit, left ${term.leaves}');
          await Future<void>.delayed(const Duration(milliseconds: 20));
          order.add('closed');
        },
      );
      await term.frame.future;
      term.type('\x03');
      await running;
      order.add('returned');
      expect(order, ['unmounted', 'before exit, left 1', 'closed', 'returned']);
    });

    test('runs after a failure too', () async {
      final term = _TesterTerminal();
      var ran = false;
      final running = runApp(
        Text('ready'),
        terminal: term,
        exitProcess: false,
        environment: const {},
        beforeExit: () async => ran = true,
      );
      await term.frame.future;
      term.input$.addError(StateError('input failure'));
      await running;
      expect(ran, isTrue);
    });

    test(
      'runs after an unmount that throws, the terminal left first',
      () async {
        final term = _TesterTerminal();
        final order = <String>[];
        final running = runApp(
          _Disposed(() => throw StateError('dispose failed')),
          terminal: term,
          exitProcess: false,
          environment: const {},
          beforeExit: () async => order.add('before exit, left ${term.leaves}'),
        );
        await term.frame.future;
        term.type('\x03');
        await running;
        expect(order, ['before exit, left 1']);
      },
    );

    test('runs after the terminal fails to be left', () async {
      final term = _FailingLeave();
      var ran = false;
      final running = runApp(
        Text('ready'),
        terminal: term,
        exitProcess: false,
        environment: const {},
        beforeExit: () async => ran = true,
      );
      await term.frame.future;
      term.type('\x03');
      await running;
      expect(term.leaves, 1);
      expect(ran, isTrue);
    });

    // CTUI-114: the guarded body's own future is awaited from outside its
    // error zone, where a failure of it would never arrive.
    test('runs, and runApp returns, when the terminal cannot enter', () async {
      final term = _FailingEnter();
      var ran = false;
      await runApp(
        Text('unused'),
        terminal: term,
        exitProcess: false,
        handleSignals: false,
        environment: const {},
        beforeExit: () async => ran = true,
      ).timeout(const Duration(seconds: 5));
      expect(term.leaves, 1);
      expect(ran, isTrue);
    });

    test(
      'runs, and runApp returns, when the first frame cannot be written',
      () async {
        final term = _FailingWrite();
        var ran = false;
        await runApp(
          Text('unused'),
          terminal: term,
          exitProcess: false,
          handleSignals: false,
          environment: const {},
          beforeExit: () async => ran = true,
        ).timeout(const Duration(seconds: 5));
        expect(term.leaves, 1);
        expect(ran, isTrue);
      },
    );

    for (final (how, code, said) in [
      ('ok', 0, ''),
      ('fails', 1, 'Bad state: input failed'),
      ('throws', 1, 'Bad state: close failed'),
      ('enters', 1, 'Bad state: enter failed'),
      ('writes', 1, 'Bad state: write failed'),
    ]) {
      test('exits $code when $how', () async {
        final process = await Process.start(Platform.resolvedExecutable, [
          'run',
          'test/fixtures/run_app_exit.dart',
          how,
        ]);
        final out = process.stdout.transform(systemEncoding.decoder).join();
        final err = process.stderr.transform(systemEncoding.decoder).join();
        // A run that never exits is the failure, and must not outlive it.
        final exitCode = await process.exitCode.timeout(
          const Duration(seconds: 20),
          onTimeout: () {
            process.kill(ProcessSignal.sigkill);
            return -1;
          },
        );
        expect(exitCode, code);
        expect(await out, endsWith('left\nclosed\n'));
        if (said.isEmpty) {
          expect(await err, isEmpty);
        } else {
          expect(await err, startsWith(said));
        }
      });
    }
  });
}

/// Calls [onDispose] when unmounted.
class _Disposed extends StatefulWidget {
  const _Disposed(this.onDispose);

  final void Function() onDispose;

  @override
  State<_Disposed> createState() => _DisposedState();
}

class _DisposedState extends State<_Disposed> {
  @override
  void dispose() {
    widget.onDispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Text('ready');
}

/// A terminal whose first frame cannot be written.
class _FailingWrite extends _TesterTerminal {
  @override
  void write(String data) {
    super.write(data);
    if (frame.isCompleted) throw StateError('write failed');
  }
}

/// A terminal that cannot be entered.
class _FailingEnter extends _TesterTerminal {
  @override
  void enter() => throw StateError('enter failed');
}

/// A terminal whose restore fails.
class _FailingLeave extends _TesterTerminal {
  @override
  Future<void> leave() async {
    await super.leave();
    throw StateError('leave failed');
  }
}

class _TesterDelayedLeave extends _TesterTerminal {
  final restoring = Completer<void>();
  final release = Completer<void>();

  @override
  Future<void> leave() async {
    restoring.complete();
    await release.future;
    await super.leave();
  }
}
