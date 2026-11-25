import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/session/context.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

String header({String id = 'id', String? task}) => encodeRecord({
  'type': 'session',
  'version': 1,
  'sessionId': id,
  'agent': 'fake',
  'cwd': 'project',
  'at': 0,
  'task': ?task,
});
String prompt(String text, num at) => encodeRecord({
  'type': 'prompt',
  'turnId': 'turn',
  'prompt': text,
  'at': at,
  'images': 0,
});
String title(Object? text, {String? subagent}) => encodeRecord({
  'type': 'update',
  'turnId': 'turn',
  'update': {'sessionUpdate': 'session_info_update', 'title': text},
  'subagentId': ?subagent,
});
SessionRecord record(
  String id,
  num at, {
  String agent = 'fake',
  String cwd = 'project',
  String? parent,
  String path = 'record',
}) => SessionRecord(
  path: path,
  sessionId: id,
  agent: agent,
  cwd: cwd,
  lastUsedAt: at,
  prompt: 'first',
  parent: parent,
);

void main() {
  test(
    'message, team, aside and shell labels match retained original fixtures',
    () async {
      final oracle =
          jsonDecode(
                await File(
                  'test/fixtures/records/original_oracle.json',
                ).readAsString(),
              )
              as Map;
      for (final fixture in oracle['labels'] as List) {
        final text = fixture['prompt'] as String;
        expect(
          promptLine(text),
          fixture['expected'],
          reason: fixture['name'] as String,
        );
        expect(
          summaryOf('fixture.jsonl', '${header()}${prompt(text, 1)}')!.prompt,
          fixture['expected'],
          reason: fixture['name'] as String,
        );
      }
    },
  );

  test(
    'retained original summary oracle matches all supported facts',
    () async {
      final text = await File(
        'test/fixtures/records/original.jsonl',
      ).readAsString();
      final oracle =
          jsonDecode(
                await File(
                  'test/fixtures/records/original_oracle.json',
                ).readAsString(),
              )
              as Map;
      final summary = summaryOf('fixture.jsonl', text)!.toJson()
        ..removeWhere((key, value) => value == null || value == false);
      expect(summary, oracle['summary']);
    },
  );

  test(
    'summary requires a first version-1 header and a prompt; last prompt is use',
    () {
      expect(summaryOf('r', header()), isNull);
      expect(summaryOf('r', '\n${header()}${prompt('hi', 1)}'), isNull);
      expect(
        summaryOf(
          'r',
          '${header().replaceFirst('"version":1', '"version":2')}${prompt('hi', 1)}',
        ),
        isNull,
      );
      final summary = summaryOf(
        'r',
        '${header()}${prompt(' first\n text ', 1.5)}${prompt('last', 8.25)}${encodeRecord({'type': 'opened', 'at': 999})}',
      )!;
      expect(summary.prompt, 'first text');
      expect(summary.lastUsedAt, 8.25);
      expect(summary.path, 'r');
    },
  );

  test(
    'chronological title rules retain rename, null clear, blank ignore and task name',
    () {
      final base = '${header()}${prompt('first', 1)}';
      final renamed = encodeRecord({
        'type': 'renamed',
        'title': ' renamed\n title ',
        'at': 2,
      });
      expect(
        summaryOf(
          'r',
          '$base${title('initial')}$renamed${title('  ')}${title('child', subagent: 'child')}',
        )!.title,
        'renamed title',
      );
      expect(summaryOf('r', '$base$renamed${title(null)}')!.title, isNull);
      expect(
        summaryOf(
          'r',
          '${header(task: 'task')}${prompt('first', 1)}${title('hidden')}',
        )!.title,
        isNull,
      );
      expect(
        titleLine('hello\u0000 \u001b[31m world\n next'),
        'hello [31m world next',
      );
    },
  );

  test(
    'shell-only prompt summaries name the command without stored output',
    () {
      final context = shellContext([
        const ShellRun(command: 'pwd', stdout: 'output', running: false),
      ]);
      expect(promptLine(context), '!pwd');
      expect(promptLine(withContext(context, ' ask\n now ')), 'ask now');
    },
  );

  test(
    'continue uses exact cwd and agent and excludes children; ties stay stable',
    () {
      final records = [
        record('first', 2),
        record('tie', 2),
        record('child', 9, parent: 'p'),
        record('remote', 8, cwd: 'other'),
        record('other-agent', 10, agent: 'other'),
      ];
      expect(
        latestSession(records, agent: 'fake', cwd: 'project').sessionId,
        'first',
      );
      expect(
        () => latestSession(records, agent: 'none', cwd: 'project'),
        throwsA(
          isA<ResumeError>().having(
            (e) => e.message,
            'message',
            'No earlier none session in project to continue.',
          ),
        ),
      );
      expect(
        earlierSessions(
          records,
          agent: 'fake',
          cwd: 'project',
          except: 'first',
        ).map((s) => s.resume.sessionId),
        ['child', 'tie'],
      );
    },
  );

  test(
    'lists deduplicate latest ids; by-id retains known cwd and refuses other agent',
    () {
      final records = [
        record('id', 1, path: 'old'),
        record('id', 3, cwd: 'other', path: 'new'),
        record('second', 2, agent: 'other'),
      ];
      expect(
        earlierSessions(records, agent: 'fake').single.resume.record,
        'new',
      );
      expect(
        sessionById(records, 'id', agent: 'fake', cwd: 'invocation').cwd,
        'other',
      );
      expect(
        sessionById(
          records,
          'w-unknown',
          agent: 'fake',
          cwd: 'invocation',
        ).record,
        isNull,
      );
      expect(
        sessionById(
          records,
          'w-unknown',
          agent: 'fake',
          cwd: 'invocation',
        ).sessionId,
        'w-unknown',
      );
      expect(
        () => sessionById(records, 'second', agent: 'fake', cwd: 'project'),
        throwsA(
          isA<ResumeError>().having(
            (e) => e.message,
            'message',
            'Session second belongs to another agent (other).',
          ),
        ),
      );
      expect(recordedAgent(records, 'second'), 'other');
      expect(
        sessionLabel(prompt: 'first', name: 'task', title: 'title'),
        'task · title',
      );
      expect(openSessionLabel(' \n '), isNull);
    },
  );

  test('resume commands quote untrusted words and scope typed overrides', () {
    expect(resumeCommand('fake', '-id'), 'chord fake --resume=-id');
    expect(
      resumeCommand('fake', "a'b", 'exec --x'),
      "chord fake --agent-command 'exec --x' --resume 'a'\\''b'",
    );
    expect(
      resumeMessage(
        (agent: 'fake', sessionId: 'id'),
        overrideAgent: 'other',
        agentCommand: 'ignore',
      ),
      'Resume this session with:\nchord fake --resume id',
    );
    expect(resumeMessage(null), isNull);
  });

  test('fixed ages match every retained original Bun boundary', () async {
    final oracle =
        jsonDecode(
              await File(
                'docs/design/evidence/CTUI-26/time-trial/oracle.json',
              ).readAsString(),
            )
            as Map;
    for (final fixture in oracle['cases'] as List) {
      expect(
        lastUsed(fixture['at'] as String, oracle['now'] as num),
        fixture['expected'],
        reason: '${fixture['at']}',
      );
    }
  });

  test(
    'scan skips legacy, unreadable and vanished files with eight streams at most',
    () async {
      final dir = await Directory.systemTemp.createTemp('chord-scan-test-');
      addTearDown(() => dir.delete(recursive: true));
      final records = await Directory(recordsDir(dir.path)).create();
      for (var i = 0; i < 19; i++) {
        await File(p.join(records.path, '$i.jsonl')).writeAsString('');
      }
      await File(p.join(records.path, 'legacy.txt')).writeAsString('');
      var active = 0, peak = 0;
      Stream<String> lines(String path) async* {
        active++;
        if (active > peak) peak = active;
        try {
          await Future<void>.delayed(Duration.zero);
          if (p.basename(path) == '0.jsonl') {
            throw const FileSystemException('vanished');
          }
          yield header(id: p.basename(path)).trimRight();
          yield prompt('hi', 1).trimRight();
          yield '{"type":"update","irrelevant":${' ' * 10000}null}';
        } finally {
          active--;
        }
      }

      expect(await scanRecords(dir.path, lines: lines), hasLength(18));
      expect(peak, 8);
      expect(active, 0);
      expect(await readRecords(p.join(dir.path, 'missing')), isEmpty);
    },
  );

  test(
    'production scan uses an owned isolate and once-per-start shares one future',
    () async {
      final dir = await Directory.systemTemp.createTemp('chord-scan-worker-');
      addTearDown(() => dir.delete(recursive: true));
      await Directory(recordsDir(dir.path)).create();
      await File(
        p.join(recordsDir(dir.path), 'fixture.jsonl'),
      ).writeAsString('${header()}${prompt('hello', 4)}');
      final records = await readRecords(dir.path);
      expect(records.single.prompt, 'hello');
      var calls = 0;
      final once = recordsOnce(() async {
        calls++;
        return records;
      });
      final a = once(), b = once();
      expect(identical(a, b), isTrue);
      expect(await a, same(records));
      expect(calls, 1);
    },
  );

  test('a typed --no-mcp-servers is said again, for the window\'s own '
      'agent alone', () {
    expect(
      resumeCommand('fake', 'id', 'exec --x', true),
      "chord fake --agent-command 'exec --x' --no-mcp-servers --resume id",
    );
    expect(
      elsewhereRefusal(
        const Resume(sessionId: 'id', cwd: '/elsewhere'),
        agent: 'fake',
        noMcpServers: true,
        shownCwd: '~/elsewhere',
      ),
      'That session is in ~/elsewhere. Quit and open it there with:\n'
      'chord fake --no-mcp-servers --resume id',
    );
    expect(
      resumeMessage(
        (agent: 'fake', sessionId: 'id'),
        overrideAgent: 'fake',
        noMcpServers: true,
      ),
      'Resume this session with:\nchord fake --no-mcp-servers --resume id',
    );
    expect(
      resumeMessage(
        (agent: 'codex', sessionId: 'id'),
        overrideAgent: 'fake',
        noMcpServers: true,
      ),
      'Resume this session with:\nchord codex --resume id',
    );
  });
}
