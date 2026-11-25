// `chord agents -C <dir> [--json]` from the command line, as the original's
// tests/headless_test.ts plays it (CHD-598): a user file, a project file and
// goose on PATH.
import 'dart:convert';
import 'dart:io';

import 'package:chord/agents.dart';
import 'package:chord/cli.dart';
import 'package:chord/settings.dart' show CommandLine;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory _dir;

Future<({int code, String stdout, String stderr})> _agents(
  List<String> args, {
  String? cwd,
}) async {
  final out = StringBuffer(), err = StringBuffer();
  final outcome = await runCli(
    ['agents', ...args],
    stdout: out,
    stderr: err,
    cwd: cwd ?? p.join(_dir.path, 'elsewhere'),
    home: _dir.path,
    environment: {'XDG_CONFIG_HOME': p.join(_dir.path, 'config')},
    lookup: _goose,
  );
  expect(outcome.launch, isNull);
  return (code: outcome.code, stdout: '$out', stderr: '$err');
}

Future<String?> _goose(String command) async =>
    command == 'goose' ? p.join(_dir.path, 'bin', 'goose') : null;

void main() {
  setUp(() {
    _dir = Directory.systemTemp.createTempSync('chord-agents-');
    File(p.join(_dir.path, 'config', 'chord', 'settings.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'agent': 'goose',
          'offeredAgents': ['mine', 'zed', 'codex', 'goose'],
          'agents': {
            'codex': {'command': 7},
            'mine': {'command': 'mine --acp'},
          },
        }),
      );
    File(p.join(_dir.path, '.chord', 'settings.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode({'theme': 'dark'}));
  });
  tearDown(() => _dir.deleteSync(recursive: true));

  test('the help lists -C and --json with the original\'s words', () {
    expect(
      agentsHelp,
      contains(RegExp(r'-C, --cwd=<dir> +Directory whose settings to read\.')),
    );
    expect(
      agentsHelp,
      contains(
        RegExp(
          r'--json +Print one JSON object instead: the preferred agent, each '
          r'agent with how it starts and whether it is offered and startable, '
          r'and the settings problems\.',
        ),
      ),
    );
  });

  test(
    'stdout is one object; stderr says what the table run says; the exit is 0',
    () async {
      final table = await _agents(['-C', _dir.path]);
      final json = await _agents(['--json', '-C', _dir.path]);
      final user = p.join(_dir.path, 'config', 'chord', 'settings.json');
      final project = p.join(_dir.path, '.chord', 'settings.json');
      final parsed = jsonDecode(json.stdout) as Map<String, Object?>;
      final agents = (parsed['agents']! as List).cast<Map<String, Object?>>();
      Map<String, Object?> named(String name) =>
          agents.firstWhere((agent) => agent['name'] == name);

      expect(json.code, 0);
      expect(json.stderr, table.stderr);
      expect(
        json.stderr,
        contains(
          '"agents.codex.command": expected a string, got a number · codex '
          'will not start',
        ),
      );
      expect(json.stdout, endsWith('}\n'));
      expect(json.stdout.trimRight().split('\n'), hasLength(1));
      expect(parsed['version'], 1);
      expect(parsed['preferred'], 'goose');
      expect(parsed['problems'], [
        {
          'file': user,
          'message':
              '"agents.codex.command": expected a string, got a number · '
              'codex will not start',
        },
        {
          'file': project,
          'message':
              '"theme" is read only from config/chord/settings.json, ignored',
        },
        {'message': '"offeredAgents": no agent named zed, left out'},
      ]);
      expect(
        [
          for (final agent in agents)
            if (agent['offered'] == true) agent['name'],
        ],
        ['mine', 'goose'],
      );
      expect(
        [for (final agent in agents.take(2)) agent['name']],
        ['mine', 'goose'],
      );
      expect(named('mine'), {
        'name': 'mine',
        'title': null,
        'via': 'settings',
        'found': null,
        'offered': true,
        'startable': true,
      });
      expect(named('goose')['found'], isTrue);
      expect(named('cursor'), containsPair('via', 'cli'));
      expect(named('cursor'), containsPair('found', false));
      expect(named('claude'), containsPair('via', 'npx'));
      expect(named('claude'), containsPair('found', null));
      expect(named('codex'), containsPair('offered', false));
      expect(named('codex'), containsPair('startable', false));
      expect(json.stdout, isNot(contains('mine --acp')));
    },
  );

  test('without --json the table is what agentTable lays out', () async {
    final call = await _agents(['-C', _dir.path]);

    expect(call.code, 0);
    expect(
      call.stdout,
      '${agentTable(await listedAgents(_goose, {'mine': const CommandLine('mine --acp')}))}\n',
    );
  });

  test('-C is resolved from where chord was started', () async {
    final relative = await _agents([
      '--json',
      '--cwd',
      '..',
    ], cwd: p.join(_dir.path, 'sub'));
    final here = await _agents(['--json'], cwd: _dir.path);
    final away = await _agents(['--json']);

    expect(relative.stdout, here.stdout);
    expect(relative.stderr, here.stderr);
    expect(here.stderr, contains('"theme" is read only'));
    expect(away.stderr, isNot(contains('"theme" is read only')));
  });
}
