import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('tester: benchmark CLI ownership', () {
    late Directory temp;
    late Directory scratch;
    setUp(() {
      temp = Directory.systemTemp.createTempSync('record-scan-cli-');
      scratch = Directory(p.join(temp.path, 'scratch'))..createSync();
    });
    tearDown(() => temp.deleteSync(recursive: true));

    Future<ProcessResult> run(
      List<String> flags, {
      Map<String, String> environment = const {},
    }) => Process.run(
      Platform.resolvedExecutable,
      [
        'run',
        'benchmark/record_scan.dart',
        if (!flags.any((flag) => flag.startsWith('--files='))) '--files=0',
        '--big-count=0',
        '--runs=1',
        ...flags,
      ],
      environment: {'TMPDIR': scratch.path, ...environment},
    );

    List<String> generated() => [
      for (final entry in scratch.listSync())
        if (p.basename(entry.path).startsWith('record_scan_')) entry.path,
    ];

    test('default temporary set is removed after a successful scan', () async {
      final result = await run([]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      expect(jsonDecode(result.stdout as String)['port']['records'], 0);
      expect(generated(), isEmpty);
    });

    test(
      'explicit generated directory survives reuse with identical bytes',
      () async {
        final state = p.join(temp.path, 'state');
        final flags = ['--dir=$state', '--files=1'];
        final first = await run(flags);
        expect(first.exitCode, 0, reason: '${first.stderr}');
        Map<String, List<int>> snapshot() => {
          for (final entry in Directory(state).listSync(recursive: true))
            if (entry is File)
              p.relative(entry.path, from: state): entry.readAsBytesSync(),
        };
        final before = snapshot();
        final second = await run(flags);
        expect(second.exitCode, 0, reason: '${second.stderr}');
        expect(second.stderr, contains('reusing the generated set'));
        expect(snapshot(), before);
        expect(generated(), isEmpty);
      },
    );
  });
}
