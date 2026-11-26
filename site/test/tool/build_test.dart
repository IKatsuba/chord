import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:test/test.dart';

import 'package:chord_site/screens.dart';

import '../../tool/build.dart';

void main() {
  _lengths();
  test('a pinned file matches only its own digest', () {
    final bytes = utf8.encode('wterm');
    final npm = Pinned(
      name: 'x.tgz',
      url: 'https://example.invalid/x.tgz',
      algorithm: 'sha512',
      digest: base64.encode(sha512.convert(bytes).bytes),
    );
    final zip = Pinned(
      name: 'x.zip',
      url: 'https://example.invalid/x.zip',
      algorithm: 'sha256',
      digest: sha256.convert(bytes).toString(),
    );
    expect(npm.matches(bytes), isTrue);
    expect(zip.matches(bytes), isTrue);
    expect(npm.matches(utf8.encode('other')), isFalse);
    expect(zip.matches(utf8.encode('other')), isFalse);
  });

  test('the pins are wterm 0.6.0 from npm and JetBrains Mono 2.304', () {
    expect(wtermDom.url, endsWith('/@wterm/dom/-/dom-0.6.0.tgz'));
    expect(wtermCore.url, endsWith('/@wterm/core/-/core-0.6.0.tgz'));
    expect(jetBrainsMono.url, contains('JetBrains/JetBrainsMono/releases'));
    expect(fontFiles.values, [
      'fonts/regular.woff2',
      'fonts/bold.woff2',
      'fonts/OFL.txt',
    ]);
  });

  test('the page gets its base, and nothing else changes', () {
    final template = File('web/index.html').readAsStringSync();
    final page = pageFor(template, '/chord/');
    expect(page, contains('<base href="/chord/">'));
    expect(page, isNot(contains('<base href="/">')));
    expect(page.length, template.length + '/chord/'.length - 1);
    expect(pageFor(template, '/'), template);
  });

  test('every URL the page loads is relative, so the base resolves it', () {
    final template = File('web/index.html').readAsStringSync();
    final urls = [
      for (final m in RegExp(
        r'''(?:href|src)="([^"]+)"|url\("([^"]+)"\)|import\("([^"]+)"\)|fetch\("([^"]+)"\)|"(\./[^"]+)"''',
      ).allMatches(template))
        [for (var i = 1; i <= 5; i++) m[i]].whereType<String>().first,
    ];
    expect(urls, isNotEmpty);
    for (final url in urls) {
      if (url == '/' || url.startsWith('https://') || url.startsWith('data:')) {
        continue;
      }
      expect(url, isNot(startsWith('/')), reason: url);
    }
  });

  test('a shot is shipped when it was recorded at all three sizes', () {
    expect(
      recordedShots([
        'team.120x36.rec.json',
        'team.80x20.rec.json',
        'team.48x32.rec.json',
        'fork.120x36.rec.json',
        'fork.80x20.rec.json',
        'edit.120x36.rec.json',
        'start.80x20.rec.json',
        'notes.txt',
      ]),
      ['team'],
    );
  });

  test("chord's version comes from the root pubspec", () {
    expect(chordVersionOf('name: chord\nversion: 0.72.2\n'), '0.72.2');
    expect(
      chordVersionOf(File('../pubspec.yaml').readAsStringSync()),
      matches(RegExp(r'^\d+\.\d+\.\d+')),
    );
    expect(() => chordVersionOf('name: x\n'), throwsStateError);
  });

  test("wterm's modules, stylesheet and licence ship; types and maps not", () {
    expect(wtermFileShipped('package/dist/index.js'), isTrue);
    expect(wtermFileShipped('package/src/terminal.css'), isTrue);
    expect(wtermFileShipped('package/LICENSE'), isTrue);
    expect(wtermFileShipped('package/dist/index.d.ts'), isFalse);
    expect(wtermFileShipped('package/dist/index.js.map'), isFalse);
    expect(wtermFileShipped('package/wasm/wterm.wasm'), isFalse);
  });
}

void _lengths() {
  test('each shot goes in with its paced length, rounded up to a second', () {
    String recording(int lastMs) => jsonEncode({
      'version': 1,
      'cols': 120,
      'rows': 36,
      'frames': [
        {
          'at': 0,
          'rows': ['a'],
          'label': null,
        },
        {
          'at': lastMs,
          'rows': ['b'],
          'label': null,
        },
      ],
    });
    expect(
      shotsWithLengths([
        'start',
        'team',
      ], (shot) => shot == 'start' ? recording(8200) : recording(12000)),
      'start:9,team:12',
    );
    expect(parseShot('start:9'), ('start', const Duration(seconds: 9)));
    expect(parseShot('start'), ('start', null));
  });
}
