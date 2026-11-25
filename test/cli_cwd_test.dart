// `-C, --cwd <dir>`: the directory the session works in, resolved, as the
// original's main.tsx reads `resolve(options.cwd)` for every use.
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

late Directory _dir;

String get _home => p.join(_dir.path, 'home');

SessionRecord _saved(String id, String cwd, {num at = 1}) => SessionRecord(
  path: 'records/$id.jsonl',
  sessionId: id,
  agent: 'claude',
  cwd: cwd,
  lastUsedAt: at,
  prompt: 'saved $id',
);

Future<({CliOutcome outcome, String stdout, String stderr})> _chord(
  List<String> args, {
  String? cwd,
  List<SessionRecord> records = const [],
  bool tty = false,
  PickStartupResume? pickResume,
  PickStartupAgent? pickAgent,
  void Function(String cwd)? opened,
}) async {
  final out = StringBuffer(), err = StringBuffer();
  final outcome = await runCli(
    args,
    stdout: out,
    stderr: err,
    cwd: cwd ?? p.join(_dir.path, 'here'),
    home: _home,
    environment: {'XDG_CONFIG_HOME': p.join(_dir.path, 'config')},
    stdinTTY: tty,
    stdoutTTY: tty,
    lookup: (command) async => '/bin/$command',
    readSessionRecords: () async => records,
    readPiped: () async => '',
    pickResume: pickResume,
    pickAgent: pickAgent,
    open:
        ({
          required command,
          env,
          required cwd,
          required onTraffic,
          required onPermission,
          relay,
          cancellationToken,
        }) {
          opened?.call(cwd);
          throw StateError('no agent in this test');
        },
  );
  return (outcome: outcome, stdout: '$out', stderr: '$err');
}

void _settings(String dir, Map<String, Object?> values) {
  File(p.join(dir, '.chord', 'settings.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(
      '{${values.entries.map((e) => '"${e.key}": "${e.value}"').join(', ')}}',
    );
}

void main() {
  setUp(() => _dir = Directory.systemTemp.createTempSync('chord-cwd-'));
  tearDown(() => _dir.deleteSync(recursive: true));

  test('the help lists -C with the original\'s words and example', () {
    expect(
      chordHelp,
      contains(RegExp(r'-C, --cwd=<dir> +Directory the session works in\.\n')),
    );
    expect(
      chordHelp,
      contains(
        RegExp(
          r'Pick an earlier session +chord --resume\n'
          r'  Codex in another directory +chord codex -C ~/src/app\n',
        ),
      ),
    );
  });

  test('without -C the window works where chord was started', () async {
    final call = await _chord(['claude']);

    expect(call.outcome.launch?.cwd, p.join(_dir.path, 'here'));
  });

  test('-C and --cwd give the directory, resolved from the current one', () {
    return Future.wait([
      for (final (args, expected) in [
        (['claude', '-C', '/work/app'], '/work/app'),
        (['claude', '--cwd', '/work/app/'], '/work/app'),
        (['claude', '--cwd=/work/./app'], '/work/app'),
        (['-C', 'sub', 'claude'], p.join(_dir.path, 'here', 'sub')),
        (['claude', '-C', '../there'], p.join(_dir.path, 'there')),
        (['claude', '-C', '.'], p.join(_dir.path, 'here')),
      ])
        _chord(args).then((call) {
          expect(call.outcome.code, 0, reason: '$args ${call.stderr}');
          expect(call.outcome.launch?.cwd, expected, reason: '$args');
        }),
    ]);
  });

  test('the window shows the -C directory from ~', () async {
    final call = await _chord(['claude', '-C', p.join(_home, 'src', 'app')]);

    expect(call.outcome.launch?.directory, '~/src/app');
  });

  test('settings are read from the -C directory', () async {
    final there = p.join(_dir.path, 'there');
    _settings(there, {'agent': 'codex'});

    final here = await _chord([]);
    final moved = await _chord(['-C', there]);

    expect(here.outcome.launch?.name, 'claude');
    expect(moved.outcome.launch?.name, 'codex');
  });

  test('a settings problem names the -C directory\'s file', () async {
    final there = p.join(_dir.path, 'there');
    File(p.join(there, '.chord', 'settings.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{');

    final call = await _chord(['claude', '-C', there]);

    expect(call.stderr, contains(p.join(there, '.chord', 'settings.json')));
  });

  test('--continue finds the latest session in the -C directory', () async {
    final records = [
      _saved('here', p.join(_dir.path, 'here'), at: 2),
      _saved('there', '/work/app'),
    ];

    final call = await _chord([
      'claude',
      '-c',
      '-C',
      '/work/app',
    ], records: records);

    expect(call.outcome.launch?.resume?.sessionId, 'there');
  });

  test('an unknown --resume id opens in the -C directory', () async {
    final call = await _chord(['--resume', 'zzz', 'claude', '-C', '/w']);

    expect(call.outcome.launch?.resume?.cwd, '/w');
  });

  test('a flag\'s value is never taken for an id', () async {
    final call = await _chord(['-C', '--resume', '-r', 'aaa', 'claude']);

    expect(call.outcome.launch?.resume?.sessionId, 'aaa');
    expect(call.outcome.launch?.cwd, p.join(_dir.path, 'here', '--resume'));
  });

  test('the resume picker is shown and looks from the -C directory', () async {
    late String shown, from;
    await _chord(
      ['claude', '-r', '-C', p.join(_home, 'w')],
      tty: true,
      records: [_saved('a', '/elsewhere')],
      pickResume:
          ({
            required sessions,
            required agent,
            required version,
            required directory,
            required cwd,
            required home,
          }) async {
            shown = directory;
            from = cwd;
            return null;
          },
    );

    expect(shown, '~/w');
    expect(from, p.join(_home, 'w'));
  });

  test('the agent picker shows the -C directory', () async {
    late String shown;
    final call = await _chord(
      ['-C', p.join(_home, 'w')],
      tty: true,
      pickAgent:
          ({
            required agents,
            required version,
            required directory,
            required preferred,
            required offered,
          }) async {
            shown = directory;
            return null;
          },
    );

    expect(call.outcome.code, 0);
    expect(shown, '~/w');
  });

  test('-p starts the agent in the -C directory', () async {
    String? started;
    await _chord(
      ['claude', '-p', 'hi', '-C', '/work/app'],
      tty: true,
      opened: (cwd) => started = cwd,
    );

    expect(started, '/work/app');
  });
}
