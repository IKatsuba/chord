// The servers the files give reach the original's fake agent, new and
// loaded, exactly as chord lists them.
@Tags(['fake_agent'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:chord/mcp.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/settings.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'session/session_fake.dart';

/// What the fake says it received, from its `mcp` scenario.
Future<Object?> _received(Session session) async {
  final reply = said((await run(session, 'mcp')).updates).join();
  return jsonDecode(reply.replaceAll(RegExp(r'^```json\n|\n```$'), ''));
}

void main() {
  test(
    'the agent receives exactly the servers chord lists, new and loaded',
    () async {
      final root = Directory.systemTemp.createTempSync('chord-mcp-fake-');
      addTearDown(() => root.deleteSync(recursive: true));
      final cwd = p.join(root.path, 'work');
      final configHome = p.join(root.path, 'config');
      Directory(p.join(configHome, 'chord')).createSync(recursive: true);
      Directory(cwd).createSync();
      File(p.join(configHome, 'chord', 'settings.json')).writeAsStringSync(
        jsonEncode({
          'mcpServers': {
            'docs': {
              'type': 'http',
              'url': 'https://mcp.example.com/mcp',
              'headers': {'Authorization': 'Bearer secret'},
            },
          },
        }),
      );
      File(p.join(cwd, '.mcp.json')).writeAsStringSync(
        jsonEncode({
          'mcpServers': {
            'filesystem': {
              'command': 'npx',
              'args': ['-y', '@modelcontextprotocol/server-filesystem', '.'],
              'env': {'DEBUG': '1'},
            },
          },
        }),
      );

      final layers = (await loadSettings(
        configHome: configHome,
        cwd: cwd,
      )).layers;
      final listed = [
        for (final defined in (await loadMcpServers(
          layers: layers,
          cwd: cwd,
        )).servers)
          defined.server,
      ];
      expect(
        [for (final server in listed) server['name']],
        ['docs', 'filesystem'],
      );

      for (final resume in [
        null,
        Resume(sessionId: '7f0c3a52-9d1e-4b6a-8c2f-1e5d9a7b3c40', cwd: cwd),
      ]) {
        final session = await openSession(
          agent: 'fake',
          command: fakeAgentCommand(),
          cwd: cwd,
          env: {'XDG_STATE_HOME': p.join(root.path, 'state')},
          open: fakeSessionOpener(),
          mcpServers: listed,
          resume: resume,
        );
        try {
          expect(session.heldBack, isEmpty);
          expect(
            await _received(session),
            jsonDecode(jsonEncode(listed)),
            reason: resume == null ? 'new' : 'loaded',
          );
        } finally {
          await session.close();
        }
      }
    },
    skip: fakeAgentSkip,
  );
}
