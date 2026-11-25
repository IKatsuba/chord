// The raw past a reopened session keeps for chord acp, on the original's
// fake agent: from the agent's own load for an id chord never recorded,
// none from a resume, and the record's where there is one.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import 'session_fake.dart';

const _id = '11111111-1111-4111-8111-111111111111';

Future<List<PastEvent>?> _past(
  List<String> flags, {
  String? record,
  bool past = true,
}) async {
  final dir = Directory.systemTemp.createTempSync('chord-past-');
  addTearDown(() => dir.deleteSync(recursive: true));
  final session = await openSession(
    agent: 'fake',
    command: fakeAgentCommand(null, flags),
    cwd: dir.path,
    resume: Resume(sessionId: _id, cwd: dir.path, record: record),
    open: fakeSessionOpener(),
    past: past,
  );
  try {
    return session.takeHistory().past;
  } finally {
    await session.close();
  }
}

void main() {
  final skip = fakeAgentSkip;

  test('an id chord never recorded is loaded through the agent, whose replay '
      'is the past, each update whole', () async {
    final past = (await _past([]))!;
    expect(past, isNotEmpty);
    expect(past, everyElement(isA<PastUpdate>()));
    expect(
      past.whereType<PastUpdate>().map((u) => u.update['sessionUpdate']),
      contains('user_message_chunk'),
    );
  }, skip: skip);

  test('a resume replays nothing, so its past is empty', () async {
    expect(await _past(['--resume-only', '--no-load']), isEmpty);
  }, skip: skip);

  test('a window that asks for no past keeps none', () async {
    expect(await _past([], past: false), isNull);
  }, skip: skip);

  test('a recorded session\'s past is its record\'s, even where the agent '
      'loads it, and reaches the conversation', () async {
    final dir = Directory.systemTemp.createTempSync('chord-past-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final record = p.join(dir.path, 'record.jsonl');
    File(record).writeAsStringSync(
      [
        {
          'type': 'prompt',
          'turnId': 'saved',
          'prompt': 'LOCAL',
          'images': 0,
          'at': 1,
        },
        {'type': 'renamed', 'title': 'Saved', 'at': 2},
      ].map(encodeRecord).join(),
    );
    final replayed = Completer<HistoryReplayed>();
    final conversation = Conversation(
      ({required onTraffic, required cancellationToken}) => openSession(
        agent: 'fake',
        command: fakeAgentCommand(null),
        cwd: dir.path,
        resume: Resume(sessionId: _id, cwd: dir.path, record: record),
        open: fakeSessionOpener(),
        onTraffic: onTraffic,
        cancellationToken: cancellationToken,
        past: true,
      ),
    );
    addTearDown(conversation.close);
    conversation.listen((event) {
      if (event is HistoryReplayed && !replayed.isCompleted) {
        replayed.complete(event);
      }
    });
    conversation.start();
    final event = await replayed.future.timeout(const Duration(seconds: 20));
    expect(
      [for (final each in event.past!) each.toJson()],
      [
        {'type': 'prompt', 'text': 'LOCAL'},
        {'type': 'renamed', 'title': 'Saved'},
      ],
    );
  }, skip: skip);

  group('tester U9 history source boundaries', () {
    test(
      'an existing header-only record selects its empty past over agent history',
      () async {
        final dir = Directory.systemTemp.createTempSync('chord-raw-source-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/record.jsonl')
          ..writeAsStringSync(
            encodeRecord({
              'type': 'session',
              'version': 1,
              'sessionId': _id,
              'agent': 'fake',
              'cwd': '/w',
              'at': 0,
            }),
          );
        expect(await _past([], record: file.path), isEmpty);
        expect(
          await _past(['--resume-only', '--no-load'], record: file.path),
          isEmpty,
        );
      },
      skip: skip,
    );

    test(
      'a recorded raw update is independent in two reopened sessions',
      () async {
        final dir = Directory.systemTemp.createTempSync(
          'chord-raw-independent-',
        );
        addTearDown(() => dir.deleteSync(recursive: true));
        final file = File('${dir.path}/record.jsonl')
          ..writeAsStringSync(
            encodeRecord({
              'type': 'update',
              'turnId': 't',
              'update': {
                'sessionUpdate': 'future_update',
                '_meta': {'kept': true},
              },
            }),
          );
        final first = (await _past([], record: file.path))!;
        final second = (await _past([], record: file.path))!;
        expect(first.map((e) => e.toJson()), second.map((e) => e.toJson()));
        first.clear();
        expect(second, hasLength(1));
        expect(second.single.toJson(), {
          'type': 'update',
          'update': {
            'sessionUpdate': 'future_update',
            '_meta': {'kept': true},
          },
        });
      },
      skip: skip,
    );
  });
}
