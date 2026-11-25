import 'dart:async';

import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/replay.dart';
import 'package:chord/session/servers.dart';
import 'package:chord/session/sessions.dart';
import 'package:chord/session/starting.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import 'conversation_fake.dart';
import 'settings_test.dart' show select, value;

const _said = [
  '~/.config/chord/settings.json: unknown key "colour", ignored',
  '.chord/settings.json: "theme" is read only from '
      '~/.config/chord/settings.json, ignored',
];

List<(String, String)> _warned(Iterable<TranscriptAction> actions) => [
  for (final action in actions)
    if (action case WarnedAction(:final turnId, :final message))
      (turnId, message),
];

void main() {
  group('tester: CTUI-29 warning reentrancy', () {
    test(
      'a clear in the first warning retires that opening and does not replay warnings',
      () {
        fakeAsync((async) {
          final s = Scripted(warnings: _said);
          var cleared = false;
          s.conversation.listen((event) {
            if (event case Transcribed(action: WarnedAction())) {
              s.conversation.clear().then((_) => cleared = true);
            }
          });
          s.conversation.start();
          async.flushMicrotasks();
          expect(cleared, isTrue);
          expect(s.opens, 2);
          expect(s.events.whereType<Cleared>(), hasLength(1));
          expect(s.events.whereType<Connected>(), hasLength(1));
          expect(
            _warned([
              for (final e in s.events)
                if (e case Transcribed(:final action)) action,
            ]),
            [('warning-0', _said[0])],
          );
          s.conversation.close();
          async.flushMicrotasks();
        });
      },
    );
  });
  test('the settings problems come first, before anything the session says, '
      'and once', () {
    fakeAsync((async) {
      final s = Scripted(warnings: _said);
      s.conversation.start();
      async.flushMicrotasks();
      final first = s.events.take(2).toList();
      expect(_warned([for (final e in first) (e as Transcribed).action]), [
        ('warning-0', _said[0]),
        ('warning-1', _said[1]),
      ]);
      expect(s.events.whereType<Connected>(), hasLength(1));
      s.conversation.clear();
      async.flushMicrotasks();
      final all = [
        for (final e in s.events)
          if (e case Transcribed(:final action)) action,
      ];
      expect(_warned(all), hasLength(2));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });

  test('with a past, the problems lead its batch', () {
    fakeAsync((async) {
      final s = Scripted(warnings: _said);
      s.session.resumed = const Resume(sessionId: 's1', cwd: '/w');
      s.session.prepared = PreparedHistory(
        rawHasPast: true,
        omitted: false,
        actions: [const PromptAction('past-1', 'earlier', 0)],
      );
      s.conversation.start();
      async.flushMicrotasks();
      final batch = s.events.whereType<HistoryReplayed>().single.actions;
      expect(_warned(batch.take(2)), [
        ('warning-0', _said[0]),
        ('warning-1', _said[1]),
      ]);
      expect(batch[2], isA<PromptAction>());
      s.conversation.close();
      async.flushMicrotasks();
    });
  });
  test('a start made at the first warning finds this start under way', () {
    fakeAsync((async) {
      final s = Scripted(warnings: _said);
      s.conversation.listen((event) {
        if (event case Transcribed(action: WarnedAction())) {
          s.conversation.start();
        }
      });
      s.conversation.start();
      async.flushMicrotasks();
      expect(s.opens, 1);
      final all = [
        for (final e in s.events)
          if (e case Transcribed(:final action)) action,
      ];
      expect(_warned(all), [('warning-0', _said[0]), ('warning-1', _said[1])]);
      expect(s.events.whereType<Connected>(), hasLength(1));
      s.conversation.close();
      async.flushMicrotasks();
    });
  });

  test('a close made at the first warning closes the session it acquires', () {
    fakeAsync((async) {
      final s = Scripted(warnings: _said);
      var closed = false;
      s.conversation.listen((event) {
        if (event case Transcribed(action: WarnedAction())) {
          s.conversation.close().then((_) => closed = true);
        }
      });
      s.conversation.start();
      async.flushMicrotasks();
      expect(s.opens, 1);
      expect(closed, isTrue);
      expect(s.session.closes, 1);
      expect(s.events.whereType<Connected>(), isEmpty);
      final all = [
        for (final e in s.events)
          if (e case Transcribed(:final action)) action,
      ];
      expect(_warned(all), [('warning-0', _said[0])]);
    });
  });

  group('the servers the agent was not given', () {
    const held = [
      HeldBack(
        server: 'docs',
        agent: 'scripted',
        transport: 'http',
        takes: ['stdio'],
      ),
    ];
    const line =
        '1 MCP server was not passed to scripted, which takes them over '
        'stdio only: docs (http). /mcp lists it.';
    List<String> messages(Iterable<ConversationEvent> events) => [
      for (final e in events)
        if (e case Transcribed(action: WarnedAction(:final message))) message,
    ];

    test('are said after the settings problems, by every session opened', () {
      fakeAsync((async) {
        final s = Scripted(warnings: _said);
        s.session.heldBack = held;
        s.conversation.start();
        async.flushMicrotasks();
        expect(messages(s.events), [..._said, line]);
        s.conversation.clear();
        async.flushMicrotasks();
        expect(messages(s.events), [..._said, line, line]);
        s.conversation.close();
        async.flushMicrotasks();
      });
    });

    List<String> said(Iterable<ConversationEvent> events) => [
      for (final e in events)
        if (e case Transcribed(
          action: WarnedAction(:final message) || FailedAction(:final message),
        ))
          message,
    ];
    final offering = AgentState(
      configOptions: [
        select('model', 'model', [value('small')], current: 'small'),
      ],
    );

    test('are said once the starting values are settled, after a refusal', () {
      fakeAsync((async) {
        final s = Scripted(
          starting: const Starting(model: StartingValue('huge')),
        );
        s.session.heldBack = held;
        s.session.state = offering;
        s.conversation.start();
        async.flushMicrotasks();
        expect(said(s.events), [
          'Could not start on huge: the agent offers small',
          line,
        ]);
        s.conversation.close();
        async.flushMicrotasks();
      });
    });

    test('are not said while a starting setter has not answered', () {
      fakeAsync((async) {
        final s = Scripted(
          starting: const Starting(model: StartingValue('small')),
        );
        s.session.heldBack = held;
        s.session.state = AgentState(
          configOptions: [
            select('model', 'model', [
              value('small'),
              value('large'),
            ], current: 'large'),
          ],
        );
        final stuck = Completer<void>();
        s.session.change = (kind, id, v) => stuck.future;
        s.conversation.start();
        async.flushMicrotasks();
        expect(s.session.changes, [('model', 'small', null)]);
        expect(messages(s.events), isEmpty);
        stuck.complete();
        async.flushMicrotasks();
        expect(messages(s.events), [line]);
        s.conversation.close();
        async.flushMicrotasks();
      });
    });

    test('a clear made at the line retires the resumed opening before its '
        'past', () {
      fakeAsync((async) {
        final s = Scripted();
        s.session.heldBack = held;
        s.session.resumed = const Resume(sessionId: 's1', cwd: '/w');
        s.session.prepared = PreparedHistory(
          rawHasPast: true,
          omitted: false,
          actions: [const PromptAction('past-1', 'earlier', 0)],
        );
        var clears = 0;
        s.conversation.listen((event) {
          if (event case Transcribed(action: WarnedAction()) when clears == 0) {
            clears++;
            s.conversation.clear();
          }
        });
        s.conversation.start();
        async.flushMicrotasks();
        expect(s.opens, 2);
        final cleared = s.events.indexWhere((e) => e is Cleared);
        final replayed = [
          for (final (index, e) in s.events.indexed)
            if (e is HistoryReplayed) (index, e),
        ];
        expect(replayed, hasLength(1));
        expect(replayed.single.$1, greaterThan(cleared));
        expect(
          [
            for (final action in replayed.single.$2.actions)
              if (action case WarnedAction(:final message)) message,
          ],
          [line],
        );
        s.conversation.close();
        async.flushMicrotasks();
      });
    });

    test(
      'lead a resumed past after the problems, and nothing when all went',
      () {
        fakeAsync((async) {
          final s = Scripted(warnings: _said);
          s.session.heldBack = held;
          s.session.resumed = const Resume(sessionId: 's1', cwd: '/w');
          s.session.prepared = PreparedHistory(
            rawHasPast: true,
            omitted: false,
            actions: [const PromptAction('past-1', 'earlier', 0)],
          );
          s.conversation.start();
          async.flushMicrotasks();
          final batch = s.events.whereType<HistoryReplayed>().single.actions;
          expect(
            [
              for (final action in batch.take(3))
                (action as WarnedAction).message,
            ],
            [..._said, line],
          );
          expect(batch[3], isA<PromptAction>());
          s.conversation.close();
          async.flushMicrotasks();

          final none = Scripted();
          none.conversation.start();
          async.flushMicrotasks();
          expect(messages(none.events), isEmpty);
          none.conversation.close();
          async.flushMicrotasks();
        });
      },
    );
  });
}
