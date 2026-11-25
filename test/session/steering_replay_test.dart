import 'dart:io';

import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/context.dart';
import 'package:chord/session/record.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/transcript/entries.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:test/test.dart';

import 'transcript/fold.dart';

Map<String, Object?> _prompt(String id, String text, {String? into}) => {
  'type': 'prompt',
  'turnId': id,
  'prompt': text,
  'images': 0,
  'at': 1.25,
  'into': ?into,
};
Map<String, Object?> _say(String id, String text) => {
  'type': 'update',
  'turnId': id,
  'update': {
    'sessionUpdate': 'agent_message_chunk',
    'content': {'type': 'text', 'text': text},
  },
};

void main() {
  _testerSteeringReplayBoundaries();
  test('personal into appends under its owner without changing turn facts', () {
    final before = fold([
      const PromptAction('running', 'first', 1.25),
      plan('running', [('unfinished', 'in_progress')]),
      update('running', {
        'sessionUpdate': 'usage_update',
        'used': 1.5,
        'size': 20.5,
      }),
      update('running', {
        'sessionUpdate': 'current_mode_update',
        'currentModeId': 'plan',
      }),
    ]);
    final after = reduceTranscript(
      before,
      const PromptAction('queued', 'steered', 9.5, into: 'running'),
    );
    expect(after.turn, same(before.turn));
    expect(after.plan, same(before.plan));
    expect(after.usage, same(before.usage));
    expect(after.mode, before.mode);
    expect(after.entries.last.turnId, 'running');
    expect((after.entries.last as UserEntry).text, 'steered');
    expect(after.entries.first.identity, before.entries.first.identity);
    expect(after.entries.last.identity, isNot(before.entries.first.identity));
    final late = reduceTranscript(
      Transcript.empty,
      const PromptAction('late', 'accepted after end', 2, into: 'ended'),
    );
    expect(late.turn, isA<Idle>());
    expect(late.entries.single.turnId, 'ended');
  });

  test(
    'personal into does not settle the open recorded turn or mark history omitted',
    () {
      final past = recordActions([
        _prompt('running', 'first'),
        _say('running', 'before'),
        _prompt('queued', 'steered', into: 'running'),
        _say('running', 'after'),
      ]);
      expect(past.omitted, isFalse);
      expect(past.actions.whereType<ResultAction>().map((a) => a.turnId), [
        'history-running',
      ]);
      expect(
        past.actions.whereType<PromptAction>().last.into,
        'history-running',
      );
      final transcript = replayTranscript(past.actions);
      expect(transcript.turn, isA<Idle>());
      expect(transcript.entries.map((e) => e.turnId).toSet(), {
        'history-running',
      });
      expect(transcript.entries.whereType<UserEntry>().map((e) => e.text), [
        'first',
        'steered',
      ]);
      expect(
        transcript.entries.whereType<AssistantEntry>().map((e) => e.text.text),
        ['before', 'after'],
      );
      final json = PreparedHistory.fromJson(past.toJson());
      expect(described(replayTranscript(json.actions)), described(transcript));
      expect(
        historyEntries(
          json.actions,
        ).where((e) => e['type'] == 'prompt').last['into'],
        'history-running',
      );
    },
  );

  test(
    'steered shell context replays before its personal row without a new turn',
    () {
      final text = withContext(
        shellContext(const [
          ShellRun(
            command: 'echo held',
            stdout: 'held output',
            running: false,
            code: 0,
          ),
        ]),
        'personal @notes.txt',
      );
      final past = recordActions([
        _prompt('running', 'first'),
        _prompt('queued', text, into: 'running'),
        _say('running', 'continued'),
      ]);
      expect(past.omitted, isFalse);
      final shell = past.actions.whereType<ShellReplayedAction>().single;
      expect(shell.run.command, 'echo held');
      expect(shell.run.stdout, 'held output');
      expect(shell.run.code, 0);
      final steered = past.actions.whereType<PromptAction>().last;
      expect(steered.text, 'personal @notes.txt');
      expect(steered.into, 'history-running');
      expect(past.actions.whereType<ResultAction>().map((a) => a.turnId), [
        'history-running',
      ]);
    },
  );

  test(
    'self-started close retains work and stays below late updates and results',
    () {
      var state = fold([
        const PromptAction('old', 'old prompt', 1),
        const ResultAction('old', TurnAnswered('end_turn')),
        const SelfStartedAction('own'),
      ]);
      final closure = state.entries.last as SelfStartedEntry;
      expect(closure.alone, isTrue);
      state = reduceTranscript(state, say('own', 'already visible'));
      expect((state.entries.last as SelfStartedEntry).alone, isFalse);
      expect(state.entries.last.identity, closure.identity);
      expect(state.entries[state.entries.length - 2], isA<AssistantEntry>());
      final beforeLate = state.entries[state.entries.length - 2];
      state = reduceTranscript(state, say('own', ' plus late text'));
      expect(
        (state.entries[state.entries.length - 2] as AssistantEntry).text.text,
        'already visible plus late text',
      );
      expect(
        state.entries[state.entries.length - 2].identity,
        beforeLate.identity,
      );
      state = reduceTranscript(
        state,
        const ResultAction('own', TurnFailed('late failure')),
      );
      expect(state.entries.last.identity, closure.identity);
      expect(state.entries[state.entries.length - 2], isA<ErrorEntry>());
      expect(state.turn, isA<Idle>());
      state = reduceTranscript(
        state,
        const PromptAction('next', 'next prompt', 2),
      );
      expect(state.entries.last, isA<UserEntry>());
      expect((state.turn as Working).turnId, 'next');
    },
  );

  test(
    'self-started record projection and worker preserve order without omission',
    () async {
      final raw = [
        _prompt('running', 'first'),
        {
          'type': 'result',
          'turnId': 'running',
          'result': {'status': 'completed', 'stopReason': 'end_turn'},
        },
        {'type': 'self_started', 'turnId': 'own'},
        _say('own', 'late work'),
        _prompt('next', 'next'),
      ];
      final expected = recordActions(raw);
      expect(expected.omitted, isFalse);
      final dir = await Directory.systemTemp.createTemp(
        'chord-steering-replay-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/record.jsonl');
      await file.writeAsString(raw.map(encodeRecord).join());
      final prepared = await readRecordedHistory(file.path);
      expect(prepared.omitted, isFalse);
      expect(
        described(replayTranscript(prepared.actions)),
        described(replayTranscript(expected.actions)),
      );
      expect(
        historyEntries(
          prepared.actions,
        ).where((e) => e['type'] == 'self_started').single['turnId'],
        'history-own',
      );
    },
  );

  test(
    'recording keeps accepted into separate from the running result and self close',
    () async {
      final writes = <String>[];
      final recording = FileRecording(
        'isolated-state',
        failed: fail,
        uuid: () => 'fixture',
        append: (_, text) async => writes.add(text),
      );
      recording.opened(
        const RecordingSession(
          sessionId: 's',
          agent: 'fake',
          cwd: 'project',
          state: AgentState.empty,
        ),
      );
      recording.sent('running', 'first', 0, [], 1.25);
      recording.sent(
        'queued',
        'held shell context\n@a',
        0,
        [
          {'type': 'resource_link', 'uri': 'file:///project/a', 'future': 2.5},
        ],
        2.5,
        into: 'running',
      );
      recording.heard(const Transcribed(SelfStartedAction('own')));
      recording.heard(
        const Transcribed(ResultAction('running', TurnAnswered('end_turn'))),
      );
      await recording.flushed();
      final raw = parseRecord(writes.join()).cast<Map<String, Object?>>();
      final prompts = raw.where((e) => e['type'] == 'prompt').toList();
      expect(prompts, hasLength(2));
      expect(prompts.last['into'], 'running');
      expect(prompts.last['at'], 2.5);
      expect((prompts.last['links'] as List).single, {
        'type': 'resource_link',
        'uri': 'file:///project/a',
        'future': 2.5,
      });
      expect(
        raw.where((e) => e['type'] == 'result').single['turnId'],
        'running',
      );
      expect(
        raw.where((e) => e['type'] == 'self_started').single['turnId'],
        'own',
      );
      expect(recordActions(raw).omitted, isFalse);
      recording.heard(const Closing());
      await recording.flushed();
    },
  );

  test(
    'new supported shapes retain unknown bytes while unsupported origins stay omitted',
    () {
      final raw = {
        ..._prompt('q', 'personal', into: 't'),
        '_meta': {
          'unknown': [1.25, 'kept'],
        },
      };
      expect(parseRecord(encodeRecord(RecordEntry.view(raw)!.json)), [raw]);
      expect(RecordEntry.view({...raw, 'into': 1.5}), isNull);
      for (final value in [
        {
          ...raw,
          'from': {'name': 'other'},
        },
        {'type': 'self_started'},
      ]) {
        expect(recordActions([value]).omitted, isTrue);
      }
      // A monitor's sender is drawn since CTUI-36.
      expect(
        recordActions([
          {
            'type': 'self_started',
            'turnId': 'own',
            'from': {
              'name': 'other',
              'monitor': {'id': 'm1'},
            },
          },
        ]).omitted,
        isFalse,
      );
    },
  );

  test(
    'detached replay keeps self-close tail writes linear and occurrences stable',
    () {
      final actions = <TranscriptAction>[
        for (var i = 0; i < 2000; i++) ...[
          SelfStartedAction('own-$i'),
          say('own-$i', 'first'),
          say('own-$i', ' second'),
        ],
      ];
      final work = ReplayWork();
      final result = replayTranscript(actions, work: work);
      expect(result.entries, hasLength(4000));
      expect(result.entries.map((e) => e.identity).toSet(), hasLength(4000));
      expect(work.copiedEntries, 4000);
      expect(work.appendedEntries, lessThanOrEqualTo(8000));
      expect(work.replacedEntries, 2000);
      expect(described(result), described(fold(actions)));
    },
  );
}

void _testerSteeringReplayBoundaries() {
  group('tester: personal steering replay boundaries', () {
    test(
      'several personal rows preserve their owner and fractional timestamps',
      () {
        final raw = <Object?>[
          _prompt('owner', 'original'),
          _say('owner', 'before'),
          {..._prompt('one', '界 😀 é', into: 'owner'), 'at': 2.75},
          _say('owner', 'between'),
          {
            ..._prompt('two', 'literal \u001b[31m text', into: 'owner'),
            'at': 3.125,
          },
          {
            'type': 'result',
            'turnId': 'owner',
            'result': {'status': 'cancelled', 'stopReason': 'cancelled'},
          },
          _prompt('next', 'separate'),
        ];
        final past = recordActions(raw);
        expect(past.omitted, isFalse);
        final personal = past.actions
            .whereType<PromptAction>()
            .where((p) => p.into != null)
            .toList();
        expect(personal.map((p) => p.into), ['history-owner', 'history-owner']);
        expect(personal.map((p) => p.at), [2.75, 3.125]);
        final state = replayTranscript(past.actions);
        expect(
          state.entries.whereType<UserEntry>().map((e) => (e.turnId, e.text)),
          [
            ('history-owner', 'original'),
            ('history-owner', '界 😀 é'),
            ('history-owner', 'literal \u001b[31m text'),
            ('history-next', 'separate'),
          ],
        );
        final projected = PreparedHistory.fromJson(past.toJson());
        expect(
          described(replayTranscript(projected.actions)),
          described(state),
        );
        expect(
          historyEntries(
            projected.actions,
          ).where((e) => e['into'] != null).map((e) => e['at']),
          [2.75, 3.125],
        );
      },
    );

    test(
      'a thousand late Unicode chunks preserve one closure and assistant identity',
      () {
        var state = reduceTranscript(
          Transcript.empty,
          const SelfStartedAction('own'),
        );
        final close = state.entries.single.identity;
        state = reduceTranscript(state, say('own', '界'));
        final assistant = state.entries.first.identity;
        for (var i = 0; i < 1000; i++) {
          state = reduceTranscript(state, say('own', '😀é'));
        }
        expect(state.entries, hasLength(2));
        expect(state.entries.first.identity, assistant);
        expect(
          (state.entries.first as AssistantEntry).text.text,
          '界${List.filled(1000, '😀é').join()}',
        );
        expect(state.entries.last.identity, close);
        expect((state.entries.last as SelfStartedEntry).alone, isFalse);
        expect(state.turn, isA<Idle>());
        final snapshot = state;
        state = reduceTranscript(state, const PromptAction('new', 'next', 1.5));
        expect(snapshot.entries, hasLength(2));
        expect(state.entries[1].identity, close);
        expect((state.turn as Working).turnId, 'new');
      },
    );
  });
}
