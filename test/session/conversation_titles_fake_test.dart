// Renames on the original's fake agent, as `--set-title` plays them.
@Tags(['fake_agent'])
library;

import 'dart:async';
import 'dart:io';

import 'package:chord/acp/rpc.dart' show RpcException;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/sessions.dart';
import 'package:path/path.dart' as p;
import 'package:chord/session/session.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'session_fake.dart';

bool _alive(int pid) => Process.runSync('kill', ['-0', '$pid']).exitCode == 0;

/// A conversation on the fake answering titles as [mode] says, up.
Future<
  ({Conversation conversation, List<ConversationEvent> events, Directory dir})
>
_up(String mode) async {
  final dir = Directory.systemTemp.createTempSync('chord-titles-');
  final pids = <int>[];
  final events = <ConversationEvent>[];
  final connected = Completer<void>();
  final conversation = Conversation(
    ({required onTraffic, required cancellationToken}) => openSession(
      agent: 'fake',
      command: fakeAgentCommand(null, ['--set-title', mode]),
      cwd: dir.path,
      open: fakeSessionOpener(pids.add),
      onTraffic: onTraffic,
      cancellationToken: cancellationToken,
    ),
  );
  conversation.listen((event) {
    events.add(event);
    if (event is Connected && !connected.isCompleted) connected.complete();
  });
  addTearDown(() async {
    // Whatever waits on the gate goes once it is released.
    Directory('${dir.path}/.fake-gate').createSync(recursive: true);
    File('${dir.path}/.fake-gate/release').createSync();
    await conversation.close();
    expect(pids.where(_alive), isEmpty, reason: 'the agent is running');
    dir.deleteSync(recursive: true);
  });
  conversation.start();
  await connected.future.timeout(const Duration(seconds: 20));
  return (conversation: conversation, events: events, dir: dir);
}

void main() {
  final skip = fakeAgentSkip;

  test('an agent that takes titles keeps the one it answers', () async {
    final (:conversation, :events, dir: _) = await _up('echo');
    final taken = await conversation.rename('  Fix   the parser ');
    expect(taken, (title: 'Fix the parser', agent: true));
    expect(events.whereType<Renamed>().map((event) => event.title), [
      'Fix the parser',
    ]);
  }, skip: skip);

  test('a refusal is the agent\'s error, and nothing is renamed', () async {
    final (:conversation, :events, dir: _) = await _up('refuse');
    await expectLater(
      conversation.rename('Fix it'),
      throwsA(isA<RpcException>().having((e) => e.code, 'code', -32600)),
    );
    expect(events.whereType<Renamed>(), isEmpty);
  }, skip: skip);

  test('a hung rename leaves the session usable, and is kept once the agent '
      'answers', () async {
    final (:conversation, :events, :dir) = await _up('hang');
    final renaming = conversation.rename('Later');
    final ended = Completer<void>();
    conversation.listen((event) {
      if (event case Transcribed(action: ResultAction())) ended.complete();
    });
    expect(conversation.send('text'), isTrue);
    await ended.future.timeout(const Duration(seconds: 20));
    expect(events.whereType<Renamed>(), isEmpty);
    Directory('${dir.path}/.fake-gate').createSync(recursive: true);
    File('${dir.path}/.fake-gate/release').createSync();
    expect(await renaming.timeout(const Duration(seconds: 20)), (
      title: 'Later',
      agent: true,
    ));
  }, skip: skip);

  test('a pending rename in the record reaches the agent when the session is '
      'reopened', () async {
    final dir = Directory.systemTemp.createTempSync('chord-titles-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final record = p.join(dir.path, 'record.jsonl');
    File(record).writeAsStringSync(
      encodeRecord({
        'type': 'prompt',
        'turnId': 'saved',
        'prompt': 'LOCAL',
        'images': 0,
        'at': 1,
      }),
    );
    await recordPendingRename(record, 'Named while away', 2);
    final pids = <int>[];
    final events = <ConversationEvent>[];
    final renamed = Completer<void>();
    final conversation = Conversation(
      ({required onTraffic, required cancellationToken}) => openSession(
        agent: 'fake',
        command: fakeAgentCommand(null, ['--set-title', 'echo']),
        cwd: dir.path,
        resume: Resume(
          sessionId: '11111111-1111-4111-8111-111111111111',
          cwd: dir.path,
          record: record,
        ),
        open: fakeSessionOpener(pids.add),
        onTraffic: onTraffic,
        cancellationToken: cancellationToken,
      ),
    );
    conversation.listen((event) {
      events.add(event);
      if (event is Renamed && !renamed.isCompleted) renamed.complete();
    });
    addTearDown(() async {
      await conversation.close();
      expect(pids.where(_alive), isEmpty, reason: 'the agent is running');
    });
    conversation.start();
    await renamed.future.timeout(const Duration(seconds: 20));
    expect(events.whereType<Renamed>().map((event) => event.title), [
      'Named while away',
    ]);
  }, skip: skip);
}
