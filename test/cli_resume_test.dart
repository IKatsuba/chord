import 'dart:async';
import 'package:chord/ui/start.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord/cli.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/launch_connection.dart';
import 'package:test/test.dart';

import 'session/recording_start_test.dart' show connected;
import 'session/reopen_session_test.dart' as memory;

SessionRecord saved(
  String id, {
  String agent = 'claude',
  String cwd = 'project',
  num at = 1,
  String? parent,
}) => SessionRecord(
  path: 'records/$id.jsonl',
  sessionId: id,
  agent: agent,
  cwd: cwd,
  lastUsedAt: at,
  prompt: 'saved $id',
  parent: parent,
);

Future<CliOutcome> call(
  List<String> args, {
  List<SessionRecord> records = const [],
  StringBuffer? error,
  bool tty = false,
  PickStartupResume? pick,
  Future<List<SessionRecord>> Function()? read,
  PickStartupAgent? pickAgent,
}) => runCli(
  args,
  stdout: StringBuffer(),
  stderr: error ?? StringBuffer(),
  cwd: 'project',
  home: null,
  stdinTTY: tty,
  stdoutTTY: tty,
  lookup: (_) async => 'found',
  readSessionRecords: read ?? () async => records,
  pickResume: pick,
  pickAgent: pickAgent,
);

void main() {
  test(
    'resume refusals and picker cancellation precede missing executable checks',
    () async {
      for (final (args, tty, records, cancel, expected) in [
        (
          ['-r'],
          false,
          <SessionRecord>[],
          false,
          '--resume needs an id when not in a terminal',
        ),
        (['-r'], true, [saved('known')], true, null),
        (
          ['-r'],
          true,
          <SessionRecord>[],
          false,
          'No earlier claude session to resume.',
        ),
        (
          ['-c'],
          false,
          <SessionRecord>[],
          false,
          'No earlier claude session in project to continue.',
        ),
        (
          ['claude', '-r', 'known'],
          false,
          [saved('known', agent: 'codex')],
          false,
          'Session known belongs to another agent (codex).',
        ),
      ]) {
        final errors = StringBuffer();
        var lookups = 0, picks = 0, reads = 0;
        final outcome = await runCli(
          args,
          stdout: StringBuffer(),
          stderr: errors,
          cwd: 'project',
          home: null,
          stdinTTY: tty,
          stdoutTTY: tty,
          lookup: (_) async {
            lookups++;
            return null;
          },
          readSessionRecords: () async {
            reads++;
            return records;
          },
          pickResume:
              ({
                required sessions,
                required agent,
                required version,
                required directory,
                required cwd,
                required home,
              }) async {
                picks++;
                return null;
              },
        );
        expect(outcome.code, cancel ? 0 : 2, reason: args.toString());
        expect(outcome.launch, isNull);
        expect(lookups, 0);
        expect(picks, cancel ? 1 : 0);
        expect(reads, tty || args.length > 1 || args.first == '-c' ? 1 : 0);
        expect('$errors', expected == null ? isEmpty : contains(expected));
      }
      var lookups = 0;
      final newStart = await runCli(
        [],
        stdout: StringBuffer(),
        stderr: StringBuffer(),
        cwd: 'project',
        home: null,
        lookup: (_) async {
          lookups++;
          return null;
        },
        readSessionRecords: () async => throw StateError('new start scanned'),
      );
      expect(newStart.code, 1);
      expect(newStart.launch, isNull);
      expect(lookups, greaterThan(0));
    },
  );
  for (final args in [
    ['-cc'],
    ['-hc'],
    ['-ch'],
    ['-Vc'],
    ['-cV'],
    ['-hhc'],
  ]) {
    test(
      'cluster refusal never scans, picks, or produces a new launch $args',
      () async {
        var reads = 0, lookups = 0, picks = 0;
        final outcome = await runCli(
          args,
          stdout: StringBuffer(),
          stderr: StringBuffer(),
          cwd: 'project',
          home: null,
          stdinTTY: true,
          stdoutTTY: true,
          lookup: (_) async {
            lookups++;
            return 'found';
          },
          readSessionRecords: () async {
            reads++;
            return [saved('known')];
          },
          pickAgent:
              ({
                required agents,
                required version,
                required directory,
                required preferred,
                required offered,
              }) async {
                picks++;
                return 'claude';
              },
        );
        expect(outcome.code, 2);
        expect(outcome.launch, isNull);
        expect(reads, 0);
        expect(lookups, 0);
        expect(picks, 0);
      },
    );
  }

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final (keys, id) in [
      ('\r', 'local'),
      ('\x1b', null),
      ('\x03', null),
      ('\x01\r', 'remote'),
      ('\x01\x031', null),
      ('12', 'local'),
    ]) {
      test(
        'actual resume startup flow restores terminal once $size ${keys.codeUnits}',
        () async {
          final terminal = ResumeTerminal(size)..keys = keys;
          try {
            final outcome = await call(
              ['-r'],
              tty: true,
              records: [
                saved('remote', cwd: 'other', at: 3),
                saved('local', at: 2),
              ],
              pick:
                  ({
                    required sessions,
                    required agent,
                    required version,
                    required directory,
                    required cwd,
                    required home,
                  }) => selectStartupResume(
                    sessions: sessions,
                    agent: agent,
                    version: version,
                    directory: directory,
                    cwd: cwd,
                    home: home,
                    terminal: terminal,
                    environment: const {'NO_COLOR': '1'},
                  ),
            ).timeout(const Duration(seconds: 5));
            expect(outcome.launch?.resume?.sessionId, id);
            expect(terminal.entered, 1);
            expect(terminal.left, 1);
            expect(terminal.output.toString(), contains('Resume a session'));
          } finally {
            await terminal.events.close();
          }
        },
      );
    }
  }

  test(
    'known id supplies own agent and directory from exactly one shared scan',
    () async {
      var scans = 0;
      final outcome = await call(
        ['--resume', 'saved'],
        tty: true,
        read: () async {
          scans++;
          return [saved('saved', agent: 'codex', cwd: 'other')];
        },
        pickAgent:
            ({
              required agents,
              required version,
              required directory,
              required preferred,
              required offered,
            }) async => throw StateError('resume must skip agent picker'),
      );
      expect(scans, 1);
      expect(outcome.launch?.name, 'codex');
      expect(outcome.launch?.directory, 'other');
      expect(outcome.launch?.resume?.cwd, 'other');
      expect(outcome.launch?.resume?.record, 'records/saved.jsonl');
    },
  );
  test('unknown id keeps selected default agent and invocation cwd', () async {
    final outcome = await call(['--resume', 'unknown']);
    expect(outcome.launch?.name, 'claude');
    expect(outcome.launch?.resume?.sessionId, 'unknown');
    expect(outcome.launch?.resume?.cwd, 'project');
    expect(outcome.launch?.resume?.record, isNull);
  });
  for (final args in [
    ['claude', '--resume', 'known'],
    ['--agent-command', 'memory', '--resume', 'known'],
  ]) {
    test(
      'explicit agent or unnamed override keeps ownership refusal $args',
      () async {
        final err = StringBuffer();
        final outcome = await call(
          args,
          records: [saved('known', agent: 'codex')],
          error: err,
        );
        expect(outcome.code, 2);
        expect(outcome.launch, isNull);
        expect(
          '$err',
          contains('Session known belongs to another agent (codex).'),
        );
      },
    );
  }
  test(
    'continue uses exact local main latest and skips both startup pickers',
    () async {
      final outcome = await call(
        ['-c'],
        tty: true,
        records: [
          saved('child', at: 9, parent: 'main'),
          saved('remote', at: 8, cwd: 'other'),
          saved('other-agent', at: 7, agent: 'codex'),
          saved('older'),
          saved('newest', at: 2.5),
        ],
        pickAgent:
            ({
              required agents,
              required version,
              required directory,
              required preferred,
              required offered,
            }) async => throw StateError('picked'),
        pick:
            ({
              required sessions,
              required agent,
              required version,
              required directory,
              required cwd,
              required home,
            }) async => throw StateError('picked'),
      );
      expect(outcome.launch?.resume?.sessionId, 'newest');
      expect(outcome.launch?.resume?.lastUsedAt, 2.5);
    },
  );
  test('continue and picker have original distinct empty refusals', () async {
    final local = StringBuffer(), global = StringBuffer();
    expect((await call(['-c'], error: local)).launch, isNull);
    expect(
      '$local',
      contains('No earlier claude session in project to continue.'),
    );
    expect((await call(['-r'], tty: true, error: global)).launch, isNull);
    expect('$global', contains('No earlier claude session to resume.'));
  });
  test('nonterminal bare resume refuses before scan or picker', () async {
    final err = StringBuffer();
    final outcome = await call(
      ['-r'],
      error: err,
      read: () async => throw StateError('scanned'),
    );
    expect(outcome.code, 2);
    expect(outcome.launch, isNull);
    expect('$err', contains('--resume needs an id when not in a terminal'));
  });
  test(
    'startup list has all directories once and cancel returns no launch',
    () async {
      var scans = 0, picks = 0;
      final outcome = await call(
        ['-r'],
        tty: true,
        read: () async {
          scans++;
          return [saved('remote', cwd: 'other'), saved('local', at: 2)];
        },
        pick:
            ({
              required sessions,
              required agent,
              required version,
              required directory,
              required cwd,
              required home,
            }) async {
              picks++;
              expect(sessions.map((s) => s.resume.sessionId), [
                'local',
                'remote',
              ]);
              expect(agent, 'claude');
              expect(cwd, 'project');
              return null;
            },
      );
      expect(scans, 1);
      expect(picks, 1);
      expect(outcome.code, 0);
      expect(outcome.launch, isNull);
    },
  );
  test(
    'startup accepts another directory and retains same discovery snapshot',
    () async {
      var scans = 0;
      final outcome = await call(
        ['--resume'],
        tty: true,
        read: () async {
          scans++;
          return [saved('remote', cwd: 'other')];
        },
        pick:
            ({
              required sessions,
              required agent,
              required version,
              required directory,
              required cwd,
              required home,
            }) async => sessions.single,
      );
      expect(scans, 1);
      expect(outcome.launch?.resume?.cwd, 'other');
      expect(outcome.launch?.directory, 'other');
    },
  );
  test('informational and invalid calls never resolve state or scan', () async {
    for (final args in [
      ['--help'],
      ['-V'],
      ['--continue', '--resume'],
      ['--resume', 'x', '--resume', 'y'],
    ]) {
      await call(args, read: () async => throw StateError('read store'));
    }
  });
  test(
    'launch factory opens selected record in its own cwd through injected ACP',
    () async {
      final dir = await memory.directory();
      final transport = memory.Memory();
      final outcome = await call(
        ['--resume', 'saved'],
        records: [saved('saved', cwd: dir.path)],
      );
      final connection = startLaunchConnection(
        outcome.launch!,
        cwd: 'project',
        open: transport.open,
        stateDirectory: () => dir.path,
      );
      addTearDown(connection.close);
      await connected(connection);
      expect(transport.openedCwd, dir.path);
      expect(connection.app.value.resumed?.sessionId, 'saved');
      expect(
        transport.requests.where((r) => r['method'] == 'session/new'),
        isEmpty,
      );
      expect(
        transport.requests.where((r) => r['method'] == 'session/load'),
        hasLength(1),
      );
      await connection.close();
      expect(transport.process.exited, isTrue);
    },
  );
}

class ResumeTerminal extends Terminal {
  ResumeTerminal(this.size);
  @override
  final Size size;
  final events = StreamController<String>();
  final output = StringBuffer();
  String keys = '';
  var sent = false, entered = 0, left = 0;
  @override
  Stream<String> get input => events.stream;
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() => entered++;
  @override
  Future<void> leave() async {
    left++;
  }

  @override
  void write(String data) {
    output.write(data);
    if (data == '\x1b]11;?\x07') {
      events.add('\x1b]11;rgb:0000/0000/0000\x07');
    } else if (!sent) {
      sent = true;
      events.add(keys);
    }
  }
}
