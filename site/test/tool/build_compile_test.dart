@Tags(['compile'])
// Covers the build, which takes no timeout of its own.
@Timeout(Duration(minutes: 6))
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/build.dart';

// CHD-638: `build.dart build` writes the whole site: the page with its base,
// the app, wterm, the font and the recordings, every page URL relative, and
// nothing a host does not serve.
void main() {
  late ProcessResult run;
  late Set<String> files;

  setUpAll(() async {
    run = await Process.run(Platform.resolvedExecutable, [
      'run',
      'tool/build.dart',
      'build',
      '--base=/chord/',
    ]);
    files = {
      for (final file in Directory('build').listSync(recursive: true))
        if (file is File) p.relative(file.path, from: 'build'),
    };
  });

  test('the build succeeds', () {
    expect(run.exitCode, 0, reason: '${run.stdout}${run.stderr}');
    expect(run.stdout, contains(RegExp(r'build: site/build/, \d+ recordings')));
  });

  test('it holds the page, the app, wterm, the font and the recordings', () {
    for (final file in [
      'index.html',
      'main.wasm',
      'main.mjs',
      'wterm/dom/dist/index.js',
      'wterm/dom/src/terminal.css',
      'wterm/core/dist/index.js',
      'fonts/regular.woff2',
      'fonts/bold.woff2',
      'fonts/OFL.txt',
    ]) {
      expect(files, contains(file));
    }
    final shots = recordedShots(
      Directory('../docs/images').listSync().map((f) => p.basename(f.path)),
    );
    for (final shot in shots) {
      for (final size in shotSizes) {
        expect(files, contains('recordings/$shot.$size.rec.json'));
      }
    }
    expect(
      files.where((f) => f.endsWith('.map') || f.endsWith('.d.ts')),
      isEmpty,
    );
  });

  test('the page has its base, and every module it imports is shipped', () {
    final page = File('build/index.html').readAsStringSync();
    expect(page, contains('<base href="/chord/">'));
    // Each relative import in wterm's modules names a shipped file.
    for (final module in files.where(
      (f) => f.startsWith('wterm/') && f.endsWith('.js'),
    )) {
      final source = File(p.join('build', module)).readAsStringSync();
      for (final m in RegExp(
        r'''from\s*["'](\.[^"']+)["']|import\(\s*["'](\.[^"']+)["']''',
      ).allMatches(source)) {
        final target = p.normalize(p.join(p.dirname(module), m[1] ?? m[2]));
        expect(files, contains(target), reason: '$module imports $target');
      }
    }
  });

  test(
    '--out builds into its own folder and leaves site/build/ alone',
    () async {
      final out = Directory.systemTemp.createTempSync('chord_site_out_');
      addTearDown(() => out.deleteSync(recursive: true));
      // A file only site/build/ has: another build there would remove it.
      final mark = File(p.join('build', 'kept.txt'))..writeAsStringSync('');
      addTearDown(() {
        if (mark.existsSync()) mark.deleteSync();
      });
      final other = await Process.run(Platform.resolvedExecutable, [
        'run',
        'tool/build.dart',
        'build',
        '--out=${out.path}',
      ]);
      expect(other.exitCode, 0, reason: '${other.stdout}${other.stderr}');
      expect(other.stdout, contains('build: ${out.path}, '));
      expect(
        File(p.join(out.path, 'index.html')).readAsStringSync(),
        contains('<base href="/">'),
      );
      expect(File(p.join(out.path, 'main.wasm')).existsSync(), isTrue);
      expect(mark.existsSync(), isTrue);
      expect(
        File('build/index.html').readAsStringSync(),
        contains('<base href="/chord/">'),
      );
    },
  );
}
