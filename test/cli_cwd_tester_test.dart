import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  group('tester CTUI-100: cwd isolation and directory precedence', () {
    late Directory root;
    late String here, there;
    setUp(() {
      root = Directory.systemTemp.createTempSync('chord-cwd-tester-');
      here = p.join(root.path, 'here');
      there = p.join(root.path, "界 😀 é ' space");
      Directory(here).createSync();
      Directory(there).createSync();
    });
    tearDown(() => root.deleteSync(recursive: true));

    void write(String dir, String file, Object value) => File(p.join(dir, file))
      ..createSync(recursive: true)
      ..writeAsStringSync(jsonEncode(value));

    Future<CliOutcome> call(
      List<String> args, {
      List<SessionRecord> records = const [],
    }) => runCli(
      args,
      stdout: StringBuffer(),
      stderr: StringBuffer(),
      cwd: here,
      home: p.join(root.path, 'home'),
      environment: {
        'XDG_CONFIG_HOME': p.join(root.path, 'config'),
        'XDG_STATE_HOME': p.join(root.path, 'state'),
      },
      readSessionRecords: () async => records,
      lookup: (_) async => 'found',
    );

    test(
      'Unicode and shell punctuation remain literal without process chdir',
      () async {
        final before = Directory.current.path;
        final result = await call(['claude', '-C', there]);
        expect(result.code, 0);
        expect(result.launch!.cwd, there);
        expect(result.launch!.directory, there);
        expect(Directory.current.path, before);
      },
    );

    test(
      'concurrent invocations keep independent settings and MCP files',
      () async {
        for (final (dir, model) in [
          (here, 'here-model'),
          (there, 'there-model'),
        ]) {
          write(dir, '.chord/settings.json', {
            'agents': {
              'claude': {'model': model},
            },
          });
          write(dir, '.mcp.json', {
            'mcpServers': {
              model: {'command': 'fixture-mcp'},
            },
          });
        }
        final results = await Future.wait([
          call(['claude', '-C', there]),
          call(['claude']),
        ]);
        for (final (index, model, dir) in [
          (0, 'there-model', there),
          (1, 'here-model', here),
        ]) {
          final launch = results[index].launch!;
          expect(launch.cwd, dir);
          expect(launch.starting.model!.id, model);
          expect(launch.mcpServers.single.server['name'], model);
          expect(
            launch.childStart!('claude')!.mcpServers.single.server['name'],
            model,
          );
          expect(launch.childStart!('claude')!.starting.model!.id, model);
        }
      },
    );

    test(
      'recorded resume directory wins over -C for settings and MCP',
      () async {
        write(here, '.chord/settings.json', {
          'agents': {
            'claude': {'model': 'record-model'},
          },
        });
        write(there, '.chord/settings.json', {
          'agents': {
            'claude': {'model': 'invocation-model'},
          },
        });
        write(here, '.mcp.json', {
          'mcpServers': {
            'record': {'command': 'fixture-mcp'},
          },
        });
        write(there, '.mcp.json', {
          'mcpServers': {
            'invocation': {'command': 'fixture-mcp'},
          },
        });
        final result = await call(
          ['claude', '-C', there, '-r', 'saved'],
          records: [
            SessionRecord(
              path: 'records/saved.jsonl',
              sessionId: 'saved',
              agent: 'claude',
              cwd: here,
              lastUsedAt: 1,
              prompt: 'saved',
            ),
          ],
        );
        final launch = result.launch!;
        expect(launch.cwd, there);
        expect(launch.resume!.cwd, here);
        expect(launch.directory, here);
        expect(launch.starting.model!.id, 'record-model');
        expect(launch.mcpServers.single.server['name'], 'record');
        expect(
          launch.childStart!('claude')!.starting.model!.id,
          'record-model',
        );
      },
    );

    test('missing cwd value refuses before settings or startup', () async {
      final result = await call(['claude', '-C']);
      expect(result.code, 2);
      expect(result.launch, isNull);
    });

    test('an option after -- remains an argument', () async {
      final result = await call(['claude', '--', '-C', there]);
      expect(result.code, 2);
      expect(result.launch, isNull);
    });

    test('tilde is literal when the shell has not expanded it', () async {
      final result = await call(['claude', '-C', '~/app']);
      expect(result.launch!.cwd, p.join(here, '~', 'app'));
    });
  });
}
