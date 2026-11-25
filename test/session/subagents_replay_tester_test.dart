import 'dart:async';
import 'dart:io';

import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/conversation.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/session.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/subagents.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'recording_test.dart' show opening;
import 'reopen_session_test.dart' as rig;

Map<String, Object?> _spawn(String id) => {
  'sessionId': id,
  'title': 'Agent $id',
};
UpdateAction _update(Map<String, Object?> json, {String? from, num at = 2}) =>
    UpdateAction(
      't',
      acp.SessionUpdate.fromJson(json),
      subagentId: from,
      at: at,
    );
UpdateAction _spawned(String id, {String? from, num at = 2}) => _update(
  {'sessionUpdate': 'subagent_update', ..._spawn(id)},
  from: from,
  at: at,
);
UpdateAction _say(String text, {String? from, String? messageId, num at = 2}) =>
    _update(
      {
        'sessionUpdate': 'agent_message_chunk',
        'content': {'type': 'text', 'text': text},
        'messageId': ?messageId,
      },
      from: from,
      at: at,
    );
String _words(List<Entry> entries) =>
    entries.whereType<AssistantEntry>().map((e) => e.text.text).join();

void main() {
  group('tester nested history route and persistence', () {
    test(
      'actual no-record load keeps grandchild replay and post-reply live routing with root settings and title',
      () async {
        final root = Directory.systemTemp.createTempSync('nested-load-tester-');
        addTearDown(() => root.deleteSync(recursive: true));
        final memory = rig.Memory(resume: false)
          ..pre = [
            rig.notification('user_message_chunk', {
              'content': {'type': 'text', 'text': 'look'},
            }),
            rig.notification('session_info_update', {'title': 'Root title'}),
            rig.notification('subagent_update', _spawn('child')),
            rig.notification('session_info_update', {
              'title': 'Child title',
            }, 'child'),
            rig.notification('current_mode_update', {
              'currentModeId': 'child-mode',
            }, 'child'),
            rig.notification('subagent_update', _spawn('grandchild'), 'child'),
            rig.say('grandchild history 界🙂e\u0301', 'grandchild'),
            rig.say('stranger ignored', 'stranger'),
          ]
          ..post = [rig.say('retained live', 'grandchild')];
        final session = await openSession(
          agent: 'memory',
          command: 'memory',
          cwd: root.path,
          resume: Resume(sessionId: 'literal/id', cwd: root.path),
          open: memory.open,
        );
        try {
          expect(
            memory.requests.where((m) => m['method'] == 'session/load'),
            hasLength(1),
          );
          final past = session.takeHistory();
          expect(past.rawHasPast, isFalse);
          expect(past.title, 'Root title');
          final transcript = past.actions.fold(
            Transcript.empty,
            reduceTranscript,
          );
          final agents = subagentsIn(transcript.entries);
          expect(agents.map((a) => a.id), ['child', 'grandchild']);
          expect(
            agents.map((a) => a.state),
            everyElement(SubagentState.disconnected),
          );
          expect(_words(agents.last.entries), 'grandchild history 界🙂e\u0301');
          expect(session.state.modes?['currentModeId'], 'B');
          final live = <(String, String?)>[];
          final later = Completer<void>();
          session.subscribeAll((u, id) {
            if (u.toJson() case {'content': {'text': final String text}}) {
              live.add((text, id));
              if (text == 'later child') later.complete();
            }
          });
          expect(live, [('retained live', 'grandchild')]);
          memory.process.send(rig.say('later child', 'child'));
          await later.future.timeout(const Duration(seconds: 3));
          expect(live.last, ('later child', 'child'));
          expect(session.state.modes?['currentModeId'], 'B');
        } finally {
          await memory.close(session);
        }
      },
    );

    test(
      'real record and preparation isolate retain tagged child and grandchild work',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'nested-record-tester-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final recording = FileRecording(
          root.path,
          failed: fail,
          uuid: () => 'fixture',
          now: () => 9,
        );
        recording.opened(opening('session'));
        recording.sent('t', 'look', 0, [], 1);
        for (final action in [
          _spawned('child', at: 2.25),
          _spawned('grandchild', from: 'child', at: 3.5),
          _say('child words', from: 'child', at: 4.25),
          _say('grandchild 界🙂e\u0301', from: 'grandchild', at: 5.75),
        ]) {
          recording.heard(Transcribed(action));
        }
        recording.heard(const Transcribed(DisconnectedAction('t', at: 8)));
        final path = recording.path!;
        recording.heard(const Closing());
        await recording.flushed();
        final raw = File(path).readAsStringSync();
        expect(raw, contains('"subagentId":"grandchild"'));
        final past = PreparedHistory.fromJson(
          (await readRecordedHistory(path)).toJson(),
        );
        final transcript = past.actions.fold(
          Transcript.empty,
          reduceTranscript,
        );
        final agents = subagentsIn(transcript.entries);
        expect(agents.map((a) => a.id), ['child', 'grandchild']);
        expect(_words(agents.first.entries), 'child words');
        expect(_words(agents.last.entries), 'grandchild 界🙂e\u0301');
        expect(agents.first.startedAt, 2.25);
        expect(agents.last.startedAt, 3.5);
        expect(
          agents.map((a) => a.state),
          everyElement(SubagentState.disconnected),
        );
        recording.heard(const Closing());
        await recording.flushed();
      },
    );

    test(
      'equal message ids stay local to root sibling and grandchild and unknown senders change nothing',
      () {
        var state = <TranscriptAction>[
          const PromptAction('t', 'look', 1),
          _spawned('a'),
          _spawned('g', from: 'a'),
          _spawned('b'),
          _say('root', messageId: 'same'),
          _say('a', from: 'a', messageId: 'same'),
          _say('g', from: 'g', messageId: 'same'),
          _say('b', from: 'b', messageId: 'same'),
          _say('+g', from: 'g', messageId: 'same'),
        ].fold(Transcript.empty, reduceTranscript);
        final agents = subagentsIn(state.entries);
        expect(_words(state.entries), 'root');
        expect([for (final a in agents) _words(a.entries)], ['a', 'g+g', 'b']);
        final before = state.entries;
        state = reduceTranscript(
          state,
          _say('stranger', from: 'unknown', messageId: 'same'),
        );
        expect(state.entries, same(before));
        state = reduceTranscript(state, const DisconnectedAction('t', at: 10));
        expect(
          subagentsIn(state.entries).map((a) => a.state),
          everyElement(SubagentState.disconnected),
        );
      },
    );
  });
}
