@Tags(['browser'])
@Timeout(Duration(minutes: 6))
library;

import 'dart:async';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:puppeteer/puppeteer.dart';
import 'package:test/test.dart';

import '../../tool/serving.dart';
import 'site_browser_test.dart' show clipboardStandIn;

void main() {
  group('CHD-638 tester: fixed terminal metrics across resize', () {
    late Browser browser;
    late HttpServer server;

    setUpAll(() async {
      // Its own folder: site_browser_test.dart builds beside it, and a build
      // replaces the folder it writes.
      final out = Directory.systemTemp.createTempSync('chord_site_palette_');
      addTearDown(() => out.deleteSync(recursive: true));
      final build = await Process.start(Platform.resolvedExecutable, [
        'run',
        'tool/build.dart',
        'build',
        '--out=${out.path}',
      ]);
      var buildFinished = false;
      addTearDown(() async {
        if (!buildFinished) {
          build.kill(ProcessSignal.sigkill);
          await build.exitCode;
        }
      });
      final output = build.stdout.transform(systemEncoding.decoder).join();
      final errors = build.stderr.transform(systemEncoding.decoder).join();
      final buildCode = await build.exitCode.timeout(
        const Duration(minutes: 4),
      );
      buildFinished = true;
      expect(buildCode, 0, reason: '${await output}${await errors}');

      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      addTearDown(() => server.close(force: true));
      server.listen((request) async {
        final path = request.uri.path.substring(1);
        final served = serve(request.uri.path, '/', {
          if (File(p.join(out.path, path)).existsSync()) path,
        });
        if (served is! ServedFile) {
          request.response.statusCode = HttpStatus.notFound;
        } else {
          request.response.headers.set(
            HttpHeaders.contentTypeHeader,
            contentTypeOf(served.file),
          );
          await request.response.addStream(
            File(p.join(out.path, served.file)).openRead(),
          );
        }
        await request.response.close();
      });
      browser = await puppeteer.launch(
        executablePath:
            Platform.environment['CHROME'] ??
            '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome',
      );
      addTearDown(() => browser.close());
    });

    test(
      'resize changes cell counts while font and row height stay fixed',
      () async {
        final page = await browser.newPage();
        addTearDown(page.close);
        await page.evaluateOnNewDocument(clipboardStandIn);
        final errors = <String>[];
        page.onError.listen((error) => errors.add('$error'));
        page.onConsole.listen((message) {
          if (message.type == ConsoleMessageType.error) {
            errors.add(message.text ?? '');
          }
        });

        Future<void> size(int width, int height, num ratio) => page.setViewport(
          DeviceViewport(
            width: width,
            height: height,
            deviceScaleFactor: ratio,
          ),
        );

        Future<void> waitForGrid(int cols, int rows) async {
          await page.waitForFunction('''() => globalThis.chordTerminal &&
          chordTerminal.cols === $cols && chordTerminal.rows === $rows &&
          getComputedStyle(document.querySelector('#terminal'))
            .getPropertyValue('--term-font-size') === '12.5px' &&
          getComputedStyle(document.querySelector('#terminal'))
            .getPropertyValue('--term-row-height') === '16px' &&
          getComputedStyle(document.querySelector('#terminal'))
            .getPropertyValue('--term-line-height') === '1.28' &&
          getComputedStyle(document.querySelector('#terminal'))
            .letterSpacing === '-0.5px' ''');
        }

        Future<void> grid(int cols, int rows) async {
          try {
            await waitForGrid(cols, rows);
          } on TimeoutException {
            // Say what the page measured instead, so a failure names it.
            final seen = await page.evaluate<Object?>('''() => {
              const t = document.querySelector("#terminal");
              const css = getComputedStyle(t);
              return {
                viewport: [innerWidth, innerHeight, devicePixelRatio],
                cells: globalThis.chordTerminal
                  ? [chordTerminal.cols, chordTerminal.rows] : null,
                font: css.getPropertyValue("--term-font-size"),
                row: css.getPropertyValue("--term-row-height"),
                line: css.getPropertyValue("--term-line-height"),
                spacing: css.letterSpacing,
                fonts: document.fonts.status,
              };
            }''');
            fail('wanted ${cols}x$rows, the page has $seen');
          }
        }

        // wterm's own measure of the cell: a "W" in a hidden term row.
        // Chrome on macOS gives 7 px; on Linux it rounds the glyph's 7.5 px
        // advance up to the next 1/64 before the -0.5 px spacing (Q438).
        Future<double> cell() async {
          final width = await page.evaluate<num>('''() => {
            const row = document.createElement("div");
            row.className = "term-row";
            row.style.visibility = "hidden";
            row.style.position = "absolute";
            const probe = document.createElement("span");
            probe.style.width = "auto";
            probe.textContent = "W";
            row.appendChild(probe);
            document.querySelector("#terminal").appendChild(row);
            const width = probe.getBoundingClientRect().width;
            row.remove();
            return width;
          }''');
          return width.toDouble();
        }

        for (final ratio in [1, 2, 3]) {
          await size(1440, 900, ratio);
          // The gallery exercises the same grid without home's recording
          // asset requests, which have their own integration checks.
          await page.goto(
            'http://127.0.0.1:${server.port}/chord_tui/gallery',
            wait: Until.load,
          );
          expect(
            await page.evaluate<bool>(
              '() => navigator.clipboard.standIn === true',
            ),
            isTrue,
          );
          await grid(205, 56);
          // Measured once the page's fonts are in.
          final w = await cell();
          expect(w, inInclusiveRange(7, 7 + 1 / 64), reason: 'cell width');
          // Columns are whole cells across the window, as wterm counts them.
          int cols(int width) => (width / w).floor();
          await size(390, 844, ratio);
          await grid(55, 52);
          await size(360, 640, ratio);
          await grid(51, 40);
          await size(820, 1180, ratio);
          // 117 at 7 px, 116 at Linux's 7 + 1/64.
          await grid(cols(820), 73);
          await size(1440, 900, ratio);
          await grid(205, 56);
          await size(599, 600, ratio);
          await grid(85, 37);
          await size(600, 600, ratio);
          await grid(85, 37);
          // No density breakpoint: only a whole new cell adds a column,
          // at 602 px for 7 px cells and 604 px on Linux.
          final next = (86 * w).ceil();
          await size(next - 1, 600, ratio);
          await grid(85, 37);
          await size(next, 600, ratio);
          await grid(86, 37);
        }
        expect(errors, isEmpty);
      },
    );
  });
}
