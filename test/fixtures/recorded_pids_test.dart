import 'dart:convert';
import 'dart:io';

import 'package:chord/platform/process.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'recorded_pids.dart';

bool _runs(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  late Directory dir;
  late File script;
  final started = <GroupProcess>[];

  setUp(() {
    dir = Directory.systemTemp.createTempSync('chord-recorded-pids-');
    script = File(p.join(dir.path, 'stubborn_provider'))
      ..writeAsStringSync(
        "#!/bin/sh\ntrap '' TERM\n"
        "sh -c \"trap '' TERM; sleep 30\" &\n"
        'echo \$! > "\$1"\nwait\n',
      );
    Process.runSync('chmod', ['+x', script.path]);
    addTearDown(() async {
      for (final group in started) {
        group.signal(ProcessSignal.sigkill);
        await group.exit.then((_) {}, onError: (_) {});
      }
      started.clear();
      dir.deleteSync(recursive: true);
    });
  });

  /// The stubborn provider, leading a group of its own as a reader starts
  /// it, working in [cwd], and the pid of what it started.
  Future<(GroupProcess, int)> provider(String name, String cwd) async {
    final descendantFile = File(p.join(dir.path, name));
    final group = await spawnGroup(script.path, [
      descendantFile.path,
    ], cwd: cwd);
    started.add(group);
    while (!descendantFile.existsSync() ||
        descendantFile.readAsStringSync().isEmpty) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return (group, int.parse(descendantFile.readAsStringSync().trim()));
  }

  String record(List<int> pids, [List<int> descendants = const []]) =>
      (File(p.join(dir.path, 'events.jsonl'))..writeAsStringSync(
            [
              for (final pid in pids) jsonEncode({'pid': pid}),
              for (final pid in descendants) jsonEncode({'descendant': pid}),
              '{"cut off',
            ].join('\n'),
          ))
          .path;

  test('a recorded provider of this run that shrugs off SIGTERM is killed '
      'with its group; one of the same script from another run, and a pid '
      'running something else, are not', () async {
    final (ours, descendant) = await provider('ours', dir.path);
    final (theirs, _) = await provider(
      'theirs',
      (Directory(p.join(dir.path, 'another-run'))..createSync()).path,
    );
    final other = await Process.start('sleep', ['30']);
    addTearDown(() => other.kill(ProcessSignal.sigkill));

    await killRecordedProviders(
      File(record([ours.pid, theirs.pid, other.pid], [descendant])),
      dir.path,
    );

    expect((await ours.exit).signal, 'SIGKILL');
    expect(ours.alive(), isFalse, reason: 'its group is gone');
    expect(_runs(descendant), isFalse);
    expect(theirs.alive(), isTrue, reason: 'another run works elsewhere');
    expect(_runs(other.pid), isTrue, reason: 'it works elsewhere');
  });

  test('a provider still there after the wait fails the cleanup, '
      'naming it', () async {
    final (ours, _) = await provider('ours', dir.path);

    await expectLater(
      killRecordedProviders(
        File(record([ours.pid])),
        dir.path,
        kill: (_) {},
        within: const Duration(milliseconds: 200),
      ),
      throwsA(
        isA<StateError>().having(
          (e) => e.message,
          'message',
          'Recorded providers outlived their kill: ${ours.pid}',
        ),
      ),
    );
    expect(ours.alive(), isTrue);
  });
}
