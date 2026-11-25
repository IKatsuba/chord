import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'keymap_window_test.dart' show window;
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/keys.dart' as keys;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/prompt/history.dart';
import 'package:chord/session/conversation.dart' show QueuedPrompt;
import 'package:chord/ui/prompt/search.dart' show emptySearch;

Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 5; i++) {
    await t.pump();
  }
}

void main() {
  group('tester: active context key ownership', () {
    test(
      'Tab identity follows search, completion, queue, then plain draft',
      () {
        keys.KeyContext context(AppState state, {bool completing = false}) =>
            keys.KeyContext(
              state: state,
              completing: completing,
              history: const History(),
              rows: 24,
              columns: 80,
            );
        const busy = AppState(
          transcript: model.Transcript(turn: model.Working('turn', 1)),
          queue: [QueuedPrompt('queued', 'next')],
        );
        final queued = context(busy);
        final completing = context(busy, completing: true);
        final searching = context(
          const AppState(search: emptySearch),
          completing: true,
        );
        expect(keys.windowAction('tab', context(const AppState())), isNull);
        expect(keys.windowAction('tab', queued), 'chat:steer');
        expect(
          keys.keySteps(Chord.parse('tab'), queued).single,
          isA<keys.Steer>(),
        );
        expect(keys.windowAction('tab', completing), 'autocomplete:accept');
        expect(
          keys.keySteps(Chord.parse('tab'), completing).single,
          isA<keys.CompleteCommand>(),
        );
        expect(keys.windowAction('tab', searching), 'historySearch:accept');
      },
    );
    for (final size in const [Size(80, 24), Size(120, 40)]) {
      testWidgets('mention finder owns all four printable actions $size', (
        t,
      ) async {
        final c = await window(
          t,
          size,
          [
            {
              'context': 'Autocomplete',
              'bindings': {
                'j': 'autocomplete:next',
                'k': 'autocomplete:previous',
                'x': 'autocomplete:accept',
                'z': 'autocomplete:dismiss',
              },
            },
          ],
          files: ['alpha', 'beta'],
        );
        await t.type('@');
        await settle(t);
        await t.press('j k j x');
        expect(c.app.value.draft, '@beta ');
        await t.press('ctrl+c');
        await t.type('@');
        await settle(t);
        await t.press('z');
        expect(c.app.value.draft, '@');
        expect(t.screen.text, isNot(contains('alpha')));
        await t.type('z');
        expect(c.app.value.draft, '@z');
      });

      testWidgets(
        'list chord is typed outside its context and owns keys inside $size',
        (t) async {
          final c = await window(
            t,
            size,
            [
              {
                'context': 'Autocomplete',
                'bindings': {'g x': 'autocomplete:accept'},
              },
            ],
            files: ['界🙂é.md'],
          );
          await t.type('gx');
          expect(c.app.value.draft, 'gx');
          await t.press('ctrl+c');
          await t.type('@');
          await settle(t);
          await t.press('g');
          expect(c.app.value.draft, '@');
          await t.press('x');
          expect(c.app.value.draft, '@界🙂é.md ');
          expect(c.app.value.transcript.entries, isEmpty);
        },
      );

      testWidgets(
        'shifted punctuation moves completion without editing $size',
        (t) async {
          final c = await window(
            t,
            size,
            [
              {
                'context': 'Autocomplete',
                'bindings': {'#': 'autocomplete:next'},
              },
            ],
            files: ['alpha', 'beta'],
          );
          await t.type('@');
          await settle(t);
          t.host.handleKey(const KeyEvent('#', shift: true));
          await t.pump();
          expect(c.app.value.draft, '@');
          await t.press('tab');
          expect(c.app.value.draft, '@beta ');
        },
      );

      testWidgets(
        'Help owns a chord until dismissed then letters type again $size',
        (t) async {
          final c = await window(t, size, [
            {
              'context': 'Help',
              'bindings': {'g q': 'help:dismiss', 'escape': null},
            },
          ]);
          await t.press('?');
          await t.press('esc');
          expect(c.app.value.shortcuts.help, isTrue);
          await t.press('g q');
          expect(c.app.value.shortcuts.help, isFalse);
          expect(c.app.value.draft, isEmpty);
          await t.type('gq');
          expect(c.app.value.draft, 'gq');
        },
      );
    }
  });
}
