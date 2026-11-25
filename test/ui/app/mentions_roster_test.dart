// `@@`'s live roster (design CTUI-35 section 6, "`@@`"; interface draft
// section 5 and I9), as the original's App.tsx lists `sessions.recipients()`
// for the agent in front: from main its open children, from a child `main`,
// never a task. A match or an awaited pick begun for one agent, or for one
// launch of it, never completes for another, even where both offer the
// same names; an equal roster for the same agent keeps it.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/tasks.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/terminal.dart'
    show MentionCompletions, rosterResets;
import 'package:chord/ui/prompt/state.dart' show MentionChoice;
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart' show mainKey;
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:fake_async/fake_async.dart';
import 'package:test/test.dart';

import '../../session/conversation_fake.dart';
import 'editor_window_test.dart' show EditorTerminal, plainLaunch, settle;

/// One scoring of a typed query, held until the test answers it.
typedef Scoring = ({
  List<String> names,
  String query,
  Completer<List<String>?> answer,
});

/// The window over a main that never starts, with `parser` and `docs` open
/// behind it on scripted sessions; every non-empty `@@` query waits in
/// [scorings] until the test answers it.
typedef Roster = ({
  StartConnection connection,
  int parser,
  int docs,
  List<Scoring> scorings,
  int Function(String name, int colour) open,
  void Function(int key, ConversationEvent event) emit,
});

Future<Roster> _window(WidgetTester t, Size size) async {
  final hanging = Completer<Agent>();
  final connection = StartConnection(
    command: 'fake',
    cwd: '.',
    agent: 'fake',
    owner: Owned(),
    open:
        ({
          required command,
          env,
          required cwd,
          required onTraffic,
          required onPermission,
          relay,
          cancellationToken,
        }) => hanging.future,
  )..start();
  addTearDown(connection.close);
  addTearDown(() {
    hanging.future.ignore();
    hanging.completeError(StateError('over'));
  });
  final emits = <int, void Function(ConversationEvent)>{};
  int open(String name, int colour) => connection.agents.openChild(
    ChildInfo(
      id: 'id-$name',
      name: name,
      runtime: 'fake',
      openedAt: 0,
      colour: colour,
    ),
    (emit, key) {
      emits[key] = emit;
      connection.fold.dispatch(AgentOpened(key));
      final session = ScriptedSession();
      return Conversation(
        ({required onTraffic, required cancellationToken}) async => session,
      )..listen(emit);
    },
  )!;
  connection.fold.heard(mainKey, const Connected('m', AgentState.empty));
  final parser = open('parser', 0);
  final docs = open('docs', 1);
  final scorings = <Scoring>[];
  await t.pumpWidget(
    TranscriptWindow(
      launch: plainLaunch,
      connection: connection,
      terminal: EditorTerminal(),
      walkFiles: (cwd, {cancellationToken}) async => const [],
      matchMentions: (names, query) {
        if (query.isEmpty) return Future.value(names);
        final answer = Completer<List<String>?>();
        scorings.add((names: names, query: query, answer: answer));
        return answer.future;
      },
    ),
    size: size,
  );
  await settle(t);
  return (
    connection: connection,
    parser: parser,
    docs: docs,
    scorings: scorings,
    open: open,
    emit: (key, event) => emits[key]!(event),
  );
}

Future<void> _show(WidgetTester t, Roster w, int key) async {
  w.connection.fold.dispatch(SessionShown(key));
  await settle(t);
}

/// The names the finder offers, its rows between the rule and the prompt.
List<String> _offered(WidgetTester t) {
  final lines = t.screen.lines;
  final box = lines.indexWhere((line) => line.startsWith('╭'));
  final rule = lines.sublist(0, box).lastIndexWhere((l) => l.startsWith(' ─'));
  if (rule < 0) return const [];
  return [
    for (final line in lines.sublist(rule + 1, box))
      if (line.trim().isNotEmpty) line.trim(),
  ];
}

/// Agent [key]'s draft, shown or not.
String _draft(Roster w, int key) => w.connection.fold.stateOf(key)!.draft;

/// Sets hidden agent [key]'s draft to [text], its cursor at the end.
void _setDraft(Roster w, int key, String text) => w.connection.fold.dispatch(
  SessionActed(key, DraftEditedAction(text, text.length)),
);

/// Types `@@ma` in the agent in front and presses Tab before its scoring
/// comes: the pick waits on it. Returns that scoring.
Future<Scoring> _awaitPick(WidgetTester t, Roster w) async {
  await t.type('@@ma');
  await settle(t);
  final scoring = w.scorings.last;
  expect(scoring.query, 'ma');
  expect(scoring.names, ['main']);
  await t.press('tab');
  await settle(t);
  expect(w.connection.fold.app.value.draft, '@@ma');
  return scoring;
}

/// Answers every scoring still waiting with [found].
Future<void> _answerAll(WidgetTester t, Roster w, List<String> found) async {
  for (final scoring in w.scorings) {
    if (!scoring.answer.isCompleted) scoring.answer.complete(found);
  }
  await settle(t);
}

void main() {
  _testerRosterLifetimes();
  group('rosterResets', () {
    const a = (key: 2, launch: 0), b = (key: 3, launch: 0);
    test('the first listing resets', () {
      expect(rosterResets(null, (session: a, names: const ['main'])), isTrue);
    });
    test('another front with equal names resets', () {
      expect(
        rosterResets(
          (session: a, names: const ['main']),
          (session: b, names: const ['main']),
        ),
        isTrue,
      );
    });
    test('another launch of the same agent resets', () {
      expect(
        rosterResets(
          (session: a, names: const ['main']),
          (session: (key: 2, launch: 1), names: const ['main']),
        ),
        isTrue,
      );
    });
    test('the same session with equal names, another list, keeps', () {
      expect(
        rosterResets(
          (session: a, names: ['parser', 'docs']),
          (session: (key: 2, launch: 0), names: ['parser', 'docs']),
        ),
        isFalse,
      );
    });
    test('the same session with other names resets', () {
      expect(
        rosterResets(
          (session: a, names: const ['parser', 'docs']),
          (session: a, names: const ['parser']),
        ),
        isTrue,
      );
      expect(
        rosterResets(
          (session: a, names: const ['parser', 'docs']),
          (session: a, names: const ['docs', 'parser']),
        ),
        isTrue,
      );
    });
  });

  test('resetSession with equal names drops the awaited pick and the '
      'match begun before, and matches afresh', () {
    fakeAsync((async) {
      final answers = <Completer<List<String>?>>[];
      final choices = <MentionChoice>[];
      final c = MentionCompletions(
        cwd: '.',
        onChoice: choices.add,
        recipients: ['main'],
        walk: (cwd, {cancellationToken}) async => const [],
        match: (names, query) {
          if (query.isEmpty) return Future.value(names);
          final answer = Completer<List<String>?>();
          answers.add(answer);
          return answer.future;
        },
      );
      c.update('@@ma', 4);
      async.flushMicrotasks();
      c.setRoom(6, visible: true);
      expect(c.accept(enter: false), isTrue);
      c.resetSession(['main']);
      async.flushMicrotasks();
      expect(answers, hasLength(2));
      answers.first.complete(['main']);
      async.flushMicrotasks();
      expect(choices, isEmpty);
      expect(c.finder!.pending, isTrue);
      answers.last.complete(['main']);
      async.flushMicrotasks();
      expect(choices, isEmpty);
      expect(c.finder!.files, ['main']);
      expect(c.accept(enter: false), isTrue);
      expect(choices.single.text, '@@main ');
      c.dispose();
    });
  });

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    group('at $size', () {
      testWidgets("main offers its open children, each in its colour", (
        t,
      ) async {
        await _window(t, size);
        await t.type('@@');
        await settle(t);
        expect(_offered(t), ['parser', 'docs']);
        // A row not highlighted is drawn in the colour of its row in the
        // list; the highlight is drawn as the focus.
        Color? colourOf(String row, String name) {
          final lines = t.screen.lines;
          final y = lines.indexWhere((line) => line.startsWith(row));
          return t.screen.styleAt(lines[y].indexOf(name), y).fg;
        }

        final docs = colourOf('    docs ', 'docs');
        expect(docs, isNotNull);
        expect(colourOf('  docs', 'docs'), docs);
        await t.press('down');
        await settle(t);
        final parser = colourOf('    parser ', 'parser');
        expect(parser, isNotNull);
        expect(parser, isNot(docs));
        expect(colourOf('  parser', 'parser'), parser);
        await t.press('tab');
        expect(t.screen, shows('@@docs '));
      });
      testWidgets('a child offers main alone', (t) async {
        final w = await _window(t, size);
        await _show(t, w, w.parser);
        await t.type('@@');
        await settle(t);
        expect(_offered(t), ['main']);
        await t.press('tab');
        expect(w.connection.fold.app.value.draft, '@@main ');
      });

      testWidgets("a pick awaited in one child is dropped as another comes "
          "in front, though both offer main; the other's draft is "
          'untouched', (t) async {
        final w = await _window(t, size);
        await _show(t, w, w.parser);
        await _awaitPick(t, w);
        _setDraft(w, w.docs, '@@ma');
        await _show(t, w, w.docs);
        await _answerAll(t, w, ['main']);
        expect(_draft(w, w.docs), '@@ma');
        expect(_draft(w, w.parser), '@@ma');
        // docs's own scoring, begun afresh, completes in docs.
        expect(w.scorings.last.names, ['main']);
        await t.press('tab');
        await _answerAll(t, w, ['main']);
        expect(_draft(w, w.docs), '@@main ');
        expect(_draft(w, w.parser), '@@ma');
      });

      testWidgets("a pick awaited in a child is dropped by its /clear, its "
          'draft kept', (t) async {
        final w = await _window(t, size);
        await _show(t, w, w.parser);
        final before = await _awaitPick(t, w);
        w.connection.agents.conversationOf(w.parser)!.clear().ignore();
        await settle(t);
        expect(w.connection.fold.front, w.parser);
        expect(_draft(w, w.parser), '@@ma');
        before.answer.complete(['main']);
        await settle(t);
        expect(_draft(w, w.parser), '@@ma');
        // The new launch's own scoring is the one a pick waits on.
        expect(identical(w.scorings.last, before), isFalse);
        await t.press('tab');
        await _answerAll(t, w, ['main']);
        expect(_draft(w, w.parser), '@@main ');
      });

      testWidgets("a pick awaited in a child is dropped as it closes and "
          'opens again under its name', (t) async {
        final w = await _window(t, size);
        await _show(t, w, w.parser);
        final before = await _awaitPick(t, w);
        // Main's draft, where the window goes as parser closes, and the
        // reopened parser's both read as parser's did.
        _setDraft(w, mainKey, '@@ma');
        w.connection.agents.closeChild(w.parser).ignore();
        w.connection.fold.dispatch(SessionClosed(w.parser, mainKey));
        await settle(t);
        final again = w.open('parser', 2);
        _setDraft(w, again, '@@ma');
        await _show(t, w, again);
        before.answer.complete(['main']);
        await settle(t);
        expect(_draft(w, again), '@@ma');
        expect(_draft(w, mainKey), '@@ma');
        await t.press('tab');
        await _answerAll(t, w, ['main']);
        expect(_draft(w, again), '@@main ');
        expect(_draft(w, mainKey), '@@ma');
      });

      testWidgets('a roster update with equal names in the same front keeps '
          'the awaited pick', (t) async {
        final w = await _window(t, size);
        await t.type('@@pa');
        await settle(t);
        final scoring = w.scorings.last;
        expect(scoring.names, ['parser', 'docs']);
        await t.press('tab');
        // A hidden child's turn changes the windowed state and lists the
        // roster again, the same names in a new list.
        w.emit(w.docs, const Transcribed(PromptAction('turn', 'go on', 0)));
        await settle(t);
        expect(identical(w.scorings.last, scoring), isTrue);
        scoring.answer.complete(['parser']);
        await settle(t);
        expect(w.connection.fold.app.value.draft, '@@parser ');
      });

      testWidgets('a closed child is no longer offered', (t) async {
        final w = await _window(t, size);
        await t.type('@@');
        await settle(t);
        expect(_offered(t), ['parser', 'docs']);
        w.connection.agents.closeChild(w.docs).ignore();
        w.connection.fold.dispatch(SessionClosed(w.docs, mainKey));
        await settle(t);
        expect(_offered(t), ['parser']);
        await t.type('d');
        await settle(t);
        expect(w.scorings.last.names, ['parser']);
      });

      testWidgets('a task is never offered, from main or from a child', (
        t,
      ) async {
        final w = await _window(t, size);
        for (final action in [
          PromptAction('t1', 'tasklong', 0),
          UpdateAction(
            't1',
            taskUpdate(
              'task-1',
              SubagentState.running,
              task: const TaskStart(
                id: 'task-1',
                name: 'Watch the build',
                runtime: 'fake',
                prompt: 'taskwait',
              ),
            ),
          ),
        ]) {
          w.connection.fold.heard(mainKey, Transcribed(action));
        }
        await settle(t);
        expect(t.screen, shows('Agent(Watch the build)'));
        await t.type('@@');
        await settle(t);
        expect(_offered(t), ['parser', 'docs']);
        await t.type('w');
        await settle(t);
        expect(w.scorings.last.names, ['parser', 'docs']);
        await t.press('ctrl+c');
        await _show(t, w, w.parser);
        await t.type('@@');
        await settle(t);
        expect(_offered(t), ['main']);
      });
    });
  }
}

void _testerRosterLifetimes() {
  group('CTUI-35 tester: roster completion lifetimes', () {
    for (final newestFirst in [false, true]) {
      test(
        'session reset retires awaited file match with newest-first=$newestFirst',
        () {
          fakeAsync((async) {
            final scores = <Completer<List<String>?>>[];
            final choices = <MentionChoice>[];
            final c = MentionCompletions(
              cwd: '.',
              onChoice: choices.add,
              recipients: ['main'],
              walk: (_, {cancellationToken}) async => ['alpha'],
              match: (names, query) {
                final answer = Completer<List<String>?>();
                scores.add(answer);
                return answer.future;
              },
            );
            c.update('@a', 2);
            async.flushMicrotasks();
            c.setRoom(6, visible: true);
            expect(c.accept(enter: false), isTrue);
            c.resetSession(['main']);
            async.flushMicrotasks();
            expect(scores, hasLength(2));
            if (newestFirst) {
              scores.last.complete(['alpha']);
              async.flushMicrotasks();
              scores.first.complete(['stale']);
            } else {
              scores.first.complete(['stale']);
              async.flushMicrotasks();
              scores.last.complete(['alpha']);
            }
            async.flushMicrotasks();
            expect(choices, isEmpty);
            expect(c.finder!.files, ['alpha']);
            expect(c.accept(enter: false), isTrue);
            expect(choices.single.text, '@alpha ');
            c.dispose();
            expect(async.pendingTimers, isEmpty);
          });
        },
      );
    }
    test(
      'a thousand reset results after disposal publish no choice or timers',
      () {
        fakeAsync((async) {
          final scores = <Completer<List<String>?>>[];
          final choices = <MentionChoice>[];
          final c = MentionCompletions(
            cwd: '.',
            onChoice: choices.add,
            recipients: ['main'],
            walk: (_, {cancellationToken}) async => const [],
            match: (names, query) {
              final answer = Completer<List<String>?>();
              scores.add(answer);
              return answer.future;
            },
          );
          c.update('@@ma', 4);
          async.flushMicrotasks();
          c.setRoom(6, visible: true);
          expect(c.accept(enter: false), isTrue);
          for (var i = 0; i < 1000; i++) {
            c.resetSession(['main']);
          }
          async.flushMicrotasks();
          expect(scores, hasLength(1001));
          c.dispose();
          for (final score in scores.reversed) {
            score.complete(['main']);
          }
          async.flushMicrotasks();
          expect(choices, isEmpty);
          expect(async.pendingTimers, isEmpty);
        });
      },
    );
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a hidden burst and resize preserve the same-front awaited pick at $size',
        (t) async {
          final w = await _window(t, size);
          await t.type('@@pa');
          await settle(t);
          final scoring = w.scorings.last;
          final count = w.scorings.length;
          await t.press('tab');
          for (var i = 0; i < 1000; i++) {
            w.emit(
              w.docs,
              Transcribed(PromptAction('burst$i', 'hidden $i', 0)),
            );
          }
          await t.resize(
            size.width == 120 ? const Size(80, 24) : const Size(120, 40),
          );
          await settle(t);
          expect(w.scorings, hasLength(count));
          expect(w.scorings.last, same(scoring));
          scoring.answer.complete(['parser']);
          await settle(t);
          expect(_draft(w, mainKey), '@@parser ');
        },
      );
      testWidgets(
        'changed roster drops a pending pick even when its answer is still a valid name at $size',
        (t) async {
          final w = await _window(t, size);
          await t.type('@@pa');
          await settle(t);
          final old = w.scorings.last;
          await t.press('tab');
          w.connection.agents.closeChild(w.docs).ignore();
          w.connection.fold.dispatch(SessionClosed(w.docs, mainKey));
          await settle(t);
          old.answer.complete(['parser']);
          await settle(t);
          expect(_draft(w, mainKey), '@@pa');
          expect(w.scorings.last.names, ['parser']);
          await _answerAll(t, w, ['parser']);
          expect(_draft(w, mainKey), '@@pa');
          await t.press('tab');
          expect(_draft(w, mainKey), '@@parser ');
        },
      );
      testWidgets(
        'Unicode recipients keep opening order and complete the whole name at $size',
        (t) async {
          final w = await _window(t, size);
          const name = '界🙂e\u0301';
          w.open(name, 2);
          await settle(t);
          await t.type('@@');
          await settle(t);
          expect(_offered(t), ['parser', 'docs', name]);
          await t.press('down');
          await t.press('down');
          await t.press('tab');
          expect(_draft(w, mainKey), '@@$name ');
        },
      );
    }
  });
}
