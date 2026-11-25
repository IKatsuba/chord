@TestOn('posix')
library;

import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/genai_prices.dart';

void main() {
  late Directory root;
  late String package;
  late String out;
  setUp(() {
    root = Directory.systemTemp.createTempSync('genai_prices_test');
    addTearDown(() => root.deleteSync(recursive: true));
    package = p.join(root.path, 'genai-prices');
    out = p.join(root.path, 'price_data.dart');
  });

  void installed(String version) => (File(
    p.join(package, 'package.json'),
  )..createSync(recursive: true)).writeAsStringSync('{"version": "$version"}');

  /// A node that records its arguments and prints [stdout].
  String node(String stdout, {int exitCode = 0}) {
    final file = File(p.join(root.path, 'node'))
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'printf "%s\\n" "\$@" > "${p.join(root.path, 'argv')}"\n'
        "printf '%s' '$stdout'\n"
        'echo "node failed" >&2\n'
        'exit $exitCode\n',
      );
    Process.runSync('chmod', ['+x', file.path]);
    return file.path;
  }

  test('reads the package with node and keeps only what pricing reads', () async {
    installed(pinned);
    final code = await generatePrices(
      package: package,
      out: out,
      node: node(
        '{"units":{"a":1},"providers":[{"id":"x","name":"X","models":'
        '[{"id":"m","name":"M","match":{"equals":"m"},"prices":{"input_mtok":1}}]}]}',
      ),
    );
    expect(code, 0);
    final argv = File(p.join(root.path, 'argv')).readAsLinesSync();
    expect(p.extension(argv.first), '.mjs');
    expect(argv.last, package);
    final written = File(out).readAsStringSync();
    expect(written, contains('@pydantic/genai-prices $pinned'));
    expect(
      written,
      contains(
        '{"units":{"a":1},"providers":[{"id":"x","models":'
        '[{"id":"m","match":{"equals":"m"},"prices":{"input_mtok":1}}]}]}',
      ),
    );
  });

  test('another version is refused, nothing written', () async {
    installed('0.2.4');
    expect(
      await generatePrices(package: package, out: out, node: node('{}')),
      1,
    );
    expect(File(out).existsSync(), isFalse);
  });

  test('no package there is refused, nothing written', () async {
    expect(
      await generatePrices(package: package, out: out, node: node('{}')),
      1,
    );
    expect(File(out).existsSync(), isFalse);
  });

  test('node failing is refused, nothing written', () async {
    installed(pinned);
    expect(
      await generatePrices(
        package: package,
        out: out,
        node: node('', exitCode: 3),
      ),
      1,
    );
    expect(File(out).existsSync(), isFalse);
  });

  test('without --package it says how to run it', () {
    final run = Process.runSync(Platform.resolvedExecutable, [
      'run',
      'tool/genai_prices.dart',
    ]);
    expect(run.exitCode, 64);
    expect(run.stderr, contains('--package <dir>'));
  });
}
