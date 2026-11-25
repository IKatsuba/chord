import 'dart:convert';
import 'dart:io';

import 'package:chord/cli.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:test/test.dart';

void main() {
  group('tester: startup keymap read ownership', () {
    for (final resume in [false, true]) {
      test(
        'file changed during ${resume ? 'resume' : 'agent'} picker does not replace launch map',
        () async {
          final root = await Directory.systemTemp.createTemp('startup-keymap-');
          addTearDown(() => root.delete(recursive: true));
          final home = '${root.path}/home', cwd = '${root.path}/work';
          await Directory('$home/.config/chord').create(recursive: true);
          await Directory(cwd).create();
          final file = File('$home/.config/chord/keybindings.json');
          Future<void> keys(String key) => file.writeAsString(
            jsonEncode({
              'bindings': [
                {
                  'context': 'Chat',
                  'bindings': {key: 'chat:submit'},
                },
              ],
            }),
          );
          await keys('ctrl+s');
          Keybindings? initial;
          final order = <String>[];
          final result = await runCli(
            resume ? ['claude', '--resume'] : [],
            stdout: StringBuffer(),
            stderr: StringBuffer(),
            cwd: cwd,
            home: home,
            environment: {'HOME': home},
            stdinTTY: true,
            stdoutTTY: true,
            lookup: (_) async => '/bin/unused',
            onKeymap: (map) {
              order.add('map');
              initial ??= map;
              expect(map, same(initial));
            },
            readSessionRecords: () async => [
              SessionRecord(
                path: '${root.path}/saved.jsonl',
                sessionId: 'saved',
                agent: 'claude',
                cwd: cwd,
                lastUsedAt: 1,
                prompt: 'saved prompt',
              ),
            ],
            pickAgent:
                ({
                  required agents,
                  required version,
                  required directory,
                  required preferred,
                  required offered,
                }) async {
                  order.add('picker');
                  expect(initial, isNotNull);
                  await keys('ctrl+t');
                  return 'claude';
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
                  order.add('picker');
                  expect(initial, isNotNull);
                  await keys('ctrl+t');
                  return sessions.first;
                },
          );
          expect(result.code, 0);
          expect(order.first, 'map');
          expect(order.where((e) => e == 'picker'), hasLength(1));
          expect(result.launch?.keymap, same(initial));
          expect(
            bound(initial!, 'chat:submit', parseSequence('ctrl+s').value),
            isTrue,
          );
          expect(
            bound(initial!, 'chat:submit', parseSequence('ctrl+t').value),
            isFalse,
          );
        },
      );
    }
  });
}
