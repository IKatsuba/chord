@Tags(['browser'])
// Covers two builds and Chrome's start, which take no timeout of their own.
@Timeout(Duration(minutes: 8))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

// CHD-638: the built site served as a host serves it, at the root and under
// a base, in the system's Chrome (CHROME names its binary elsewhere): it
// loads and draws, keys, clicks and kitty keys reach it, its paths are real
// both ways, Back and Esc move as the Routes say, and the console stays
// clean.

/// A clipboard the page writes to instead of the system's, put in place
/// before each document's own scripts run; `testCopied()` reads it.
const clipboardStandIn = '''() => {
  const copied = [];
  Object.defineProperty(navigator, "clipboard", {
    configurable: true,
    value: {
      writeText: async (text) => { copied.push(text); },
      readText: async () => copied.at(-1) ?? "",
      standIn: true,
    },
  });
  globalThis.testCopied = () => copied;
}''';

/// `build.dart serve`, started and stopped by the test, its output kept.
class _Server {
  _Server._(this._process, this.port, this._errors);

  final Process _process;

  /// The port it answers on.
  final int port;

  final StringBuffer _errors;

  /// Builds the site for [base] and serves it, failing at once if serve
  /// ends before it says where it answers.
  static Future<_Server> start(String base) async {
    final build = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/build.dart',
      'build',
      '--base=$base',
    ]);
    expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
    return launch(Platform.resolvedExecutable, [
      'run',
      'tool/build.dart',
      'serve',
      '--base=$base',
      '--port=0',
    ]);
  }

  /// Runs [executable] as a server and waits up to [ready] for it to say
  /// its port. A server that ends first, or is not ready in time, is
  /// stopped and awaited before the failure is thrown: nothing outlives a
  /// failed start. [started] is told of the process, for tests of that.
  static Future<_Server> launch(
    String executable,
    List<String> arguments, {
    Duration ready = const Duration(minutes: 1),
    void Function(Process process)? started,
  }) async {
    final process = await Process.start(executable, arguments);
    started?.call(process);
    final errors = StringBuffer();
    process.stderr.transform(utf8.decoder).listen(errors.write);
    final address = Completer<int>();
    process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final match = RegExp(r'127\.0\.0\.1:(\d+)').firstMatch(line);
          if (match != null && !address.isCompleted) {
            address.complete(int.parse(match[1]!));
          }
        });
    try {
      final port = await Future.any([
        address.future,
        process.exitCode.then<int>(
          (code) => throw StateError('serve ended with $code:\n$errors'),
        ),
      ]).timeout(ready);
      return _Server._(process, port, errors);
    } catch (_) {
      await _stopProcess(process);
      rethrow;
    }
  }

  /// Stops it and waits for it to be gone, killing it if it lingers.
  Future<void> stop() => _stopProcess(_process);

  static Future<void> _stopProcess(Process process) async {
    process.kill();
    final ended = await process.exitCode
        .then<bool>((_) => true)
        .timeout(const Duration(seconds: 5), onTimeout: () => false);
    if (!ended) {
      process.kill(ProcessSignal.sigkill);
      await process.exitCode;
    }
  }

  /// What it said on stderr.
  String get errors => '$_errors';
}

void main() {
  Browser? browser;

  setUpAll(() async {
    browser = await puppeteer.launch(
      executablePath:
          Platform.environment['CHROME'] ??
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    );
  });
  tearDownAll(() async => browser?.close());

  test('a server that is never ready is stopped before start fails', () async {
    Process? started;
    await expectLater(
      _Server.launch(
        '/bin/sleep',
        ['30'],
        ready: const Duration(milliseconds: 300),
        started: (process) => started = process,
      ),
      throwsA(isA<TimeoutException>()),
    );
    // Already gone: start awaited its end before it threw.
    final code = await started!.exitCode.timeout(Duration.zero);
    expect(code, isNot(0));
  });

  test('a server that ends before it is ready fails at once', () async {
    final watch = Stopwatch()..start();
    await expectLater(
      _Server.launch('/bin/sh', ['-c', 'echo broken >&2; exit 3']),
      throwsA(
        isA<StateError>().having((e) => e.message, 'message', contains('3')),
      ),
    );
    expect(watch.elapsed, lessThan(const Duration(seconds: 10)));
  });

  for (final base in ['/', '/chord/']) {
    group('under $base', () {
      _Server? server;
      late Page page;
      Page? opened;
      final errors = <String>[];

      setUpAll(() async {
        server = await _Server.start(base);
        page = opened = await browser!.newPage();
        // Before every document, so before the app: the site's copy keys
        // reach a stand-in, never the person's own clipboard.
        await page.evaluateOnNewDocument(clipboardStandIn);
        await page.setViewport(const DeviceViewport(width: 1200, height: 800));
        page.onConsole.listen((message) {
          if (message.type == ConsoleMessageType.error) {
            errors.add(message.text ?? '');
          }
        });
        page.onError.listen((error) => errors.add('$error'));
      });
      // The server is stopped whatever happened to the page, or to start.
      tearDownAll(() async {
        try {
          await opened?.close();
        } finally {
          await server?.stop();
        }
      });

      String url(String path) =>
          'http://127.0.0.1:${server!.port}$base${path.substring(1)}';

      Future<String> screen() => page.evaluate<String>(
        '() => [...document.querySelectorAll("#terminal .term-row")]'
        '.map((row) => row.innerText).join("\\n")',
      );

      Future<void> until(String text) async {
        final deadline = DateTime.now().add(const Duration(seconds: 15));
        while (!(await screen()).contains(text)) {
          if (DateTime.now().isAfter(deadline)) {
            fail('timed out on "$text":\n${await screen()}');
          }
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      Future<void> open(String path, {String size = 'cols=120&rows=40'}) async {
        await page.goto('${url(path)}?$size', wait: Until.load);
        expect(
          await page.evaluate<bool>(
            '() => navigator.clipboard.standIn === true',
          ),
          isTrue,
          reason: 'the clipboard is the stand-in',
        );
        await page.waitForFunction('() => typeof chordStart === "number"');
      }

      Future<String> pathname() =>
          page.evaluate<String>('() => location.pathname');

      test(
        'it loads, draws home, and says how long it took to start',
        () async {
          await open('/');
          await until('A TERMINAL WINDOW');
          final start = await page.evaluate<num>('() => chordStart');
          printOnFailure('start: $start ms');
          expect(start, lessThan(5000));
          expect(
            await page.evaluate<String>('() => document.title'),
            'chord and chord_tui',
          );
        },
      );

      test('3 opens the gallery; Back comes home', () async {
        await open('/');
        await until('A TERMINAL WINDOW');
        await page.keyboard.press(Key.digit3);
        await until('03 / THE GALLERY');
        expect(await pathname(), '${base}chord_tui/gallery');
        expect(
          await page.evaluate<String>('() => document.title'),
          'gallery · chord_tui',
        );
        await page.goBack();
        await until('A TERMINAL WINDOW');
        expect(await pathname(), base);
      });

      test('a deep link opens its page; Esc goes to its parent; Back '
          'returns', () async {
        await open('/chord_tui/markdown');
        await until('EXAMPLE/MARKDOWN.DART');
        expect(
          await page.evaluate<String>('() => document.title'),
          'markdown · chord_tui',
        );
        await page.keyboard.press(Key.escape);
        await until('03 / THE GALLERY');
        expect(await pathname(), '${base}chord_tui/gallery');
        await page.goBack();
        await until('EXAMPLE/MARKDOWN.DART');
        expect(await pathname(), '${base}chord_tui/markdown');
      });

      test('an unknown path draws not found, and keeps the path', () async {
        await open('/chord_tui/markdwon');
        await until('PAGE NOT FOUND.');
        await until('/chord_tui/markdwon');
        expect(
          await page.evaluate<String>('() => document.title'),
          'not found · chord',
        );
        expect(await pathname(), '${base}chord_tui/markdwon');
      });

      test(
        'a click on a home column opens it: SGR mouse reaches the app',
        () async {
          await open('/', size: 'cols=120&rows=80');
          await until('THE FRAMEWORK');
          final row = await page.evaluate<Map<dynamic, dynamic>>('''() => {
          const rows = [...document.querySelectorAll("#terminal .term-row")];
          const row = rows.find((r) => r.innerText.includes("THE FRAMEWORK"));
          const box = row.getBoundingClientRect();
          const column = row.innerText.indexOf("THE FRAMEWORK");
          return {x: box.left + (column + 2) * box.width / chordTerminal.cols,
            y: box.top + box.height / 2};
        }''');
          await page.mouse.click(
            Point((row['x'] as num).toDouble(), (row['y'] as num).toDouble()),
          );
          await until('02 / FRAMEWORK');
          expect(await pathname(), '${base}chord_tui');
        },
      );

      test('shift+enter reaches an entered text area as a kitty key', () async {
        await open('/chord_tui/text_area');
        await until('TAB TO ENTER');
        await page.keyboard.press(Key.tab);
        await until('ESC LEAVES');
        await page.keyboard.type('first');
        await page.keyboard.down(Key.shift);
        await page.keyboard.press(Key.enter);
        await page.keyboard.up(Key.shift);
        await page.keyboard.type('second');
        await until('second');
        final lines = (await screen()).split('\n');
        final first = lines.indexWhere((l) => l.contains('first'));
        final second = lines.indexWhere((l) => l.contains('second'));
        expect(second, greaterThan(first));
      });

      test('c on install copies to the stand-in clipboard', () async {
        await open('/install');
        await until('COPY c');
        await page.keyboard.press(Key.keyC);
        await until('COPIED');
        expect(await page.evaluate<List<dynamic>>('() => testCopied()'), [
          'brew install ikatsuba/tap/chord',
        ]);
      });

      test('a recording page fetches and plays its recording', () async {
        // 120x36 in its frame: the page has 42 rows under the nav.
        await open('/chord/permission', size: 'cols=122&rows=47');
        await until('01 / THE APP / PERMISSION');
        await until('Do you want to proceed?');
        expect(await screen(), contains('▶'));
      });

      group('tester: viewport and emulated touch', () {
        test('auto-resize keeps the selected home action', () async {
          try {
            await page.setViewport(
              const DeviceViewport(width: 1200, height: 800),
            );
            await open('/', size: '');
            await until('❯ 1. chord');
            final before = await page.evaluate<Map<dynamic, dynamic>>(
              '() => ({cols: chordTerminal.cols, rows: chordTerminal.rows})',
            );
            await page.keyboard.press(Key.arrowDown);
            await until('❯ 2. chord_tui');
            await page.setViewport(
              const DeviceViewport(width: 700, height: 500),
            );
            await page.waitForFunction(
              '() => chordTerminal.cols < ${before['cols']} && '
              'chordTerminal.rows < ${before['rows']}',
            );
            await until('❯ 2. chord_tui');
            expect(await pathname(), base);
            await page.keyboard.press(Key.enter);
            await until('chord › chord_tui');
            expect(await pathname(), '${base}chord_tui');
          } finally {
            await page.setViewport(
              const DeviceViewport(width: 1200, height: 800),
            );
          }
        });

        test('emulated phone taps open a menu row and toggle F1', () async {
          try {
            await page.setViewport(
              const DeviceViewport(
                width: 390,
                height: 844,
                deviceScaleFactor: 2,
                isMobile: true,
                hasTouch: true,
              ),
            );
            await open('/', size: 'cols=43&rows=37');
            await until('2. chord_tui');
            final menu = await page.evaluate<Map<dynamic, dynamic>>('''() => {
              const row = [...document.querySelectorAll("#terminal .term-row")]
                .find((r) => r.innerText.includes("2. chord_tui"));
              const box = row.getBoundingClientRect();
              return {x: box.left + 60, y: box.top + box.height / 2};
            }''');
            await page.touchscreen.tap(
              Point(
                (menu['x'] as num).toDouble(),
                (menu['y'] as num).toDouble(),
              ),
            );
            await until('chord › chord_tui');
            expect(await pathname(), '${base}chord_tui');

            Future<void> tapF1() async {
              final key = await page.evaluate<Map<dynamic, dynamic>>('''() => {
                const row = [...document.querySelectorAll("#terminal .term-row")]
                  .find((r) => r.innerText.includes("esc") &&
                    r.innerText.includes("tab") && r.innerText.includes("f1"));
                const box = row.getBoundingClientRect();
                const column = row.innerText.indexOf("f1");
                return {x: box.left + (column + 0.5) * box.width / chordTerminal.cols,
                  y: box.top + box.height / 2};
              }''');
              await page.touchscreen.tap(
                Point(
                  (key['x'] as num).toDouble(),
                  (key['y'] as num).toDouble(),
                ),
              );
            }

            await tapF1();
            await until(' Keys');
            await tapF1();
            await page.waitForFunction('''() =>
              ![...document.querySelectorAll("#terminal .term-row")]
                .some((r) => r.innerText.includes(" Keys"))''');
          } finally {
            await page.setViewport(
              const DeviceViewport(width: 1200, height: 800),
            );
          }
        });
      });

      test('the console stayed clean', () {
        expect(errors, isEmpty);
        expect(server!.errors, isEmpty);
      });

      test('a missing asset is a 404, not the page', () async {
        await open('/');
        final status = await page.evaluate<int>(
          '() => fetch("chord_tui/main.wasm").then((r) => r.status)',
        );
        expect(status, 404);
      });
    });
  }
}
