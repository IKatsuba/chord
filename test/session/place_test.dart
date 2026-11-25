import 'dart:convert';
import 'dart:io';

import 'package:chord/agents.dart';
import 'package:chord/session/place.dart';
import 'package:chord/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// A project directory whose `.chord/settings.json` holds [settings].
String project(Map<String, Object?> settings) {
  final dir = Directory.systemTemp.createTempSync('chord-place-');
  addTearDown(() => dir.deleteSync(recursive: true));
  File(p.join(dir.path, '.chord', 'settings.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync(jsonEncode(settings));
  return dir.path;
}

Future<PlaceReader> reader(
  String launchDir, {
  Flags flags = const Flags(agent: 'codex'),
  bool noMcpServers = false,
  List<List<SettingsProblem>>? reported,
}) async => placeReader(
  agent: 'codex',
  launchDir: launchDir,
  launched: await loadSettings(configHome: null, cwd: launchDir),
  flags: flags,
  noMcpServers: noMcpServers,
  configHome: null,
  home: null,
  report: reported?.add,
);

void main() {
  group('tester: CTUI-34 per-directory MCP rereads', () {
    test(
      'simultaneous places and repair never share servers or ignored files',
      () async {
        final launch = project({});
        final other = project({});
        final shared = File(p.join(launch, '.mcp.json'))
          ..writeAsStringSync('{');
        File(p.join(other, '.mcp.json')).writeAsStringSync(
          jsonEncode({
            'mcpServers': {
              'other': {'command': 'serve-other'},
            },
          }),
        );
        final reported = <List<SettingsProblem>>[];
        final read = await reader(launch, reported: reported);
        final places = await Future.wait([read(launch), read(other)]);
        expect(places[0].start!.mcpServers, isEmpty);
        expect(places[0].start!.mcpIgnored.single.from, shared.path);
        expect(places[1].start!.mcpServers.single.server['name'], 'other');
        expect(places[1].start!.mcpIgnored, isEmpty);

        shared.writeAsStringSync(
          jsonEncode({
            'mcpServers': {
              'repaired': {'command': 'serve-repaired'},
            },
          }),
        );
        final repaired = (await read(launch)).start!;
        expect(repaired.mcpServers.single.server['name'], 'repaired');
        expect(repaired.mcpIgnored, isEmpty);
        shared.deleteSync();
        expect((await read(launch)).start!.mcpServers, isEmpty);
        expect(
          (await read(other)).start!.mcpServers.single.server['name'],
          'other',
        );
        expect(reported.expand((each) => each), hasLength(1));
        expect(places[0].start!.mcpIgnored, hasLength(1));
      },
    );
  });

  test('the catalog\'s start, on the values the directory\'s files set, '
      'with where each was set', () async {
    final dir = project({
      'agents': {
        'codex': {'model': 'gpt-5', 'permissionMode': 'read-only'},
      },
    });
    final start = (await (await reader(dir))(dir)).start!;
    expect(start.command, findAgent('codex')!.start.command);
    expect(start.starting.model?.id, 'gpt-5');
    expect(start.starting.model?.from, contains('settings.json'));
    expect(start.starting.mode?.id, 'read-only');
    expect(start.noMcpServers, isFalse);
    expect(start.pinned, findAgent('codex')!.pinned);
    // chord's own command is no command of the person's.
    expect(start.agentCommand, isNull);
  });

  test(
    'the launch directory is read once; another is read on each call',
    () async {
      final launch = project({
        'agents': {
          'codex': {'model': 'first'},
        },
      });
      final other = project({
        'agents': {
          'codex': {'model': 'there'},
        },
      });
      final read = await reader(launch);
      File(p.join(launch, '.chord', 'settings.json')).writeAsStringSync(
        jsonEncode({
          'agents': {
            'codex': {'model': 'changed'},
          },
        }),
      );
      expect((await read(launch)).start!.starting.model?.id, 'first');
      expect((await read(other)).start!.starting.model?.id, 'there');
      File(p.join(other, '.chord', 'settings.json')).writeAsStringSync(
        jsonEncode({
          'agents': {
            'codex': {'model': 'again'},
          },
        }),
      );
      expect((await read(other)).start!.starting.model?.id, 'again');
    },
  );

  test('a command the directory\'s files refuse is said, and nothing '
      'starts', () async {
    final dir = project({
      'agents': {
        'codex': {'command': 3},
      },
    });
    final start = (await (await reader(dir))(dir)).start!;
    expect(start.command, isNull);
    expect(
      start.refused,
      startsWith('codex not started: agents.codex.command'),
    );
  });

  test('--agent-command starts its own command, and pins nothing', () async {
    final dir = project({});
    final start = (await (await reader(
      dir,
      flags: const Flags(agent: 'codex', agentCommand: 'my-codex --acp'),
    ))(dir)).start!;
    expect(start.command, 'my-codex --acp');
    expect(start.pinned, isNull);
    // The person's own, so its limits are not read.
    expect(start.agentCommand, 'my-codex --acp');
  });

  test('--no-mcp-servers, or a file, holds every server back, saying what '
      'set it', () async {
    final plain = project({});
    final flagged = (await (await reader(plain, noMcpServers: true))(
      plain,
    )).start!;
    expect(flagged.noMcpServers, isTrue);
    expect(flagged.noMcpServersFrom, '--no-mcp-servers');
    final dir = project({
      'agents': {
        'codex': {'mcpServers': false},
      },
    });
    final filed = (await (await reader(dir))(dir)).start!;
    expect(filed.noMcpServers, isTrue);
    expect(filed.noMcpServersFrom, p.join(dir, '.chord', 'settings.json'));
  });

  test('another directory\'s problems are reported once each', () async {
    final launch = project({});
    final other = project({'agent': 3});
    final reported = <List<SettingsProblem>>[];
    final read = await reader(launch, reported: reported);
    await read(other);
    await read(other);
    expect(reported, hasLength(1));
  });

  test('the command is the launch directory'
      's wherever a session works; '
      'another directory gives its values and may refuse it', () async {
    final launch = project({
      'agents': {
        'codex': {'command': 'codex-a', 'model': 'a-model'},
      },
    });
    final other = project({
      'agents': {
        'codex': {'command': 'codex-b', 'model': 'b-model'},
      },
    });
    final refusing = project({
      'agents': {
        'codex': {'command': 3},
      },
    });
    final read = await reader(launch);
    final there = (await read(other)).start!;
    expect(there.command, 'codex-a');
    expect(there.starting.model?.id, 'b-model');
    expect(there.pinned, isNull);
    final refused = (await read(refusing)).start!;
    expect(refused.command, isNull);
    expect(refused.refused, startsWith('codex not started:'));
    final flagged = await reader(
      launch,
      flags: const Flags(agent: 'codex', agentCommand: 'codex-flag'),
    );
    final flaggedThere = (await flagged(refusing)).start!;
    expect(flaggedThere.refused, isNull);
    expect(flaggedThere.command, 'codex-flag');
  });

  test('each directory gives its own MCP servers, read on each call, the '
      'project file over .mcp.json, and their problems once each', () async {
    final launch = project({
      'mcpServers': {
        'team': {'command': 'ours'},
        'broken': {'type': 'http'},
      },
    });
    File(p.join(launch, '.mcp.json')).writeAsStringSync(
      jsonEncode({
        'mcpServers': {
          'team': {'command': 'shared'},
          'files': {'command': 'files-mcp'},
        },
      }),
    );
    final other = project({});
    final reported = <List<SettingsProblem>>[];
    final read = await reader(launch, reported: reported);

    final start = (await read(launch)).start!;
    expect(
      [
        for (final d in start.mcpServers)
          '${d.server['name']}=${d.server['command']}',
      ],
      ['team=ours', 'files=files-mcp'],
    );
    expect(start.mcpIgnored.single.servers, 1);
    expect((await read(other)).start!.mcpServers, isEmpty);
    await read(launch);
    expect(
      [for (final each in reported) ...each],
      [
        SettingsProblem(
          p.join(launch, '.chord', 'settings.json'),
          '"mcpServers.broken.url": missing; the server is ignored',
        ),
      ],
    );
  });

  test('the flag, else the last file to say, else the table decides '
      'whether an agent takes MCP servers', () {
    const off = SettingsLayer(
      '/u.json',
      Settings(agents: {'codex': AgentSettings(mcpServers: false)}),
    );
    const on = SettingsLayer(
      '/p.json',
      Settings(agents: {'codex': AgentSettings(mcpServers: true)}),
    );
    expect(mcpServersTaken('codex', const [], flag: true), (
      none: true,
      from: '--no-mcp-servers',
    ));
    expect(mcpServersTaken('codex', const [off], flag: false), (
      none: true,
      from: '/u.json',
    ));
    expect(mcpServersTaken('codex', const [off, on], flag: false), (
      none: false,
      from: null,
    ));
    expect(
      mcpServersTaken('own', const [], flag: false, known: findAgent('codex')),
      (none: false, from: null),
    );
    expect(
      mcpServersTaken(
        'openclaw',
        const [],
        flag: false,
        known: findAgent('openclaw'),
      ),
      (none: true, from: null),
    );
  });
}
