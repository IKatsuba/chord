import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord/ui/transcript/scroll.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const _keys = {
  'home',
  'end',
  'shift+home',
  'shift+end',
  'shift+up',
  'shift+down',
  'pageup',
  'pagedown',
  'shift+pageup',
  'shift+pagedown',
};
TextArea _input({FocusNode? node}) => TextArea(
  focusNode: node,
  autofocus: node == null,
  maxHeight: 1,
  unhandledKeys: _keys,
);
model.Transcript _entries({String label = 'row'}) => model.Transcript(
  entries: [
    model.ThoughtEntry('t', TextRun.empty.plus('first\nsecond\nthird')),
    for (var i = 0; i < 120; i++) model.UserEntry('t', '$label $i'),
  ],
);

void main() {
  group('tester U6 transcript integration boundaries', () {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      testWidgets('every scroll alias moves through focused input at $size', (
        t,
      ) async {
        final scroll = ScrollController(follow: Follow.bottom);
        addTearDown(scroll.dispose);
        await t.pumpWidget(
          Transcript(
            transcript: _entries(),
            controller: scroll,
            footer: _input(),
          ),
          size: size,
        );
        final page = scroll.viewRows - 2;
        for (final (key, delta) in [
          ('pageup', -page),
          ('shift+pageup', -page),
          ('pagedown', page),
          ('shift+pagedown', page),
          ('shift+up', -1),
          ('shift+down', 1),
          ('up', 0),
          ('down', 0),
        ]) {
          scroll.jumpTo(100);
          await t.pump();
          await t.press(key);
          expect(scroll.offset, 100 + delta, reason: key);
        }
        for (final key in ['home', 'shift+home']) {
          await t.press(key);
          expect(scroll.offset, 0);
        }
        for (final key in ['end', 'shift+end']) {
          scroll.toTop();
          await t.pump();
          await t.press(key);
          expect(scroll.isFollowing, isTrue);
        }
      });

      testWidgets(
        'two transcripts route focus and details independently at $size',
        (t) async {
          final first = ScrollController(follow: Follow.bottom);
          final second = ScrollController(follow: Follow.bottom);
          final firstFocus = FocusNode();
          final secondFocus = FocusNode();
          await t.pumpWidget(
            Row(
              children: [
                Expanded(
                  child: Transcript(
                    transcript: _entries(label: 'first'),
                    controller: first,
                    footer: _input(node: firstFocus),
                  ),
                ),
                Expanded(
                  child: Transcript(
                    transcript: _entries(label: 'second'),
                    controller: second,
                    footer: _input(node: secondFocus),
                  ),
                ),
              ],
            ),
            size: size,
          );
          final firstRows = first.contentRows, secondRows = second.contentRows;
          firstFocus.requestFocus();
          await t.press('pageup');
          expect(first.isFollowing, isFalse);
          expect(second.isFollowing, isTrue);
          await t.press('ctrl+o');
          expect(first.contentRows, greaterThan(firstRows));
          expect(second.contentRows, secondRows);
          final held = first.offset;
          secondFocus.requestFocus();
          await t.press('pageup');
          expect(first.offset, held);
          expect(second.isFollowing, isFalse);
          await t.press('ctrl+o');
          expect(second.contentRows, greaterThan(secondRows));
          firstFocus.requestFocus();
          await t.press('end');
          expect(first.isFollowing, isTrue);
          expect(second.isFollowing, isFalse);
          t.dispose();
          first.dispose();
          second.dispose();
          firstFocus.dispose();
          secondFocus.dispose();
        },
      );

      testWidgets('thousand updates preserve held entry and news at $size', (
        t,
      ) async {
        final scroll = ScrollController(follow: Follow.bottom);
        final state = ValueNotifier(_entries());
        addTearDown(scroll.dispose);
        addTearDown(state.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: state,
            builder: (_) => Transcript(
              transcript: state.value,
              controller: scroll,
              footer: _input(),
            ),
          ),
          size: size,
        );
        scroll.jumpTo(scroll.itemTop(40) + 1);
        await t.pump();
        final top = t.screen.lines.first;
        final base = state.value.entries;
        for (var i = 0; i < 1000; i++) {
          state.value = model.Transcript(
            entries: [...base, model.UserEntry('t', 'latest $i 界👩‍💻e\u0301')],
          );
          applyScrollEffect(scroll, ScrollEffect.news);
        }
        await t.pump();
        expect(t.screen.lines.first, top);
        expect(scroll.hasNews, isTrue);
        expect(t.screen, shows('new output'));
        final before = scroll.state;
        applyScrollEffect(scroll, ScrollEffect.none);
        expect(scroll.state, before);
        applyScrollEffect(scroll, ScrollEffect.bottom);
        await t.pump();
        expect(t.screen, shows('latest 999 界👩‍💻e\u0301'));
        expect(scroll.hasNews, isFalse);
        await t.resize(const Size(0, 0));
        expect(t.screen.text, isEmpty);
        await t.resize(const Size(1, 1));
        await t.resize(size);
        expect(t.screen, shows('latest 999 界👩‍💻e\u0301'));
      });
    }

    testWidgets('replacing controller detaches all old listeners and actions', (
      t,
    ) async {
      final first = ScrollController(follow: Follow.bottom);
      final second = ScrollController(follow: Follow.bottom);
      final selected = ValueNotifier(first);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: selected,
          builder: (_) => Transcript(
            transcript: _entries(),
            controller: selected.value,
            footer: _input(),
          ),
        ),
      );
      expect(first.hasListeners, isTrue);
      selected.value = second;
      await t.pump();
      expect(first.hasListeners, isFalse);
      expect(second.hasListeners, isTrue);
      expect(() => first.itemRows(0), throwsStateError);
      final oldState = first.state;
      await t.press('home');
      expect(second.offset, 0);
      expect(first.state, oldState);
      await t.pumpWidget(Text('removed'));
      expect(second.hasListeners, isFalse);
      first.markNews();
      second.markNews();
      await t.pump();
      expect(t.screen.text, 'removed');
      selected.dispose();
      first.dispose();
      second.dispose();
    });

    testWidgets('all turn transitions invalidate offscreen running extents', (
      t,
    ) async {
      final scroll = ScrollController(follow: Follow.bottom);
      final entries = <model.Entry>[
        const model.ToolEntry(
          't',
          model.ToolCall('a', title: 'Run', status: 'in_progress'),
        ),
        ..._entries().entries,
      ];
      final state = ValueNotifier(
        model.Transcript(entries: entries, turn: const model.Working('t', 0)),
      );
      addTearDown(scroll.dispose);
      addTearDown(state.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: state,
          builder: (_) => Transcript(
            transcript: state.value,
            controller: scroll,
            footer: _input(),
          ),
        ),
      );
      scroll.jumpTo(scroll.itemTop(50) + 1);
      await t.pump();
      final top = t.screen.lines.first;
      for (final (turn, rows) in <(model.TurnState, int)>[
        (const model.Cancelling('t', 0, 1), 3),
        (const model.AwaitingPermission('t', 0, [], between: true), 2),
        (const model.Working('other', 0), 2),
        (const model.Working('t', 0), 3),
        (const model.Idle(), 2),
      ]) {
        state.value = state.value.withTurn(turn);
        await t.pump();
        expect(state.value.entries, same(entries));
        expect(scroll.itemRows(0), rows);
        expect(t.screen.lines.first, top);
      }
    });

    testWidgets('Below middle marker uses base style between accented spans', (
      t,
    ) async {
      for (final width in [0, 1, 3, 12, 80, 120]) {
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              height: 1,
              child: const Below(
                ScrollState(content: 100, view: 20, news: true),
              ),
            ),
          ),
          size: const Size(120, 40),
        );
        if (width < 4) {
          expect(t.screen.text, isEmpty);
        } else if (width == 12) {
          expect(t.screen.lines.first, '── ↓...elow');
          for (var x = 4; x < 7; x++) {
            expect(t.screen.styleAt(x, 0).isDim, isFalse);
            expect(t.screen.styleAt(x, 0).isBold, isFalse);
          }
        } else {
          expect(t.screen.lines.first, contains('↓ new output'));
          expect(t.screen.styleAt(3, 0).isBold, isTrue);
          expect(t.screen.lines[1], isEmpty);
        }
      }
    });
  });
}
