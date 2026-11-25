// An app's terminal starts `open` or `xdg-open` detached and does not wait
// for it, as the original's `open` does when it does not wait for the app;
// one it cannot start is reported.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

const _url = 'https://example.com/a?b=c';

/// Runs the fixture with [path] as its only PATH, killing it if it has not
/// ended within [limit].
Future<({int exitCode, String stdout, String stderr})> _fixture(
  String path, {
  Duration limit = const Duration(seconds: 30),
}) async {
  final process = await Process.start(
    Platform.resolvedExecutable,
    ['test/fixtures/open_url_detached.dart', _url],
    environment: {'PATH': path},
  );
  final out = process.stdout.transform(utf8.decoder).join();
  final err = process.stderr.transform(utf8.decoder).join();
  final code = await process.exitCode.timeout(
    limit,
    onTimeout: () {
      process.kill(ProcessSignal.sigkill);
      return -1;
    },
  );
  return (exitCode: code, stdout: await out, stderr: await err);
}

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('open_url_detached');
  });
  tearDown(() {
    // Only the fake opener this case started, as it recorded itself, even
    // when the case failed before reading it.
    final started = File('${root.path}/started');
    final pid = int.tryParse(
      started.existsSync() ? started.readAsStringSync().split(' ').first : '',
    );
    if (pid != null && _alive(pid)) Process.killPid(pid);
    root.deleteSync(recursive: true);
  });

  test(
    'the opener is started and left running: openUrl returns before it ends',
    () async {
      final bin = Directory('${root.path}/bin')..createSync();
      final started = '${root.path}/started';
      final release = '${root.path}/release';
      for (final name in ['open', 'xdg-open']) {
        final fake = File('${bin.path}/$name')
          ..writeAsStringSync('''
#!/bin/sh
printf '%s %s\\n' "\$\$" "\$*" > '$started'
while [ ! -f '$release' ] && [ -d '${root.path}' ]; do /bin/sleep 0.05; done
''');
        Process.runSync('/bin/chmod', ['+x', fake.path]);
      }
      final result = await _fixture(bin.path);
      expect(result.exitCode, 0, reason: result.stderr);
      expect(result.stdout, 'said: null\n');
      // The fake has started, and still waits for its release.
      final file = File(started);
      final deadline = DateTime.now().add(const Duration(seconds: 10));
      String said() => file.existsSync() ? file.readAsStringSync() : '';
      while (!said().endsWith('\n') && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      final [pid, url] = said().trim().split(' ');
      final opener = int.parse(pid);
      expect(url, _url);
      expect(_alive(opener), isTrue);
      File(release).createSync();
      while (_alive(opener) && DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 20));
      }
      expect(_alive(opener), isFalse);
    },
    skip: Platform.isWindows ? 'open and xdg-open are POSIX openers' : false,
  );

  test('an opener that cannot be started is reported', () async {
    final empty = Directory('${root.path}/empty')..createSync();
    final result = await _fixture(empty.path);
    expect(result.exitCode, 0, reason: result.stderr);
    expect(result.stdout, startsWith('said: '));
    expect(result.stdout, isNot('said: null\n'));
  }, skip: Platform.isWindows ? 'open and xdg-open are POSIX openers' : false);
}
