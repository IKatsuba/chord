// The servers a child's start carries, through the launch a call to chord
// builds: the place's, the settings files' and `.mcp.json`'s, as the
// original's `placeOf` in src/session/place.ts reads them for every agent
// started there, children included.
import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

void main() {
  test("a child's start carries the place's servers, as main's launch "
      'does', () async {
    final root = Directory.systemTemp.createTempSync('chord-child-servers-');
    addTearDown(() => root.deleteSync(recursive: true));
    final home = p.join(root.path, 'home');
    final work = p.join(root.path, 'work');
    Directory(work).createSync(recursive: true);
    File(p.join(home, '.config', 'chord', 'settings.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'mcpServers': {
            'shared': {'command': 'user-shared'},
            'mine': {'command': 'user-mine'},
          },
          'agents': {
            'other': {'command': 'other-agent'},
          },
        }),
      );
    File(p.join(work, '.mcp.json')).writeAsStringSync(
      jsonEncode({
        'mcpServers': {
          'shared': {'command': 'project-shared'},
        },
      }),
    );
    final outcome = await runCli(
      ['fake', '--agent-command', 'fake-agent'],
      stdout: StringBuffer(),
      stderr: StringBuffer(),
      cwd: work,
      home: home,
      environment: {'HOME': home},
      lookup: (command) async => '/bin/$command',
      readSessionRecords: () async => const [],
    );
    expect(outcome.code, 0);
    final launch = outcome.launch!;
    List<Object?> commands(Iterable<Map<String, Object?>> servers) => [
      for (final server in servers) (server['name'], server['command']),
    ];
    final main = commands([for (final d in launch.mcpServers) d.server]);
    expect(main, [('shared', 'project-shared'), ('mine', 'user-mine')]);
    for (final runtime in ['fake', 'other']) {
      final start = launch.childStart!(runtime)!;
      expect(
        commands([for (final d in start.mcpServers) d.server]),
        main,
        reason: runtime,
      );
    }
  });
}
