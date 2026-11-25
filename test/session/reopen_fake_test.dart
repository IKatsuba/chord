@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/acp/traffic.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'session_fake.dart';

const id = '11111111-1111-4111-8111-111111111111';
bool alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

void main() {
  group('original fake reopening', skip: fakeAgentSkip, () {
    for (final (flags, local, method, prompts)
        in <(List<String>, bool, String, List<String>)>[
          ([], false, 'session/load', ['tools', 'text']),
          (['--resume-only'], true, 'session/resume', ['LOCAL']),
          (['--resume-only'], false, 'session/load', ['tools', 'text']),
          (['--resume-only', '--no-load'], false, 'session/resume', []),
          ([], true, 'session/load', ['LOCAL']),
        ]) {
      test(
        '$flags local=$local uses $method and prompts the same ACP id',
        () async {
          final dir = await Directory.systemTemp.createTemp(
            'chord-resume-fake-',
          );
          final record = File(p.join(dir.path, 'record.jsonl'));
          if (local) {
            await record.writeAsString(
              encodeRecord({
                'type': 'prompt',
                'turnId': 'saved',
                'prompt': 'LOCAL',
                'images': 0,
                'at': 1,
              }),
            );
          }
          final pids = <int>[];
          final traffic = TrafficRecorder();
          Session? session;
          try {
            session = await openSession(
              agent: 'fake',
              command: fakeAgentCommand('opened', flags),
              cwd: dir.path,
              env: {'XDG_STATE_HOME': p.join(dir.path, 'state')},
              resume: Resume(
                sessionId: id,
                cwd: dir.path,
                record: local ? record.path : null,
              ),
              open: fakeSessionOpener(pids.add),
              onTraffic: traffic.add,
            );
            expect(session.id, id);
            expect(
              session.takeHistory().actions.whereType<PromptAction>().map(
                (a) => a.text,
              ),
              prompts,
            );
            final opened = traffic.heard
                .whereType<ChordTraffic>()
                .map((t) => t.message)
                .singleWhere((m) => m['method'] == method);
            expect(opened['params'], {
              'sessionId': id,
              'cwd': dir.path,
              'mcpServers': [],
            });
            expect(
              traffic.heard.whereType<ChordTraffic>().where(
                (t) => t.message['method'] == 'session/new',
              ),
              isEmpty,
            );
            final ran = await run(session, 'opened');
            expect(ran.result, isA<TurnAnswered>());
            expect(said(ran.updates).join(), contains('"method": "$method"'));
            final sent = traffic.heard
                .whereType<ChordTraffic>()
                .map((t) => t.message)
                .singleWhere((m) => m['method'] == 'session/prompt');
            expect((sent['params'] as Map)['sessionId'], id);
          } finally {
            await session?.close();
            expect(pids, hasLength(1));
            expect(pids.where(alive), isEmpty);
            await dir.delete(recursive: true);
          }
        },
      );
    }

    test(
      'agent refusal does not publish prepared local history and stops its group',
      () async {
        final dir = await Directory.systemTemp.createTemp(
          'chord-resume-refused-',
        );
        final record = File(p.join(dir.path, 'record.jsonl'));
        final prefix = encodeRecord({
          'type': 'prompt',
          'turnId': 'saved',
          'prompt': 'LOCAL',
          'images': 0,
          'at': 1,
        });
        await record.writeAsString(prefix);
        final pids = <int>[];
        try {
          await expectLater(
            openSession(
              agent: 'fake',
              command: fakeAgentCommand(null, ['--resume-only']),
              cwd: dir.path,
              env: {
                'XDG_STATE_HOME': p.join(dir.path, 'state'),
                'CHORD_FAKE_REFUSE_LOAD': '1',
              },
              resume: Resume(sessionId: id, cwd: dir.path, record: record.path),
              open: fakeSessionOpener(pids.add),
            ),
            throwsA(
              isA<ResumeError>().having(
                (e) => e.message,
                'resume refusal',
                startsWith('it cannot resume session $id: '),
              ),
            ),
          );
          expect(await record.readAsString(), prefix);
          expect(pids, hasLength(1));
          expect(pids.where(alive), isEmpty);
        } finally {
          await dir.delete(recursive: true);
        }
      },
    );
  });
}
