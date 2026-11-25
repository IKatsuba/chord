import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/keys.dart' as keys;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart';
import 'package:chord/ui/prompt/queue.dart';
import 'package:chord/ui/shortcuts/keys.dart' as catalog;
import 'package:chord/ui/shortcuts/state.dart';
import 'package:chord/ui/status/status.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

const _running = model.Transcript(turn: model.Working('running', 1));

keys.KeyContext _context(
  AppState state, {
  bool completing = false,
  bool canEdit = true,
  bool picking = false,
}) => keys.KeyContext(
  state: state,
  history: const History(),
  rows: 24,
  completing: completing,
  canEdit: canEdit,
  picking: picking,
);

void main() {
  _testerSteeringStateBoundaries();
  test(
    'queue updates preserve held context through dispatch and refusal without touching draft',
    () {
      var state = reduceApp(
        const AppState(
          transcript: _running,
          held: ['shell'],
          draft: 'typed draft',
          cursor: 3,
        ),
        const Queued('q', 'queued'),
      );
      state = reduceWindow(state, ContextSentAction(['shell']));
      state = reduceApp(state, const Queued('q', 'queued', taken: true));
      expect(state.queue.single.taken, isTrue);
      expect(state.queue.single.held, ['shell']);
      expect(state.held, isEmpty);
      state = reduceApp(state, const Queued('q', 'queued', afterCalls: true));
      expect(state.queue.single.taken, isFalse);
      expect(state.queue.single.afterCalls, isTrue);
      state = reduceApp(state, const Queued('q', 'queued', steering: true));
      expect(state.queue.single.afterCalls, isFalse);
      expect(state.queue.single.steering, isTrue);
      state = reduceApp(state, const Queued('q', 'queued', refused: true));
      expect(state.queue.single.steering, isFalse);
      expect(state.steerRefused, (id: 1, refused: true));
      expect(state.queue.single.held, ['shell']);
      expect((state.draft, state.cursor), ('typed draft', 3));
      state = reduceApp(
        state,
        const QueueWithdrawn([QueuedPrompt('q', 'queued')]),
      );
      expect(state.held, ['shell']);
    },
  );

  test(
    'each note restarts identity while stale expiry cannot clear its replacement',
    () {
      final first = reduceWindow(
        const AppState(),
        const SteerRefusedAction(false),
      );
      final second = reduceWindow(first, const SteerRefusedAction(false));
      expect(first.steerRefused, (id: 1, refused: false));
      expect(second.steerRefused, (id: 2, refused: false));
      expect(reduceWindow(second, const SteerNoteGoneAction(1)), same(second));
      expect(
        reduceWindow(second, const SteerNoteGoneAction(2)).steerRefused,
        isNull,
      );
      expect(steerNoteMs, 3000);
      expect(
        steerNote(false),
        'This agent does not take messages into a running turn · it stays queued',
      );
      expect(
        steerNote(true),
        'Not taken into the running turn · it stays queued',
      );
    },
  );

  test(
    'Tab emits only steering for an eligible busy row and preserves the draft snapshot',
    () {
      const state = AppState(
        transcript: _running,
        queue: [QueuedPrompt('q', 'queued')],
        draft: 'draft',
        cursor: 2,
      );
      final steps = keys.keySteps(Chord.parse('tab'), _context(state));
      expect(steps.single, isA<keys.Steer>());
      expect((state.draft, state.cursor), ('draft', 2));
      final binding = keys
          .windowBindings(() => _context(state), (_) {})
          .singleWhere((binding) => binding.chord == Chord.parse('tab'));
      expect(binding.description, 'Send oldest queued prompt now');
      expect(catalog.shortcuts[1].key, 'tab');
      expect(catalog.shortcuts[1].does, 'to send the oldest queued now');
    },
  );

  test(
    'modal, completion, code pick, help and bash keep their Tab ahead of steering',
    () {
      const queue = [QueuedPrompt('q', 'queued')];
      final blocked = [
        _context(const AppState(queue: queue)),
        _context(
          const AppState(transcript: _running, queue: queue, bash: true),
        ),
        _context(
          const AppState(transcript: _running, queue: queue, closing: true),
        ),
        _context(
          const AppState(
            transcript: _running,
            queue: queue,
            shortcuts: ShortcutsState(help: true),
          ),
        ),
        _context(
          const AppState(transcript: _running, queue: queue),
          completing: true,
        ),
        _context(
          const AppState(transcript: _running, queue: queue),
          canEdit: false,
        ),
        _context(
          const AppState(transcript: _running, queue: queue),
          picking: true,
        ),
      ];
      for (final context in blocked) {
        expect(keys.canSteer(context), isFalse);
        expect(
          keys.keySteps(Chord.parse('tab'), context).whereType<keys.Steer>(),
          isEmpty,
        );
      }
    },
  );

  test(
    'taken, pending and held rows are skipped while later eligible personal rows remain sendable',
    () {
      const blocked = [
        QueuedPrompt('a', 'answer', afterAnswer: true),
        QueuedPrompt('c', 'calls', afterCalls: true),
        QueuedPrompt('s', 'pending', steering: true),
        QueuedPrompt('t', 'taken', taken: true),
      ];
      expect(sendable(blocked), isFalse);
      expect(
        sendable([...blocked, const QueuedPrompt('q', 'eligible')]),
        isTrue,
      );
      expect(restoredDraft(blocked, 'draft'), 'answer\ncalls\ndraft');
    },
  );

  test(
    'queue header priority and first-line folding follow original steering facts',
    () {
      final rows = queueRows(const [
        QueuedPrompt(
          's',
          'one\ntwo',
          steering: true,
          afterAnswer: true,
          afterCalls: true,
        ),
        QueuedPrompt('a', 'answer', afterAnswer: true, afterCalls: true),
        QueuedPrompt('c', 'calls', afterCalls: true),
        QueuedPrompt('t', 'taken', taken: true),
      ], 4).cast<PromptQueueRow>();
      expect(rows.map((r) => r.header), [
        'into the running turn: ',
        'after your answer: ',
        'after the running calls: ',
        null,
      ]);
      expect(rows.first.text, 'one …');
    },
  );

  test(
    'steering notes use original warning tone and suppress mode while preserving reported facts',
    () {
      for (final refused in [false, true]) {
        for (final width in [120, 80, 32]) {
          final view = statusLine(
            StatusFacts(
              model: 'reported-model',
              mode: 'plan',
              notice: steerNote(refused),
              failed: true,
            ),
            width,
          );
          expect(view.left.first.tone, StatusTone.failed);
          expect(
            view.left.first.text,
            startsWith(refused ? 'Not taken' : 'This agent'),
          );
          expect(
            view.left.any((part) => part.tone == StatusTone.plan),
            isFalse,
          );
        }
      }
    },
  );
}

void _testerSteeringStateBoundaries() {
  test(
    'tester: a thousand note replacements reject all stale expiries without changing draft or queue',
    () {
      var state = const AppState(
        transcript: _running,
        queue: [
          QueuedPrompt('q', '界 😀 é', held: ['shell']),
        ],
        draft: 'draft é',
        cursor: 7,
      );
      for (var i = 0; i < 1000; i++) {
        state = reduceWindow(state, SteerRefusedAction(i.isOdd));
      }
      final last = state;
      for (var id = 1; id < 1000; id++) {
        expect(reduceWindow(state, SteerNoteGoneAction(id)), same(last));
      }
      expect(state.steerRefused, (id: 1000, refused: true));
      state = reduceWindow(state, const SteerNoteGoneAction(1000));
      expect(state.steerRefused, isNull);
      expect((state.draft, state.cursor), ('draft é', 7));
      expect(state.queue.single.held, ['shell']);
      expect(state.queue.single.text, '界 😀 é');
    },
  );
}
