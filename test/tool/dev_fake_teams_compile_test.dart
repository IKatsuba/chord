// Tester CTUI-117: the original team safely refuses its unsupported model;
// a staged team with real runtime names starts fake lead/member processes.
@Tags(['compile', 'fake_agent'])
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/dev.dart' show shellWord;
import '../fixtures/fake.dart';
import '../fixtures/native_smoke_cleanup.dart';

const _routingTeam = '''
---
description: Proves fake-only routing with real runtime names.
lead:
  agent: claude
  model: fake-large
  instructions: Open tester and coder and report their results.
members:
  - name: tester
    role: Checks the job
    agent: codex
    model: fake-large
    instructions: Report the test result to the lead.
  - name: coder
    role: Reads the implementation
    agent: claude
    model: fake-large
    instructions: Read the job and wait for the lead.
---

# Routing proof

The lead coordinates tester and coder.
''';

String _tcl(String value) =>
    '[encoding convertfrom utf-8 [binary format H* {'
    '${utf8.encode(value).map((b) => b.toRadixString(16).padLeft(2, '0')).join()}'
    '}]]';

Future<List<({int pid, int parent, int group, String command})>>
_processes() async {
  final result = await Process.run('ps', [
    '-A',
    '-o',
    'pid=,ppid=,pgid=,command=',
  ]);
  expect(result.exitCode, 0, reason: '${result.stderr}');
  return [
    for (final line in const LineSplitter().convert('${result.stdout}'))
      if (RegExp(r'^\s*(\d+)\s+(\d+)\s+(\d+)\s+(.+)$').firstMatch(line)
          case final match?)
        (
          pid: int.parse(match[1]!),
          parent: int.parse(match[2]!),
          group: int.parse(match[3]!),
          command: match[4]!,
        ),
  ];
}

void main() {
  late List<String> fake;
  late String fakeSnapshot;
  final skip = !File('/usr/bin/expect').existsSync()
      ? 'POSIX expect is required'
      : fakeAgent.reason ?? false;
  late Directory build;
  late String binary;

  group('tester CTUI-117: saved team uses fake processes', () {
    setUpAll(() async {
      fake = fakeAgentCommand(null, ['--step-ms', '0']);
      fakeSnapshot = fake[1];
      build = Directory.systemTemp.createTempSync('chord-dev-team-build-');
      binary = p.join(build.path, 'chord');
      final result = await Process.run('nice', [
        '-n',
        '19',
        Platform.resolvedExecutable,
        'compile',
        'exe',
        '-DCHORD_RESOURCE_FIXTURE=true',
        '-DCHORD_FAKE_RUNTIMES=true',
        'bin/chord.dart',
        '-o',
        binary,
      ]);
      expect(result.exitCode, 0, reason: '${result.stdout}${result.stderr}');
    });
    tearDownAll(() => build.deleteSync(recursive: true));

    for (final (columns, rows) in [(120, 40), (80, 24)]) {
      for (final originalModels in [true, false]) {
        test(
          'team runtime names stay fake at ${columns}x$rows, original models: $originalModels',
          () async {
            final root = Directory(
              p.join(build.path, '$columns-$originalModels'),
            )..createSync();
            final project = Directory(p.join(root.path, 'project'))
              ..createSync();
            final state = Directory(p.join(root.path, 'state'))..createSync();
            final tools = Directory(p.join(root.path, 'bin'))..createSync();
            Link(
              p.join(tools.path, 'dart'),
            ).createSync(Platform.resolvedExecutable);
            Link(p.join(tools.path, 'sh')).createSync('/bin/sh');
            Link(p.join(tools.path, 'stty')).createSync('/bin/stty');
            final team = File(
              p.join(project.path, '.chord', 'teams', 'bugfix.md'),
            )..createSync(recursive: true);
            if (originalModels) {
              team.writeAsBytesSync(
                File(
                  p.join(
                    portPackageDir(),
                    'test',
                    'fixtures',
                    'teams',
                    'bugfix.md',
                  ),
                ).readAsBytesSync(),
              );
            } else {
              team.writeAsStringSync(_routingTeam);
            }
            final env = {
              'HOME': p.join(root.path, 'home'),
              'XDG_CONFIG_HOME': p.join(root.path, 'config'),
              'XDG_STATE_HOME': state.path,
              'TMPDIR': root.path,
              'PATH': tools.path,
              'CHORD_FAKE_CHILD_RUNTIME': 'fake',
              'TERM': 'xterm-256color',
              'NO_COLOR': '1',
            };
            expect(
              tools.listSync().map((f) => p.basename(f.path)),
              unorderedEquals(['dart', 'sh', 'stty']),
            );
            final refused = await Process.run(
              binary,
              ['claude'],
              workingDirectory: project.path,
              environment: env,
              includeParentEnvironment: false,
            );
            expect(refused.exitCode, 1);
            expect(
              refused.stderr,
              contains('this chord starts only the fake agent'),
            );

            final pidFile = File(p.join(root.path, 'window.pid'));
            final done = File(p.join(root.path, 'done'));
            final command = [
              binary,
              'fake',
              '--agent-command',
              fake.map(shellWord).join(' '),
              '-C',
              project.path,
            ];
            final script = File(p.join(root.path, 'team.exp'))
              ..writeAsStringSync('''
set timeout 30
spawn -noecho {*}[list ${command.map(_tcl).join(' ')}]
set pidfile [open ${_tcl(pidFile.path)} w]
puts \$pidfile [exp_pid]
close \$pidfile
stty rows $rows columns $columns < \$spawn_out(slave,name)
expect {
  -exact "Fake Large" {}
  timeout {exit 90}
  eof {exit 91}
}
send -- "/team run bugfix Fix the quote.\\r"
set deadline [expr {[clock milliseconds] + 45000}]
while {![file exists ${_tcl(done.path)}]} {
  if {[clock milliseconds] > \$deadline} {exit 92}
  expect -timeout 1 {
    -re {.+} {}
    eof {exit 93}
  }
}
close
catch wait result
puts "TEAM_DRIVER_DONE=\$result"
''');
            final driver = await Process.start(
              '/usr/bin/expect',
              [script.path],
              workingDirectory: project.path,
              environment: env,
              includeParentEnvironment: false,
            );
            final output = StringBuffer();
            driver.stdout.transform(utf8.decoder).listen(output.write);
            driver.stderr.transform(utf8.decoder).listen(output.write);
            final owned = <int>{};
            Future<List<String>> snapshot() async {
              final list = await _processes();
              final pids = {driver.pid};
              var changed = true;
              while (changed) {
                changed = false;
                for (final process in list) {
                  if (pids.contains(process.parent) && pids.add(process.pid)) {
                    changed = true;
                  }
                }
              }
              owned.addAll(
                list.where((v) => pids.contains(v.pid)).map((v) => v.group),
              );
              // The test runner's group is never ours to signal.
              owned.removeWhere(
                (group) => list.any((v) => v.pid == pid && v.group == group),
              );
              return [
                for (final v in list)
                  if (pids.contains(v.pid) && v.pid != driver.pid) v.command,
              ];
            }

            addTearDown(() async {
              await snapshot();
              if (pidFile.existsSync()) {
                owned.add(int.parse(pidFile.readAsStringSync()));
              }
              await cleanupNativeSmoke(driver: driver, groupIds: () => owned);
            });

            final expected = {
              'bugfix': 'claude',
              'tester': 'codex',
              'coder': 'claude',
            };
            final found = <String, String>{};
            const refusal =
                'bugfix (claude) did not start: Bad state: '
                'Could not start on opus, set by team bugfix: '
                'the agent offers fake-large, fake-small.';
            var saidRefusal = false;
            final deadline = DateTime.now().add(const Duration(seconds: 40));
            while (DateTime.now().isBefore(deadline) &&
                !(originalModels
                    ? saidRefusal
                    : found.length == expected.length)) {
              for (final file
                  in state.listSync(recursive: true).whereType<File>()) {
                if (!file.path.endsWith('.jsonl')) continue;
                final entries = <Map<String, dynamic>>[];
                for (final line in const LineSplitter().convert(
                  file.readAsStringSync(),
                )) {
                  try {
                    if (jsonDecode(line)
                        case final Map<String, dynamic> value) {
                      entries.add(value);
                    }
                  } on FormatException {
                    /* An in-progress final line is not ready. */
                  }
                }
                saidRefusal =
                    saidRefusal ||
                    entries.any(
                      (v) =>
                          v['type'] == 'prompt' &&
                          '${v['prompt']}'.contains(refusal),
                    );
                if (!entries.any((v) => v['type'] == 'prompt')) continue;
                for (final entry in entries) {
                  if (entry['type'] == 'session' &&
                      expected.containsKey(entry['name'])) {
                    found[entry['name'] as String] = entry['agent'] as String;
                  }
                }
              }
              await snapshot();
              if (found.length < expected.length) {
                await Future<void>.delayed(const Duration(milliseconds: 20));
              }
            }
            if (originalModels) {
              expect(saidRefusal, isTrue, reason: '$output');
              expect(found, isEmpty);
            } else {
              expect(found, expected, reason: '$output');
            }
            final commands = await snapshot();
            expect(
              commands.every(
                (c) => c.startsWith(binary) || c.contains(fakeSnapshot),
              ),
              isTrue,
              reason: '$commands',
            );
            final fakes = commands
                .where((c) => c.contains(fakeSnapshot) && !c.startsWith(binary))
                .toList();
            expect(
              fakes.length,
              greaterThanOrEqualTo(originalModels ? 1 : 4),
              reason: '$commands',
            );
            expect(
              commands.where(
                (c) =>
                    c.contains('claude-agent-acp') ||
                    c.contains('codex-acp') ||
                    c.contains('npx '),
              ),
              isEmpty,
            );
            done.writeAsStringSync('done');
            expect(
              await driver.exitCode.timeout(const Duration(seconds: 15)),
              0,
              reason: '$output',
            );
            expect('$output', contains('TEAM_DRIVER_DONE='));
          },
          timeout: const Timeout(Duration(minutes: 2)),
        );
      }
    }
  }, skip: skip);
}
