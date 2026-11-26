@Tags(['browser'])
// Covers the build and Chrome's start, which take no timeout of their own.
@Timeout(Duration(minutes: 6))
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

// CHD-638: the built site served as a host serves it, in the system's
// Chrome (CHROME names its binary elsewhere): it loads and draws, keys,
// clicks and kitty keys reach it, its paths are real, and the console stays
// clean.
void main() {
  Process? server;
  Browser? browser;
  late Page page;
  late int port;
  final errors = <String>[];

  Future<void> buildAndServe(String base) async {
    server?.kill();
    final build = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/build.dart',
      'build',
      '--base=$base',
    ]);
    expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
    final serving = server = await Process.start(Platform.resolvedExecutable, [
      'run',
      'tool/build.dart',
      'serve',
      '--base=$base',
      '--port=0',
    ]);
    final address = Completer<int>();
    serving.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((line) {
          final match = RegExp(r'127\.0\.0\.1:(\d+)').firstMatch(line);
          if (match != null && !address.isCompleted) {
            address.complete(int.parse(match[1]!));
          }
        });
    port = await address.future.timeout(const Duration(minutes: 1));
  }

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

  Future<void> open(String path) async {
    await page.goto('http://127.0.0.1:$port$path', wait: Until.load);
    await page.waitForFunction('() => typeof chordStart === "number"');
  }

  setUpAll(() async {
    await buildAndServe('/');
    browser = await puppeteer.launch(
      executablePath:
          Platform.environment['CHROME'] ??
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    );
    page = await browser!.newPage();
    await page.setViewport(const DeviceViewport(width: 1200, height: 800));
    page.onConsole.listen((message) {
      if (message.type == ConsoleMessageType.error) {
        errors.add(message.text ?? '');
      }
    });
    page.onError.listen((error) => errors.add('$error'));
  });
  tearDownAll(() async {
    await browser?.close();
    server?.kill();
  });

  test('it loads, draws home, and says how long it took to start', () async {
    await open('/?cols=120&rows=40');
    await until('❯ 1. chord');
    final start = await page.evaluate<num>('() => chordStart');
    printOnFailure('start: $start ms');
    expect(start, lessThan(5000));
    expect(
      await page.evaluate<String>('() => document.title'),
      'chord and chord_tui',
    );
    expect(errors, isEmpty);
  });

  test('enter on item 3 opens the gallery at its own path', () async {
    await open('/?cols=120&rows=40');
    await until('❯ 1. chord');
    await page.keyboard.press(Key.arrowDown);
    await page.keyboard.press(Key.arrowDown);
    await page.keyboard.press(Key.enter);
    await until('chord › chord_tui › gallery');
    expect(
      await page.evaluate<String>('() => location.pathname'),
      '/chord_tui/gallery',
    );
    expect(
      await page.evaluate<String>('() => document.title'),
      'gallery · chord_tui',
    );
    // Back is the browser's: the shell follows it without pushing.
    await page.goBack();
    await until('❯ 1. chord');
    expect(await page.evaluate<String>('() => location.pathname'), '/');
  });

  test('a deep link opens its page', () async {
    await open('/chord_tui/picker?cols=120&rows=40');
    await until('Pick one');
    expect(
      await page.evaluate<String>('() => document.title'),
      'picker · chord_tui',
    );
  });

  test('a click on a menu row opens it: SGR mouse reaches the app', () async {
    await open('/?cols=120&rows=40');
    await until('2. chord_tui');
    final row = await page.evaluate<Map<dynamic, dynamic>>('''() => {
      const rows = [...document.querySelectorAll("#terminal .term-row")];
      const row = rows.find((r) => r.innerText.includes("2. chord_tui"));
      const box = row.getBoundingClientRect();
      return {x: box.left + 60, y: box.top + box.height / 2};
    }''');
    await page.mouse.click(
      Point((row['x'] as num).toDouble(), (row['y'] as num).toDouble()),
    );
    await until('chord › chord_tui');
    expect(
      await page.evaluate<String>('() => location.pathname'),
      '/chord_tui',
    );
  });

  test('shift+enter reaches a text area as a kitty key', () async {
    await open('/chord_tui/text_area?cols=120&rows=40');
    await until('Text area');
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

  test('a recording page fetches and plays its recording', () async {
    await open('/chord/permission?cols=80&rows=24');
    await until('Do you want to proceed?');
    expect(await screen(), contains('▶'));
  });

  test('the console stayed clean', () {
    expect(errors, isEmpty);
  });

  test('under a base, deep links and assets resolve against it', () async {
    await buildAndServe('/chord/');
    await open('/chord/chord_tui/gallery?cols=120&rows=40');
    await until('chord › chord_tui › gallery');
    expect(errors, isEmpty);
    // A missing asset fails loudly instead of loading the page.
    final missing = await page.evaluate<int>(
      '() => fetch("chord_tui/main.wasm").then((r) => r.status)',
    );
    expect(missing, 404);
  });
}
