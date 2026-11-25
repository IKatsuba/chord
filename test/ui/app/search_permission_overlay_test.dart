import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../../tool/steering.dart';
import 'search_window_test.dart' show editor;
import 'steering_window_test.dart' show connected, send;
import 'window_fake_test.dart' show until;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final searching in [false, true]) {
      testWidgets(
        'permission arrival retains rejection cue with search=$searching $size',
        (t) async {
          final f = await connected(t, size);
          await send(t, '/review');
          await t.type('saved 界😀');
          await t.press('left');
          final saved = editor(t),
              draft = editor(t).text,
              cursor = editor(t).cursor;
          if (searching) {
            await t.press('ctrl+r');
            await t.type('/re');
            expect(t.screen, shows('search prompts: /re'));
          }
          f.agent.askPermission();
          await until(() => f.agent.hasPermission);
          final before = t.inputLayoutPasses;
          await t.pump();
          expect(t.inputLayoutPasses - before, lessThanOrEqualTo(2));
          expect(t.screen, shows('Approve notes'));
          expect(t.screen, shows('Esc to reject'));
          expect(
            t.screen.lines.where((line) => line.trimLeft().startsWith('╰')),
            hasLength(2),
          );
          expect(f.connection.app.value.search, isNull);
          expect(editor(t), same(saved));
          expect((saved.text, saved.cursor), (draft, cursor));
          expect(t.screen, isNot(shows('search prompts:')));
          await t.press('tab');
          await t.type('z');
          expect((saved.text, saved.cursor), (draft, cursor));
          await t.press('enter');
          await until(() => !f.agent.hasPermission);
          await t.pump();
          expect(f.connection.app.value.search, isNull);
          expect((saved.text, saved.cursor), (draft, cursor));
          expect(
            f.agent.requests.where((r) => r['method'] == 'session/prompt'),
            hasLength(1),
          );
          expect(
            f.agent.requests.where((r) => r['method'] == '_session/steering'),
            isEmpty,
          );
          await t.press('ctrl+z');
          expect(saved.text, 'saved 界');
          await t.press('ctrl+y');
          expect(saved.text, draft);
        },
      );
    }
  }
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'held-between permission leaves query until CtrlX A attends $size',
      (t) async {
        final f = await connected(t, size);
        await t.type('saved 界😀');
        await t.press('left');
        final saved = editor(t),
            draft = editor(t).text,
            cursor = editor(t).cursor;
        await t.press('ctrl+r');
        await t.type('query');
        final query = f.connection.app.value.search;
        f.agent.askPermission();
        await until(() => f.agent.hasPermission);
        await t.pump();
        expect(f.connection.app.value.search, same(query));
        await t.press('ctrl+x a');
        expect(f.connection.app.value.search, isNull);
        expect(editor(t), same(saved));
        expect((saved.text, saved.cursor), (draft, cursor));
        expect(t.screen, shows('Esc to reject'));
        await t.press('enter');
        await until(() => !f.agent.hasPermission);
        await t.pump();
        expect(f.connection.app.value.search, isNull);
        expect((saved.text, saved.cursor), (draft, cursor));
        expect(
          f.agent.requests.where((r) => r['method'] == 'session/prompt'),
          isEmpty,
        );
      },
    );
  }
  testWidgets(
    'late old permission after connection swap cannot close new search',
    (t) async {
      final first = await SteeringFixture.create();
      final second = await SteeringFixture.create();
      final front = ValueNotifier(first);
      addTearDown(() async {
        await first.close();
        await second.close();
        front.dispose();
        for (final f in [first, second]) {
          expect(await f.directory.exists(), isFalse);
          expect(f.agents.every((a) => a.process.exited), isTrue);
        }
      });
      await until(
        () =>
            first.connection.app.value.start.phase == StartPhase.connected &&
            second.connection.app.value.start.phase == StartPhase.connected,
      );
      await t.pumpWidget(
        ListenableBuilder(
          listenable: front,
          builder: (_) => front.value.view(),
        ),
      );
      await send(t, 'old reference');
      await t.type('saved');
      await t.press('ctrl+r');
      await t.type('old');
      front.value = second;
      await t.pump();
      await t.press('ctrl+c');
      await send(t, 'new reference');
      await t.type('new saved');
      await t.press('ctrl+r');
      await t.type('new');
      final current = second.connection.app.value.search,
          shown = editor(t).text;
      first.agent.askPermission();
      await until(() => first.agent.hasPermission);
      await t.pump();
      expect(second.connection.app.value.search, same(current));
      expect(editor(t).text, shown);
      await first.close();
      await t.pump();
      expect(second.connection.app.value.search, same(current));
      second.agent.askPermission();
      await until(() => second.agent.hasPermission);
      await t.pump();
      expect(second.connection.app.value.search, isNull);
      await t.pumpWidget(const SizedBox());
      await second.close();
      await t.pump();
    },
  );
}
