import 'dart:async';

import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/ui/start.dart';
import 'package:chord/ui/app/start.dart';
import 'package:chord/version.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

Future<String?> found(String command) async => '/bin/$command';

void main() {
  test(
    'interactive unnamed call offers every agent before selected route checks',
    () async {
      final out = StringBuffer();
      final err = StringBuffer();
      var picks = 0;
      final selected = await runCli(
        [],
        stdout: out,
        stderr: err,
        cwd: '/workspace/demo',
        home: null,
        stdinTTY: true,
        stdoutTTY: true,
        lookup: found,
        pickAgent:
            ({
              required agents,
              required version,
              required directory,
              required preferred,
              required offered,
            }) async {
              picks++;
              expect(
                agents.map((a) => a.name),
                listAgents().map((a) => a.name),
              );
              expect(preferred, defaultAgent);
              expect(directory, '/workspace/demo');
              expect(version, isNotEmpty);
              expect(err.toString(), isEmpty);
              return 'codex';
            },
      );
      final named = await runCli(
        ['codex'],
        stdout: StringBuffer(),
        stderr: StringBuffer(),
        cwd: '/workspace/demo',
        home: null,
        lookup: found,
      );
      expect(picks, 1);
      expect(selected.code, named.code);
      expect(selected.launch?.name, named.launch?.name);
      expect(
        selected.launch?.agent?.start.command,
        named.launch?.agent?.start.command,
      );
      expect(selected.launch?.agentCommand, named.launch?.agentCommand);
      expect(out.toString(), isEmpty);
      expect(err.toString(), isEmpty);
    },
  );

  test('missing selected command is refused only after picking', () async {
    final err = StringBuffer();
    var picked = false;
    final result = await runCli(
      [],
      stdout: StringBuffer(),
      stderr: err,
      cwd: '.',
      home: null,
      stdinTTY: true,
      stdoutTTY: true,
      lookup: (_) async => null,
      pickAgent:
          ({
            required agents,
            required version,
            required directory,
            required preferred,
            required offered,
          }) async {
            expect(err.toString(), isEmpty);
            expect(agents.map((a) => a.name), isNot(contains('cursor')));
            expect(agents.firstWhere((a) => a.name == 'claude').found, isNull);
            picked = true;
            return 'claude';
          },
    );
    expect(picked, isTrue);
    expect(result.code, 1);
    expect(result.launch, isNull);
    expect(err.toString(), contains('npx'));
  });

  test(
    'explicit custom command, named, help, version and pipes do not ask',
    () async {
      for (final (args, input, output) in [
        (<String>['codex'], true, true),
        (<String>['--agent-command', 'fixture'], true, true),
        (<String>['--help'], true, true),
        (<String>['--version'], true, true),
        (<String>['agents'], true, true),
        (<String>[], false, true),
        (<String>[], true, false),
      ]) {
        await runCli(
          args,
          stdout: StringBuffer(),
          stderr: StringBuffer(),
          cwd: '.',
          home: null,
          stdinTTY: input,
          stdoutTTY: output,
          lookup: found,
          pickAgent:
              ({
                required agents,
                required version,
                required directory,
                required preferred,
                required offered,
              }) async {
                fail('the existing route must not ask');
              },
        );
      }
    },
  );

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final cancel in [null, '\x1b', '\x03']) {
      test(
        'actual startup page flow picks or cancels and restores terminal at $size with $cancel',
        () async {
          final terminal = _MemoryTerminal(size);
          final err = StringBuffer();
          try {
            final outcome = await runCli(
              [],
              stdout: StringBuffer(),
              stderr: err,
              cwd: '/workspace/demo',
              home: null,
              stdinTTY: true,
              stdoutTTY: true,
              lookup: found,
              pickAgent:
                  ({
                    required agents,
                    required version,
                    required directory,
                    required preferred,
                    required offered,
                  }) async {
                    if (cancel != null) {
                      terminal.keys = cancel;
                    } else {
                      final current = agents.indexWhere(
                        (a) => a.name == preferred,
                      );
                      final target = agents.indexWhere(
                        (a) => a.name == 'codex',
                      );
                      final delta = target - current;
                      terminal.keys =
                          '${delta >= 0 ? 'j' * delta : 'k' * (-delta)}\r';
                    }
                    return selectStartupAgent(
                      agents: agents,
                      version: version,
                      directory: directory,
                      preferred: preferred,
                      terminal: terminal,
                      environment: const {'NO_COLOR': '1'},
                    );
                  },
            ).timeout(const Duration(seconds: 5));
            expect(outcome.code, 0);
            expect(outcome.launch?.name, cancel == null ? 'codex' : null);
            expect(terminal.entered, 1);
            expect(terminal.left, 1);
            expect(terminal.output.toString(), contains('Select agent'));
            expect(err.toString(), isEmpty);
          } finally {
            await terminal.events.close();
          }
        },
      );
    }
  }

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final (keys, expected) in [
      ('12', 'claude'),
      ('1\x03', 'claude'),
      ('\x031', null),
    ]) {
      test('batched startup events settle once at $size for $keys', () async {
        final catalog = await listedAgents(found);
        final agents = [
          for (final name in ['claude', 'codex'])
            catalog.firstWhere((agent) => agent.name == name),
        ];
        var picks = 0;
        var cancels = 0;
        String? picked;
        final terminal = _MemoryTerminal(size)..keys = keys;
        try {
          await runApp(
            StartPage(
              version: 'test',
              directory: '.',
              agents: agents,
              onPicked: (value) {
                picks++;
                picked = value;
              },
              onCanceled: () {
                cancels++;
              },
            ),
            terminal: terminal,
            environment: const {'NO_COLOR': '1'},
            exitProcess: false,
          ).timeout(const Duration(seconds: 5));
          expect(picked, expected);
          expect(picks, expected == null ? 0 : 1);
          expect(cancels, expected == null ? 1 : 0);
          expect(terminal.entered, 1);
          expect(terminal.left, 1);
        } finally {
          await terminal.events.close();
        }
        final helper = _MemoryTerminal(size)..keys = keys;
        try {
          expect(
            await selectStartupAgent(
              agents: agents,
              version: 'test',
              directory: '.',
              terminal: helper,
              environment: const {'NO_COLOR': '1'},
            ).timeout(const Duration(seconds: 5)),
            expected,
          );
          expect(helper.entered, 1);
          expect(helper.left, 1);
        } finally {
          await helper.events.close();
        }
      });
    }
  }

  test('cancel returns cleanly without a launch or refusal', () async {
    final out = StringBuffer();
    final err = StringBuffer();
    final outcome = await runCli(
      [],
      stdout: out,
      stderr: err,
      cwd: '.',
      home: null,
      stdinTTY: true,
      stdoutTTY: true,
      lookup: found,
      pickAgent:
          ({
            required agents,
            required version,
            required directory,
            required preferred,
            required offered,
          }) async => null,
    );
    expect(outcome.code, 0);
    expect(outcome.launch, isNull);
    expect(out.toString(), isEmpty);
    expect(err.toString(), isEmpty);
    expect(version, isNotEmpty);
  });
}

class _MemoryTerminal extends Terminal {
  _MemoryTerminal(this.size);
  @override
  final Size size;
  final events = StreamController<String>();
  final output = StringBuffer();
  String keys = '';
  var sent = false;
  var entered = 0;
  var left = 0;
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
