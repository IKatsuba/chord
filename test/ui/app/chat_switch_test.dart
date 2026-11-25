// The chat switch (design CTUI-35, framework draft U4): each session keeps
// its own scroll controller and gets its own viewport, so a session shown
// again is where it was left, news that came while it was hidden is told,
// and what the other session had selected or picked ends with the switch.
// A child in front opens its transcript with its line and names itself on
// the prompt's top, as the original does.
import 'dart:async';

import 'package:chord/acp/connection.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/leaving.dart';
import 'package:chord/session/start_connection.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/window_agents.dart';
import 'package:chord/ui/app/scrolls.dart';
import 'package:chord/ui/app/selection.dart' as copy;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord/ui/app/window_fold.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:clock/clock.dart';
import 'package:test/test.dart';

import '../../session/conversation_fake.dart';
import 'code_pick_window_test.dart' show pickHint, pressBounded;
import 'editor_window_test.dart' show EditorTerminal, plainLaunch, settle;
import 'selection_window_test.dart' show cellOf, primary;

typedef _Window = ({
  StartConnection connection,
  int child,
  ScriptedSession session,
  SessionScrolls scrolls,
  List<String> copies,
});

/// The window over a main that never starts, with the child `parser`
/// behind it, opened a minute ago on a scripted session.
Future<_Window> _window(WidgetTester t, Size size) async {
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
  final session = ScriptedSession();
  final child = connection.agents.openChild(
    ChildInfo(
      id: 'a1',
      name: 'parser',
      runtime: 'fake',
      model: 'Fake Small',
      openedAt: clock.now().millisecondsSinceEpoch - 61000,
    ),
    (emit, key) {
      connection.fold.dispatch(AgentOpened(key));
      return Conversation(
        ({required onTraffic, required cancellationToken}) async => session,
      )..listen(emit);
    },
  )!;
  final scrolls = SessionScrolls();
  final copies = <String>[];
  await t.pumpWidget(
    TranscriptWindow(
      launch: plainLaunch,
      connection: connection,
      terminal: EditorTerminal(),
      scrolls: scrolls,
      copy: (text, _) {
        copies.add(text);
        return const copy.CopyResult.sent();
      },
    ),
    size: size,
  );
  await settle(t);
  return (
    connection: connection,
    child: child,
    session: session,
    scrolls: scrolls,
    copies: copies,
  );
}

Future<void> _show(WidgetTester t, StartConnection connection, int key) async {
  connection.fold.dispatch(SessionShown(key));
  await t.pump();
  await t.pump();
}

/// Main's transcript: [count] prompts, `history 0` the oldest, and [last].
void _history(StartConnection connection, {int count = 60, String? last}) {
  final old = connection.app.value;
  connection.app.value = AppState(
    start: old.start,
    transcript: model.Transcript(
      entries: [
        for (var i = 0; i < count; i++) model.UserEntry('u$i', 'history $i'),
        if (last != null) model.AssistantEntry('a', TextRun.empty.plus(last)),
      ],
    ),
  );
}

/// The oldest of main's prompts on screen.
String _top(WidgetTester t) => RegExp(
  r'history \d+',
).firstMatch(t.screen.lines.firstWhere((l) => l.contains('history ')))![0]!;

void main() {
  _testerChatLifetimes();
  _testerMessageCopies();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('main scrolled back, a child picked and main again: the same '
        'top entry, at $size', (t) async {
      final w = await _window(t, size);
      _history(w.connection);
      await t.pump();
      await t.press('pageup');
      await t.press('pageup');
      await t.pump();
      final top = _top(t);
      final screen = t.screen.lines.take(size.height - 10).toList();
      expect(top, isNot('history 0'));
      await _show(t, w.connection, w.child);
      expect(t.screen, isNot(shows('history ')));
      await _show(t, w.connection, mainKey);
      expect(_top(t), top);
      expect(t.screen.lines.take(size.height - 10).toList(), screen);
    });

    testWidgets('a resize while main was hidden keeps its top entry, at '
        '$size', (t) async {
      final w = await _window(t, size);
      _history(w.connection);
      await t.pump();
      await t.press('pageup');
      await t.press('pageup');
      await t.pump();
      final top = _top(t);
      await _show(t, w.connection, w.child);
      final narrow = Size(size.width - 20, size.height - 4);
      await t.resize(narrow);
      await t.pump();
      await _show(t, w.connection, mainKey);
      expect(_top(t), top);
    });

    testWidgets("news on a hidden child is told once it is picked again, the "
        "shown one's scroll untouched, at $size", (t) async {
      final w = await _window(t, size);
      await _show(t, w.connection, w.child);
      await t.type('go');
      await t.press('enter');
      await settle(t);
      w.session.chunk([for (var i = 0; i < 80; i++) 'line $i'].join('\n\n'));
      await settle(t);
      await t.press('pageup');
      await t.press('pageup');
      await t.pump();
      expect(t.screen, isNot(shows('new output')));
      final childScroll = w.scrolls.made(w.child)!;
      expect(childScroll.isFollowing, isFalse);
      await _show(t, w.connection, mainKey);
      final mainScroll = w.scrolls.made(mainKey)!;
      final mainState = mainScroll.state;
      w.session.chunk('\n\nmore while hidden');
      await settle(t);
      expect(childScroll.hasNews, isTrue);
      expect(mainScroll.state, mainState);
      await _show(t, w.connection, w.child);
      expect(t.screen, shows('↓ new output'));
    });

    testWidgets('a selection in main is gone after a switch, at $size', (
      t,
    ) async {
      final w = await _window(t, size);
      _history(w.connection, count: 3);
      await t.pump();
      final start = cellOf(t, 'history 1');
      final end = cellOf(t, 'history 1', end: true);
      final plain = t.screen.styleAt(start.x, start.y);
      await t.mouse(primary(MouseEventKind.press, start));
      await t.mouse(primary(MouseEventKind.move, end));
      await t.pump();
      expect(t.screen.styleAt(start.x, start.y), isNot(plain));
      await _show(t, w.connection, w.child);
      // Let go over the child: nothing of main's is copied.
      await t.mouse(primary(MouseEventKind.release, end));
      await t.pump();
      expect(w.copies, isEmpty);
      await _show(t, w.connection, mainKey);
      final at = cellOf(t, 'history 1');
      expect(t.screen.styleAt(at.x, at.y), plain);
    });

    testWidgets("a selection in main's header is gone after a round trip, "
        'though the header is there again, at $size', (t) async {
      final w = await _window(t, size);
      final start = cellOf(t, 'shortcuts');
      final end = cellOf(t, 'shortcuts', end: true);
      final plain = t.screen.styleAt(start.x, start.y);
      await t.mouse(primary(MouseEventKind.press, start));
      await t.mouse(primary(MouseEventKind.move, end));
      await t.pump();
      expect(t.screen.styleAt(start.x, start.y), isNot(plain));
      await _show(t, w.connection, w.child);
      await _show(t, w.connection, mainKey);
      expect(t.screen.styleAt(start.x, start.y), plain);
      await t.mouse(primary(MouseEventKind.release, end));
      await t.pump();
      expect(w.copies, isEmpty);
    });

    testWidgets('a code block picked in main ends with the switch, at $size', (
      t,
    ) async {
      final w = await _window(t, size);
      _history(w.connection, count: 1, last: '```\npicked code\n```');
      await t.pump();
      await pressBounded(t, 'ctrl+x b');
      expect(t.screen, shows(pickHint));
      await _show(t, w.connection, w.child);
      expect(t.screen, isNot(shows(pickHint)));
      await _show(t, w.connection, mainKey);
      expect(t.screen, isNot(shows(pickHint)));
    });

    testWidgets("a closed child's controller is disposed, no listener left, "
        'at $size', (t) async {
      final w = await _window(t, size);
      await _show(t, w.connection, w.child);
      final scroll = w.scrolls.made(w.child)!;
      expect(scroll.hasListeners, isTrue);
      await _show(t, w.connection, mainKey);
      w.connection.agents.closeChild(w.child).ignore();
      w.connection.fold.dispatch(SessionClosed(w.child, mainKey));
      await settle(t);
      expect(scroll.isDisposed, isTrue);
      expect(scroll.hasListeners, isFalse);
      expect(w.scrolls.made(w.child), isNull);
      expect(w.scrolls.made(mainKey)!.isDisposed, isFalse);
    });

    testWidgets("a cleared child's controller is replaced, hidden or shown, "
        'at $size', (t) async {
      final w = await _window(t, size);
      await _show(t, w.connection, w.child);
      final first = w.scrolls.made(w.child)!;
      await _show(t, w.connection, mainKey);
      w.connection.agents.conversationOf(w.child)!.clear().ignore();
      await settle(t);
      expect(first.isDisposed, isTrue);
      expect(first.hasListeners, isFalse);
      final second = w.scrolls.made(w.child);
      expect(second, isNotNull);
      expect(second!.isFollowing, isTrue);
      await _show(t, w.connection, w.child);
      expect(w.scrolls.made(w.child), same(second));
      w.connection.agents.conversationOf(w.child)!.clear().ignore();
      await settle(t);
      expect(second.isDisposed, isTrue);
      expect(second.hasListeners, isFalse);
      expect(w.scrolls.made(w.child)!.hasListeners, isTrue);
    });

    testWidgets("a child's transcript opens with its line, one column in, "
        'and its name on the prompt, at $size', (t) async {
      final w = await _window(t, size);
      expect(t.screen.lines.first, isNot(contains('parser')));
      await _show(t, w.connection, w.child);
      // As the original's capture (agents-list/orig-120x40-parser-child-line).
      expect(
        t.screen.lines.first,
        ' parser · fake · Fake Small · opened by main 1m ago',
      );
      expect(t.screen.styleAt(0, 0).isBold, isFalse);
      expect(t.screen.styleAt(1, 0).isBold, isTrue);
      expect(t.screen.styleAt(8, 0).isDim, isTrue);
      final top = t.screen.lines.indexWhere((l) => l.startsWith('╭─ parser '));
      expect(top, greaterThan(0), reason: t.screen.text);
      expect(
        t.screen.lines[top],
        '╭─ parser ${'─' * (size.width - 'parser'.length - 5)}╮',
      );
      expect(t.screen.styleAt(3, top).isBold, isTrue);
      await _show(t, w.connection, mainKey);
      expect(t.screen.lines.first, isNot(contains('parser')));
      expect(t.screen, isNot(shows('╭─ parser')));
    });
  }
}

void _testerChatLifetimes() {
  group('CTUI-35 tester: hidden bursts and mount lifetime', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a thousand hidden updates keep both scroll authorities at $size',
        (t) async {
          final w = await _window(t, size);
          _history(w.connection);
          await t.pump();
          await t.press('pageup');
          await t.press('pageup');
          final mainTop = _top(t);
          final mainScroll = w.scrolls.made(mainKey)!;
          await _show(t, w.connection, w.child);
          await t.type('go');
          await t.press('enter');
          await settle(t);
          w.session.chunk(
            [for (var i = 0; i < 80; i++) 'child row $i'].join('\n\n'),
          );
          await settle(t);
          await t.press('pageup');
          await t.press('pageup');
          final childScroll = w.scrolls.made(w.child)!;
          expect(childScroll.isFollowing, isFalse);
          await _show(t, w.connection, mainKey);
          final before = mainScroll.state;
          for (var i = 0; i < 1000; i++) {
            w.session.chunk('\n\nburst $i');
          }
          await settle(t);
          expect(mainScroll.state, before);
          expect(_top(t), mainTop);
          expect(childScroll.hasNews, isTrue);
          await t.resize(Size(size.width - 20, size.height - 4));
          await _show(t, w.connection, w.child);
          expect(w.scrolls.made(w.child), same(childScroll));
          expect(t.screen, shows('↓ new output'));
          await t.press('end');
          await t.pump();
          expect(t.screen, shows('burst 999'));
          expect(childScroll.hasNews, isFalse);
          expect(childScroll.isFollowing, isTrue);
          await _show(t, w.connection, mainKey);
          expect(w.scrolls.made(mainKey), same(mainScroll));
          expect(_top(t), mainTop);
        },
      );

      testWidgets(
        'removing a window while a child streams disposes every controller at $size',
        (t) async {
          final w = await _window(t, size);
          await _show(t, w.connection, w.child);
          await t.type('go');
          await t.press('enter');
          await settle(t);
          w.session.chunk('before removal');
          await settle(t);
          final controllers = [
            for (final key in w.scrolls.keys) w.scrolls.made(key)!,
          ];
          expect(controllers, hasLength(2));
          await t.pumpWidget(const SizedBox(), size: size);
          expect(w.scrolls.keys, isEmpty);
          for (final controller in controllers) {
            expect(controller.isDisposed, isTrue);
            expect(controller.hasListeners, isFalse);
          }
          w.session.chunk('late output after removal');
          w.session.turns.single.answer();
          await settle(t);
          expect(t.screen.text.trim(), isEmpty);
          expect(w.scrolls.keys, isEmpty);
        },
      );
    }
  });
}

void _testerMessageCopies() {
  group('CTUI-35 tester: message selection', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets('received code copies bare with message gaps at $size', (
        t,
      ) async {
        final w = await _window(t, size);
        await _show(t, w.connection, w.child);
        final conversation = w.connection.agents.conversationOf(w.child)!;
        conversation.deliver(
          const model.MessageFrom('main', reachable: true),
          'First.\n\n```sh\nls -la\n```\n\nSecond.',
        );
        await settle(t);
        final start = cellOf(t, 'First.');
        final end = cellOf(t, 'Second.', end: true);
        await t.mouse(primary(MouseEventKind.press, start));
        await t.mouse(primary(MouseEventKind.move, end));
        await t.mouse(primary(MouseEventKind.release, end));
        await t.pump();
        expect(w.copies, ['First.\n \nls -la\n \nSecond.']);
      });
    }
  });
}
