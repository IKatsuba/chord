// chord acp's /team on the original's fake: each form said in one chunk
// of chord's, never a turn of the agent's, but /team new, which is one with
// its preamble ahead; and the refusals in a chunk, not an error. The
// original's tests/acp_agent_test.ts "chord's commands" /team cases.
@Tags(['fake_agent'])
library;

import 'dart:io';

import 'package:chord/server/server.dart' show serveChord;
import 'package:chord/session/team_command.dart' show newTeamPrompt;
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'acp_client.dart';
import 'fixtures/fake_harness.dart';

final _bugfix = File(
  p.join(portPackageDir(), 'test', 'fixtures', 'teams', 'fake', 'bugfix.md'),
).readAsStringSync();

/// `chord acp` on the fake, with chord's server and children on the fake,
/// in a directory holding team `bugfix`.
Future<({AcpClient client, String session})> _served() async {
  final server = await serveChord();
  addTearDown(server.close);
  final client = AcpClient(server: server, children: true);
  final teams = Directory(p.join(client.cwd, '.chord', 'teams'))
    ..createSync(recursive: true);
  File(p.join(teams.path, 'bugfix.md')).writeAsStringSync(_bugfix);
  await client.initialize();
  return (client: client, session: await client.newSession());
}

/// Team `fixture`, as the selected-run tests save it.
const _fixture = '''
---
description: Frozen selection fixture
lead:
  agent: fake
members:
  - name: reviewer
    role: Review only
    agent: fake
    instructions: Preserve this exact review instruction.
---
Preserve the exact team body and permissions.
''';

/// `chord acp` on the fake, in a directory holding team `fixture`, with a
/// teamSelection policy in its user's settings, as the original's case
/// gives its place.
Future<({AcpClient client, String session})> _servedSelected() async {
  final home = Directory.systemTemp.createTempSync('chord-acp-team-home-');
  addTearDown(() => home.deleteSync(recursive: true));
  File(p.join(home.path, '.config', 'chord', 'settings.json'))
    ..createSync(recursive: true)
    ..writeAsStringSync('{"teamSelection": {"intent": "balanced"}}');
  final server = await serveChord();
  addTearDown(server.close);
  final client = AcpClient(
    server: server,
    children: true,
    configHome: p.join(home.path, '.config'),
    home: home.path,
  );
  File(p.join(client.cwd, '.chord', 'teams', 'fixture.md'))
    ..createSync(recursive: true)
    ..writeAsStringSync(_fixture);
  await client.initialize();
  return (client: client, session: await client.newSession());
}

/// What [text] came to as a command: its answer, and the one chunk of
/// chord's it said.
Future<({Map<String, Object?> answer, String? text, Object? meta})> _ran(
  AcpClient client,
  String session,
  String text, {
  List<Map<String, Object?>> more = const [],
}) async {
  final before = client.notified('session/update').length;
  final answer = await client.answer(
    client.ask('session/prompt', {
      'sessionId': session,
      'prompt': [
        {'type': 'text', 'text': text},
        ...more,
      ],
    }),
  );
  final said = client
      .notified('session/update')
      .skip(before)
      .where((params) => params['sessionId'] == session)
      .map((params) => params['update'] as Map)
      .where((update) => (update['_meta'] as Map?)?['chord/command'] != null)
      .lastOrNull;
  return (
    answer: answer,
    text: (said?['content'] as Map?)?['text'] as String?,
    meta: (said?['_meta'] as Map?)?['chord/command'],
  );
}

/// The first block of each prompt chord sent the agents, in order.
List<Object?> _prompts(AcpClient client) => [
  for (final message in client.agentMessages('session/prompt'))
    ((message['params'] as Map)['prompt'] as List).first,
];

void main() {
  group('CTUI-37 tester: ACP team session ownership', () {
    test(
      'same-name runs in two sessions stop independently',
      () async {
        final (:client, :session) = await _served();
        final other = await client.newSession();
        for (final id in [session, other]) {
          final started = await _ran(
            client,
            id,
            '/team run bugfix selectedidle',
          );
          expect(started.meta, {'name': 'team', 'failed': false});
          expect(started.text, contains('Its lead is bugfix;'));
        }
        expect(
          (await _ran(client, session, '/team stop bugfix')).text,
          startsWith('Stopped bugfix:'),
        );
        expect(
          (await _ran(client, session, '/team')).text,
          contains('No run is open.'),
        );
        expect(
          (await _ran(client, other, '/team')).text,
          contains('Runs open:\n\n- bugfix · team bugfix'),
        );
        expect(
          (await _ran(client, other, '/team show bugfix')).text,
          contains('- lead (bugfix) · open · fake'),
        );
        expect(
          (await _ran(client, other, '/team stop bugfix')).text,
          startsWith('Stopped bugfix:'),
        );
        expect(
          (await _ran(client, other, '/team')).text,
          contains('No run is open.'),
        );
        expect(
          _prompts(client).where((block) => '$block'.contains('/team ')),
          isEmpty,
        );
      },
      skip: fakeAgentSkip,
      timeout: const Timeout(Duration(minutes: 1)),
    );
  });

  final skip = fakeAgentSkip;

  test('/team lists, and nothing of it reaches the agent', () async {
    final (:client, :session) = await _served();
    final (:answer, :text, :meta) = await _ran(client, session, '/team');
    expect((answer['result'] as Map)['stopReason'], 'end_turn');
    expect(meta, {'name': 'team', 'failed': false});
    expect(text, contains('Teams:\n\n- bugfix · 3 agents · fake'));
    expect(text, contains('No run is open.'));
    expect(_prompts(client), isEmpty);
  }, skip: skip);

  test(
    '/team show of a team, then of its run; a run and its stop',
    () async {
      final (:client, :session) = await _served();
      expect(
        (await _ran(client, session, '/team show bugfix')).text,
        contains('bugfix · .chord/teams/bugfix.md\n\nFixes a bug'),
      );
      final started = await _ran(
        client,
        session,
        '/team run bugfix fix the quote',
      );
      expect(
        started.text,
        'Team bugfix started. Its lead is bugfix; /team stop bugfix ends it.',
      );
      expect(started.meta, {'name': 'team', 'failed': false});
      final shown = await _ran(client, session, '/team show bugfix');
      expect(shown.text, contains('on "fix the quote"'));
      expect(shown.text, contains('- lead (bugfix) · open · fake'));
      expect(
        (await _ran(client, session, '/team')).text,
        contains('Runs open:\n\n- bugfix · team bugfix · working'),
      );
      final stopped = await _ran(client, session, '/team stop bugfix');
      expect(stopped.text, contains('Stopped bugfix:'));
      // Its members may or may not have opened by now.
      expect(
        stopped.text,
        matches(
          RegExp(r"chord with (its|each) agent's name and -r lists (it|them)$"),
        ),
      );
      expect(
        (await _ran(client, session, '/team stop bugfix')).text,
        'No run named bugfix is open · /team lists them',
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 1)),
  );

  group('refused in a chunk, not an error', () {
    for (final (typed, words) in [
      ('/team run bugfix', '/team run bugfix takes the job after the name'),
      ('/team run', 'Which team? /team lists them'),
      ('/team run nope a job', 'No team named nope · /team lists them'),
      ('/team stop', 'Which run? /team lists them'),
      ('/team show', 'Which team? /team lists them'),
      (
        '/team nope',
        '/team has no nope; it takes list, new, show, run or stop',
      ),
    ]) {
      test(typed, () async {
        final (:client, :session) = await _served();
        final (:answer, :text, :meta) = await _ran(client, session, typed);
        expect(answer['error'], isNull);
        expect((answer['result'] as Map)['stopReason'], 'end_turn');
        expect(text, words);
        expect(meta, {'name': 'team', 'failed': true});
      }, skip: skip);
    }
  });

  test("/team new is a turn of the agent's, its preamble ahead", () async {
    final (:client, :session) = await _served();
    final answer = await client.answer(
      client.ask('session/prompt', {
        'sessionId': session,
        'prompt': [
          {'type': 'text', 'text': '/team new fixes bugs'},
        ],
      }),
    );
    expect((answer['result'] as Map)['stopReason'], 'end_turn');
    // The agent was sent the preamble and the words, not the command.
    final sent = [
      for (final message in client.agentMessages('session/prompt'))
        ((message['params'] as Map)['prompt'] as List).first['text'],
    ];
    expect(sent.single, newTeamPrompt('fixes bugs'));
  }, skip: skip);

  test(
    '/team show of a selected run is refused, open or by its id once '
    'closed',
    () async {
      final (:client, :session) = await _servedSelected();
      await client.answer(
        client.ask('session/prompt', {
          'sessionId': session,
          'prompt': [
            {'type': 'text', 'text': 'budgetawareteam'},
          ],
        }),
      );
      final open = await _ran(client, session, '/team show fixture');
      final runId = RegExp(
        r'then /team show (\S+) there$',
      ).firstMatch(open.text ?? '')?.group(1);
      expect(runId, isNotNull, reason: open.text);
      expect(
        open.text,
        "fixture is a selected run, and only chord's window shows its receipt: "
        "chord -r with this session's id, then /team show $runId there",
      );
      expect(open.meta, {'name': 'team', 'failed': true});
      expect(
        (await _ran(client, session, '/team stop fixture')).text,
        startsWith('Stopped fixture:'),
      );
      final closed = await _ran(client, session, '/team show $runId');
      expect(
        closed.text,
        "$runId is a selected run, and only chord's window shows its receipt: "
        "chord -r with this session's id, then /team show $runId there",
      );
      expect(closed.meta, {'name': 'team', 'failed': true});
      // Neither show reached an agent as a turn: only /team stop's note to
      // main did, as the original's stop tells main.
      expect(
        [
          for (final message in client.agentMessages('session/prompt'))
            '${(message['params'] as Map)['prompt']}',
        ].where((prompt) => prompt.contains('team show')),
        isEmpty,
      );
    },
    skip: skip,
    timeout: const Timeout(Duration(minutes: 1)),
  );

  test('a command beside an image is refused, and nothing runs', () async {
    final (:client, :session) = await _served();
    final (:answer, :text, :meta) = await _ran(
      client,
      session,
      '/team run bugfix fix it',
      more: [
        {'type': 'image', 'data': 'x', 'mimeType': 'image/png'},
      ],
    );
    expect((answer['result'] as Map)['stopReason'], 'end_turn');
    expect(
      text,
      '/team takes text alone, and this prompt had other blocks beside it. '
      'Nothing ran; send the command by itself.',
    );
    expect(meta, {'name': 'team', 'failed': true});
    expect(_prompts(client), isEmpty);
  }, skip: skip);
}
