@Tags(['compile'])
@TestOn('posix')
library;

import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:test/test.dart';

// Compiled, a limits read starts `claude` through chord's own binary as its
// group launcher: this builds the probe, runs it from `/` with an empty
// HOME, against the recording fake `claude`, and checks the answer and
// that the fake heard both control requests.
void main() {
  late Directory dir;
  late String probe;

  String source(String path) => Isolate.resolvePackageUriSync(
    Uri.parse('package:chord/platform/resource_worker.dart'),
  )!.resolve('../../$path').toFilePath();

  setUpAll(() async {
    dir = Directory.systemTemp.createTempSync('chord-aot-usage-');
    Directory('${dir.path}/home').createSync();
    probe = '${dir.path}/probe';
    final build = await Process.run(Platform.resolvedExecutable, [
      'compile',
      'exe',
      source('test/fixtures/resource_read_probe.dart'),
      '-o',
      probe,
    ]);
    expect(build.exitCode, 0, reason: '${build.stdout}${build.stderr}');
  });
  tearDownAll(() => dir.deleteSync(recursive: true));

  test("a compiled reader speaks claude's usage wire through its own "
      'launcher', () async {
    final claude = File('${dir.path}/claude')
      ..writeAsStringSync(
        "#!/bin/sh\nexec '${Platform.resolvedExecutable}' "
        "'${source('test/fixtures/claude_usage_fake.dart')}' \"\$@\"\n",
      );
    Process.runSync('chmod', ['+x', claude.path]);
    final record = '${dir.path}/record.jsonl';
    final result = await Process.run(
      probe,
      [claude.path, record],
      workingDirectory: '/',
      environment: {
        'HOME': '${dir.path}/home',
        'PATH': Platform.environment['PATH']!,
      },
      includeParentEnvironment: false,
    ).timeout(const Duration(seconds: 60));
    expect(result.exitCode, 0, reason: '${result.stderr}');
    expect(jsonDecode(result.stdout as String), {
      'agent': 'claude',
      'windows': [
        {
          'name': 'five_hour',
          'usedPercent': 1,
          'windowSeconds': 18000,
          'resetsAt': null,
          'models': null,
        },
      ],
    });
    expect(
      [
        for (final line in File(record).readAsLinesSync().skip(1))
          (jsonDecode(line) as Map)['request']['subtype'],
      ],
      ['initialize', 'get_usage'],
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}
