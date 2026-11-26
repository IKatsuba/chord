@Tags(['browser'])
// Covers setUpAll's build and Chrome's start, which take no timeout of
// their own.
@Timeout(Duration(minutes: 3))
library;

import 'dart:async';
import 'dart:io';

import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

// CHD-638: WebTerminal binds a page's terminal to a chord_tui app compiled
// to Wasm, in the system's Chrome (CHROME names its binary elsewhere).
void main() {
  late Directory dir;
  HttpServer? server;
  Browser? browser;
  late Page page;
  final console = <String>[];
  final errors = <String>[];

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('chorded_web_terminal');
    final build = await Process.run('dart', [
      'compile',
      'wasm',
      'test/fixtures/web_terminal.dart',
      '-o',
      '${dir.path}/web_terminal.wasm',
    ]);
    expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
    File('test/fixtures/web_terminal.html').copySync('${dir.path}/index.html');
    final served = server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    served.listen((request) async {
      final name = request.uri.path == '/' ? 'index.html' : request.uri.path;
      final file = File('${dir.path}/$name');
      if (!file.existsSync()) {
        request.response.statusCode = HttpStatus.notFound;
      } else {
        request.response.headers.contentType = switch (name.split('.').last) {
          'wasm' => ContentType('application', 'wasm'),
          'mjs' => ContentType('text', 'javascript', charset: 'utf-8'),
          _ => ContentType.html,
        };
        await request.response.addStream(file.openRead());
      }
      await request.response.close();
    });
    final chrome = browser = await puppeteer.launch(
      executablePath:
          Platform.environment['CHROME'] ??
          '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
    );
    final origin = 'http://127.0.0.1:${served.port}';
    await chrome.defaultBrowserContext.overridePermissions(origin, [
      PermissionType.clipboardReadWrite,
    ]);
    page = await chrome.newPage();
    page.onConsole.listen((message) {
      final text = message.text ?? '';
      (message.type == ConsoleMessageType.error ? errors : console).add(text);
    });
    page.onError.listen((error) => errors.add('$error'));
    await page.goto(origin);
    await _until(page, "testWrites().includes('size 40x5')");
  });
  tearDownAll(() async {
    await browser?.close();
    await server?.close(force: true);
    dir.deleteSync(recursive: true);
  });

  test('enter takes the screen, with SGR mouse reports', () async {
    final written = await page.evaluate<String>('() => testWrites()');
    expect(
      written,
      startsWith(
        '\x1b[?1049h\x1b[?25l\x1b[?2004h\x1b[?1000h\x1b[?1002h\x1b[?1006h',
      ),
    );
  });

  test('a resize redraws at the new size', () async {
    await page.evaluate<void>('() => testResize(50, 6)');
    await _seen(console, 'size 50x6');
  });

  test('kitty keys reach the app as keys', () async {
    await page.evaluate<void>(r"() => testType('\x1b[13;2u')");
    await _seen(console, 'did kitty');
  });

  test('a copy goes to the browser clipboard', () async {
    await page.evaluate<void>("() => testType('c')");
    await _seen(console, 'did copied');
    await _until(
      page,
      "navigator.clipboard.readText().then((t) => t === 'from key')",
    );
  });

  test('a link opens without an opener', () async {
    await page.evaluate<void>("() => testType('o')");
    await _until(page, 'testOpened.length === 1');
    expect(await page.evaluate<List<Object?>>('() => testOpened[0]'), [
      'https://a.test/',
      '_blank',
      'noopener',
    ]);
  });

  test('the title is the document title', () async {
    await page.evaluate<void>("() => testType('t')");
    await _until(page, "document.title === 'chord_tui page'");
  });

  test('Ctrl+C quits cleanly: runApp returns, modes undone', () async {
    await page.evaluate<void>(r"() => testType('\x03')");
    await _seen(console, 'runApp returned 1');
    final written = await page.evaluate<String>('() => testWrites()');
    expect(
      written,
      contains(
        '\x1b[?1000l\x1b[?1002l\x1b[?1006l'
        '\x1b[?2004l\x1b[0m\x1b[0 q\x1b[?25h\x1b[?1049l',
      ),
    );
    expect(errors, isEmpty);
  });

  test('the same terminal serves a second runApp, keys once each', () async {
    // The second run has entered again after the first one's leave.
    await _until(
      page,
      "testWrites().lastIndexOf('\\x1b[?1049h') > "
      "testWrites().lastIndexOf('\\x1b[?1049l')",
    );
    final copies = console.where((line) => line == 'did copied').length;
    await page.evaluate<void>("() => testType('c')");
    await _seen(console, 'did copied', times: copies + 1);
    // A doubled page callback would handle the key twice.
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(console.where((line) => line == 'did copied').length, copies + 1);
    await page.evaluate<void>(r"() => testType('\x03')");
    await _seen(console, 'runApp returned 2');
    expect(console.where((line) => line.startsWith('runApp')).toList(), [
      'runApp returned 1',
      'runApp returned 2',
    ]);
    expect(errors, isEmpty);
  });
}

/// Waits for the page's console to have said [line] [times] times.
Future<void> _seen(List<String> console, String line, {int times = 1}) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (console.where((said) => said == line).length < times) {
    if (DateTime.now().isAfter(deadline)) fail('timed out on $line');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

/// Waits for [condition], a JavaScript expression the page evaluates, to
/// hold.
Future<void> _until(Page page, String condition) async {
  final deadline = DateTime.now().add(const Duration(seconds: 10));
  while (await page.evaluate<bool>('async () => !!($condition)') != true) {
    if (DateTime.now().isAfter(deadline)) fail('timed out on $condition');
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}
