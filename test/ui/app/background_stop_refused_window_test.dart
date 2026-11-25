// A stop x sent to an agent's subagent that fails later: said on the hint
// line of the window that asked, as the original's sessions.ts stopBackground
// says it; nothing once that window is gone or shows another connection.
import 'dart:async';

import 'package:chord/session/start_connection.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../../session/conversation_fake.dart';
import 'editor_window_test.dart' show EditorTerminal, settle;
import 'front_routing_test.dart' show window;

/// The window over a child whose subagent runs, its stop held on [notice],
/// with the background view open on it.
Future<({StartConnection connection, ScriptedSession session})> _stopping(
  WidgetTester t,
  Size size,
  Completer<void> notice,
) async {
  final w = await window(t, size, EditorTerminal());
  w.session.stopping = (_) => notice.future;
  w.session.say({
    'sessionUpdate': 'subagent_update',
    'sessionId': 'worker',
    'title': 'watcher',
    'description': 'Watch the build',
    'state': {'state': 'running'},
    'capabilities': {'cancel': <String, Object?>{}},
  });
  await settle(t);
  // Down the list, main then the child, to the summary line, which opens
  // the view.
  for (var i = 0; i < 3; i++) {
    await t.press('down');
  }
  await t.press('enter');
  await t.pump();
  expect(t.screen.text, contains('❯ Watch the build'));
  await t.press('x');
  await t.pump();
  expect(w.session.stopped, ['worker']);
  expect(t.screen.text, contains('■ stopping'));
  return (connection: w.connection, session: w.session);
}

void main() {
  testerLateRefusalOwnership();
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('a stop that fails later says so on the hint line, whole, '
        'the row running again, at $size', (t) async {
      final notice = Completer<void>();
      await _stopping(t, size, notice);
      notice.completeError(StateError('Broken pipe\ntransport detail'));
      await settle(t);
      expect(t.screen.text, contains('could not stop: Broken pipe'));
      expect(t.screen.text, contains('transport detail'));
      expect(t.screen.text, isNot(contains('■ stopping')));
      expect(t.screen.text, contains('running'));
    });

    testWidgets('a stop that fails once its window is gone says nothing, at '
        '$size', (t) async {
      final notice = Completer<void>();
      final w = await _stopping(t, size, notice);
      expect(w.connection.app.value.backgroundView?.stopping, isNotNull);
      await t.pumpWidget(const SizedBox(), size: size);
      notice.completeError(StateError('Broken pipe'));
      await settle(t);
      expect(w.connection.app.value.backgroundView?.hint, isNull);
    });
  }
}

void testerLateRefusalOwnership() {
  group('CTUI-83 tester: late refusal ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'duplicate x sends once and a refusal cannot follow focus at $size',
        (t) async {
          final notice = Completer<void>();
          final w = await _stopping(t, size, notice);
          await t.press('x');
          expect(w.session.stopped, ['worker']);
          w.session.say({
            'sessionUpdate': 'subagent_update',
            'sessionId': 'other',
            'description': 'Another worker',
            'state': {'state': 'running'},
            'capabilities': {'cancel': <String, Object?>{}},
          });
          await settle(t);
          await t.press('down');
          expect(t.screen.text, contains('❯ Another worker'));
          notice.completeError(StateError('obsolete refusal'));
          await settle(t);
          expect(w.connection.app.value.backgroundView?.hint, isNull);
          expect(t.screen.text, isNot(contains('obsolete refusal')));
          expect(t.screen.text, contains('❯ Another worker'));
        },
      );

      testWidgets(
        'a rebound connection keeps its own pending stop when the old one fails at $size',
        (t) async {
          final oldNotice = Completer<void>();
          final old = await _stopping(t, size, oldNotice);
          final freshNotice = Completer<void>();
          final fresh = await _stopping(t, size, freshNotice);
          expect(identical(old.connection, fresh.connection), isFalse);
          oldNotice.completeError(StateError('old connection refusal'));
          await settle(t);
          expect(fresh.connection.app.value.backgroundView?.hint, isNull);
          expect(t.screen.text, contains('■ stopping'));
          freshNotice.completeError(StateError('current refusal'));
          await settle(t);
          expect(t.screen.text, contains('could not stop: current refusal'));
          expect(t.screen.text, isNot(contains('old connection refusal')));
        },
      );
    }
  });
}
