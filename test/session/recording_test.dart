import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

RecordingSession opening(
  String id, {
  String? path,
  List<Map<String, Object?>> history = const [],
  AgentState state = AgentState.empty,
}) => RecordingSession(
  sessionId: id,
  agent: 'fake',
  cwd: 'fixture-project',
  record: path,
  history: history,
  state: state,
);
Transcribed update(String text, [String turn = 't']) => Transcribed(
  UpdateAction(
    turn,
    acp.SessionUpdate.fromJson({
      'sessionUpdate': 'agent_message_chunk',
      'content': {'type': 'text', 'text': text},
    }),
  ),
);
List<Map<String, Object?>> lines(String text) =>
    parseRecord(text).cast<Map<String, Object?>>();

void main() {
  test('mkdir failure warns once and a later event retries fresh IO', () async {
    final dir = await Directory.systemTemp.createTemp('chord-record-mkdir-');
    addTearDown(() => dir.delete(recursive: true));
    final obstacle = File(recordsDir(dir.path));
    await obstacle.writeAsString('not a directory');
    final warnings = <String>[];
    final recording = FileRecording(
      dir.path,
      failed: warnings.add,
      uuid: () => 'fixture',
    );
    recording.opened(opening('id'));
    recording.sent('t', 'dropped', 0, [], 1);
    await recording.flushed();
    expect(warnings, hasLength(1));
    await obstacle.delete();
    recording.heard(update('later event'));
    await recording.flushed();
    final kept = lines(await File(recording.path!).readAsString());
    expect(kept.map((e) => e['type']), ['update']);
    expect(warnings, hasLength(1));
    recording.heard(const Closing());
    await recording.flushed();
  });

  test(
    'model and selectable option changes persist only changed values',
    () async {
      final writes = <String>[];
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'fixture',
        append: (_, text) async => writes.add(text),
      );
      AgentState state(String model, String effort) => AgentState(
        models: {
          'currentModelId': model,
          'availableModels': [
            {'modelId': 'm1'},
            {'modelId': 'm2'},
          ],
        },
        configOptions: [
          {
            'id': 'effort',
            'name': 'Effort',
            'type': 'select',
            'currentValue': effort,
            'options': [
              {'value': 'low', 'name': 'Low'},
              {'value': 'high', 'name': 'High'},
            ],
          },
        ],
      );
      recording.opened(opening('id', state: state('m1', 'low')));
      recording.sent('t', 'hello', 0, [], 1);
      recording.heard(AgentStateChanged(state('m1', 'low')));
      recording.heard(AgentStateChanged(state('m2', 'low')));
      recording.heard(AgentStateChanged(state('m2', 'high')));
      recording.heard(AgentStateChanged(state('m2', 'high')));
      await recording.flushed();
      expect(lines(writes.join()).where((e) => e['type'] == 'state'), [
        {
          'type': 'state',
          'model': 'm1',
          'options': {'effort': 'low'},
        },
        {
          'type': 'state',
          'model': 'm2',
          'options': {'effort': 'low'},
        },
        {
          'type': 'state',
          'model': 'm2',
          'options': {'effort': 'high'},
        },
      ]);
    },
  );

  test(
    'looking-only openings hold without IO and clear discards their updates',
    () async {
      final writes = <String>[];
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'new',
        now: () => 1,
        append: (_, text) async => writes.add(text),
      );
      recording.opened(opening('old'));
      recording.heard(update('unsubmitted'));
      await recording.flushed();
      expect(writes, isEmpty);
      expect(recording.heldBytes, greaterThan(0));
      recording.heard(const Cleared());
      expect(recording.heldBytes, 0);
      recording.opened(opening('new'));
      recording.sent('t', 'hello', 0, [], 2);
      await recording.flushed();
      expect(lines(writes.join()).map((e) => e['type']), [
        'session',
        'opened',
        'state',
        'prompt',
      ]);
      expect(writes.join(), isNot(contains('unsubmitted')));
      expect(lines(writes.join()).first['sessionId'], 'new');
    },
  );

  test(
    'converted agent history precedes opened/state and submitted content',
    () async {
      final writes = <String>[];
      final history = <String, Object?>{
        'type': 'prompt',
        'turnId': 'history-t',
        'prompt': '[Image #1]',
        'images': 0,
        'at': 1,
      };
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'new',
        now: () => 2,
        append: (_, text) async => writes.add(text),
      );
      recording.opened(opening('id', history: [history]));
      history['prompt'] = 'mutated';
      recording.heard(update('early'));
      recording.sent('t', 'actual', 1, [], 3);
      recording.heard(
        const Transcribed(ResultAction('t', TurnAnswered('end_turn'))),
      );
      await recording.flushed();
      final kept = lines(writes.join());
      expect(kept.map((e) => e['type']), [
        'session',
        'prompt',
        'opened',
        'state',
        'update',
        'prompt',
        'result',
      ]);
      expect(kept[1]['prompt'], '[Image #1]');
      expect(kept[1]['images'], 0);
      expect(kept.last['result'], {
        'status': 'completed',
        'stopReason': 'end_turn',
      });
    },
  );

  test(
    'admission snapshots mutable links, update maps and resource metadata only',
    () async {
      final writes = <String>[];
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'new',
        append: (_, text) async => writes.add(text),
      );
      final link = <String, Object?>{
        'type': 'resource_link',
        'uri': 'file:fixture',
        'name': 'fixture',
      };
      final resource = <String, Object?>{
        'uri': 'resource:fixture',
        'mimeType': 'text/plain',
        'text': 'secret payload',
        'blob': 'secret blob',
      };
      final wire = <String, Object?>{
        'sessionUpdate': 'future',
        '_meta': <String, Object?>{'number': 2.5},
      };
      recording.opened(opening('id'));
      recording.sent(
        't',
        'finalized context and mentions',
        2,
        [link],
        1,
        resources: [resource],
      );
      recording.heard(
        Transcribed(UpdateAction('t', acp.SessionUpdate.fromJson(wire))),
      );
      link['name'] = 'changed';
      resource['uri'] = 'changed';
      (wire['_meta'] as Map)['number'] = 9;
      await recording.flushed();
      final kept = lines(writes.join());
      expect(kept[3]['links'], [
        {'type': 'resource_link', 'uri': 'file:fixture', 'name': 'fixture'},
      ]);
      expect(kept[3]['resources'], [
        {'uri': 'resource:fixture', 'mimeType': 'text/plain'},
      ]);
      expect(kept.last['update'], {
        'sessionUpdate': 'future',
        '_meta': {'number': 2.5},
      });
      expect(writes.join(), isNot(contains('secret')));
    },
  );

  test(
    'flushed joins enqueues during a slow append in prompt/update/result order',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final writes = <String>[];
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'new',
        append: (_, text) async {
          writes.add(text);
          if (writes.length == 1) {
            entered.complete();
            await release.future;
          }
        },
      );
      recording.opened(opening('id'));
      recording.sent('t', 'hello', 0, [], 1);
      await entered.future;
      var flushed = false;
      final done = recording.flushed().then((_) => flushed = true);
      recording.heard(update('reply'));
      recording.heard(
        const Transcribed(
          ResultAction('t', TurnFailed('refused', code: -32000)),
        ),
      );
      await Future<void>.delayed(Duration.zero);
      expect(flushed, isFalse);
      expect(recording.queuedBytes, greaterThan(0));
      expect(
        recording.queuedBytesHighWater,
        greaterThanOrEqualTo(recording.queuedBytes),
      );
      release.complete();
      await done;
      expect(lines(writes.join()).map((e) => e['type']), [
        'session',
        'opened',
        'state',
        'prompt',
        'update',
        'result',
      ]);
      expect(writes, hasLength(2));
      expect(recording.queuedBytes, 0);
    },
  );

  test(
    'one drain groups captured paths without moving retired lines to replacement',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final writes = <({String path, String text})>[];
      var active = 0, peak = 0;
      final recording = FileRecording(
        'state',
        failed: fail,
        append: (path, text) async {
          active++;
          if (active > peak) peak = active;
          writes.add((path: path, text: text));
          if (writes.length == 1) {
            entered.complete();
            await release.future;
          }
          active--;
        },
      );
      recording.opened(opening('a', path: 'a.jsonl'));
      recording.sent('a-t', 'a first', 0, [], 1);
      await entered.future;
      recording.heard(update('a pending', 'a-t'));
      recording.heard(const Cleared());
      recording.opened(opening('b', path: 'b.jsonl'));
      recording.sent('b-t', 'b first', 0, [], 2);
      recording.heard(update('b pending', 'b-t'));
      recording.heard(const Cleared());
      recording.opened(opening('a', path: 'a.jsonl'));
      recording.sent('a-next', 'a second', 0, [], 3);
      release.complete();
      await recording.flushed();
      final a = writes
          .where((e) => e.path == 'a.jsonl')
          .map((e) => e.text)
          .join();
      final b = writes
          .where((e) => e.path == 'b.jsonl')
          .map((e) => e.text)
          .join();
      expect(a, contains('a pending'));
      expect(a, contains('a second'));
      expect(a, isNot(contains('b first')));
      expect(b, contains('b pending'));
      expect(b, isNot(contains('a pending')));
      expect(peak, 1);
    },
  );

  test(
    'partial failure drops uncertain taken and queued lines; later events retry once warned',
    () async {
      final entered = Completer<void>(), release = Completer<void>();
      final writes = <String>[], warnings = <String>[];
      var calls = 0;
      final recording = FileRecording(
        'state',
        failed: warnings.add,
        uuid: () => 'new',
        append: (_, text) async {
          calls++;
          if (calls == 1) {
            writes.add(text.substring(0, 12));
            entered.complete();
            await release.future;
            throw const FileSystemException('partial append');
          }
          if (calls == 3) throw const FileSystemException('second failure');
          writes.add(text);
        },
      );
      recording.opened(opening('id'));
      recording.sent('t', 'uncertain prompt', 0, [], 1);
      await entered.future;
      recording.heard(update('pending dropped'));
      release.complete();
      await recording.flushed();
      expect(warnings, hasLength(1));
      expect(
        warnings.single,
        startsWith("Could not keep this session's record: "),
      );
      recording.heard(update('fresh retry'));
      await recording.flushed();
      recording.heard(update('second failure'));
      await recording.flushed();
      expect(calls, 3);
      expect(warnings, hasLength(1));
      expect(writes.join(), contains('fresh retry'));
      expect(writes.join(), isNot(contains('pending dropped')));
      expect(writes.join(), isNot(contains('uncertain prompt')));
    },
  );

  test(
    'throwing warning observer can reenter with a fresh write without wedging flush',
    () async {
      final writes = <String>[];
      var calls = 0, warnings = 0;
      late FileRecording recording;
      recording = FileRecording(
        'state',
        uuid: () => 'new',
        failed: (_) {
          warnings++;
          recording.heard(update('reentrant retry'));
          throw StateError('observer');
        },
        append: (_, text) async {
          if (++calls == 1) throw StateError('append');
          writes.add(text);
        },
      );
      recording.opened(opening('id'));
      recording.sent('t', 'hello', 0, [], 1);
      await recording.flushed();
      expect(calls, 2);
      expect(warnings, 1);
      expect(writes.single, contains('reentrant retry'));
    },
  );

  test(
    'only changed model/mode/options state is recorded; local events never are',
    () async {
      final writes = <String>[];
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'new',
        append: (_, text) async => writes.add(text),
      );
      recording.opened(opening('id'));
      recording.sent('t', 'hello', 0, [], 1);
      const state = AgentState(
        modes: {
          'currentModeId': 'plan',
          'availableModes': [
            {'id': 'plan', 'name': 'Plan'},
          ],
        },
      );
      recording.heard(const AgentStateChanged(state));
      recording.heard(const AgentStateChanged(state));
      recording.heard(const Queued('queued', 'not sent'));
      recording.heard(const SettingNoted('note', '/model', 'local'));
      recording.heard(const Transcribed(PromptAction('unsent', 'unsent', 4)));
      recording.heard(
        const Transcribed(WarnedAction('local', 'omission notice')),
      );
      recording.heard(const Transcribed(DisconnectedAction('t')));
      recording.heard(const Transcribed(CancelAction('t', 5)));
      recording.heard(const Transcribed(DisconnectedAction('t', at: 6)));
      await recording.flushed();
      final kept = lines(writes.join());
      expect(kept.where((e) => e['type'] == 'state'), hasLength(2));
      expect(kept[4], {'type': 'state', 'mode': 'plan', 'options': {}});
      expect(kept.map((e) => e['type']), [
        'session',
        'opened',
        'state',
        'prompt',
        'state',
        'cancel',
        'disconnected',
      ]);
      expect(writes.join(), isNot(contains('not sent')));
      expect(writes.join(), isNot(contains('omission notice')));
    },
  );

  test(
    'unadmitted prompt failures and cancellation never enter a later hold release',
    () async {
      final writes = <String>[];
      final recording = FileRecording(
        'state',
        failed: fail,
        uuid: () => 'new',
        append: (_, text) async => writes.add(text),
      );
      recording.opened(opening('id'));
      recording.heard(
        const Transcribed(
          ResultAction('unsent', TurnFailed('cancelled before admission')),
        ),
      );
      recording.heard(const Transcribed(CancelAction('unsent', 1)));
      recording.sent('actual', 'hello', 0, [], 2);
      await recording.flushed();
      expect(writes.join(), isNot(contains('unsent')));
      expect(writes.join(), isNot(contains('cancelled before admission')));
    },
  );

  test(
    'known record append preserves every original byte including opaque history',
    () async {
      final dir = await Directory.systemTemp.createTemp('chord-record-prefix-');
      addTearDown(() => dir.delete(recursive: true));
      final prefix = await File(
        'test/fixtures/records/original.jsonl',
      ).readAsBytes();
      final file = File(p.join(dir.path, 'existing.jsonl'));
      await file.writeAsBytes(prefix);
      final recording = FileRecording(dir.path, failed: fail, now: () => 10);
      recording.opened(opening('literal/id', path: file.path));
      await recording.flushed();
      expect(await file.readAsBytes(), prefix);
      recording.sent('new-t', 'hello', 0, [], 11);
      await recording.flushed();
      final bytes = await file.readAsBytes();
      expect(bytes.sublist(0, prefix.length), prefix);
      expect(
        lines(utf8.decode(bytes.sublist(prefix.length))).map((e) => e['type']),
        ['opened', 'state', 'prompt'],
      );
    },
  );

  test(
    'torn final line absorbs first append without any hidden repair separator',
    () async {
      final dir = await Directory.systemTemp.createTemp('chord-record-torn-');
      addTearDown(() => dir.delete(recursive: true));
      final file = File(p.join(dir.path, 'existing.jsonl'));
      const prefix = '{"type":"future","torn":';
      await file.writeAsString(prefix);
      final recording = FileRecording(dir.path, failed: fail, now: () => 1);
      recording.opened(opening('id', path: file.path));
      recording.sent('t', 'hello', 0, [], 2);
      await recording.flushed();
      final bytes = await file.readAsString();
      expect(bytes, startsWith('$prefix{"type":"opened"'));
      expect(lines(bytes).map((e) => e['type']), ['state', 'prompt']);
    },
  );

  test(
    'close stops admission and holds but joins admitted writes before directory removal',
    () async {
      final dir = await Directory.systemTemp.createTemp('chord-record-close-');
      final entered = Completer<void>(), release = Completer<void>();
      final file = File(p.join(dir.path, 'record.jsonl'));
      var writes = 0;
      final recording = FileRecording(
        dir.path,
        failed: fail,
        append: (path, text) async {
          writes++;
          entered.complete();
          await release.future;
          await File(path).writeAsString(text, mode: FileMode.append);
        },
      );
      recording.opened(opening('id', path: file.path));
      recording.sent('t', 'admitted', 0, [], 1);
      await entered.future;
      recording.heard(const Closing());
      recording.sent('late', 'never sent', 0, [], 2);
      recording.heard(update('late update'));
      recording.opened(opening('replacement'));
      var closed = false;
      final close = recording.flushed().then((_) => closed = true);
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      release.complete();
      await close;
      await dir.delete(recursive: true);
      recording.sent('later', 'not admitted', 0, [], 3);
      recording.heard(update('later update'));
      await recording.flushed();
      expect(await dir.exists(), isFalse);
      expect(writes, 1);
    },
  );

  test('close before first admission leaves no filesystem trace', () async {
    final writes = <String>[];
    final recording = FileRecording(
      'state',
      failed: fail,
      uuid: () => 'new',
      append: (_, text) async => writes.add(text),
    );
    recording.opened(opening('id'));
    recording.heard(const Closing());
    recording.sent('t', 'cancelled before admission', 0, [], 1);
    recording.heard(const Transcribed(ResultAction('t', TurnFailed('closed'))));
    await recording.flushed();
    expect(writes, isEmpty);
    expect(recording.heldBytes, 0);
  });
}
