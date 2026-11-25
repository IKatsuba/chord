// Original TranscriptBack_test.tsx/state_test.ts scroll screen cases:
// ctrl+o/resize keep the top entry; keys/news/bottom. Multiple sessions and
// mount windows are omitted. Fake live scenarios are U7's window tests.
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/ui/transcript/tools/paths.dart';
import 'package:chord/session/transcript/text_run.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord/ui/transcript/scroll.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

const input = TextArea(
  autofocus: true,
  maxHeight: 1,
  unhandledKeys: {
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
  },
);
void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'scroll keys work above focused input and show the news rule at $size',
      (t) async {
        final scroll = ScrollController(follow: Follow.bottom);
        final state = ValueNotifier(
          model.Transcript(
            entries: [
              for (var i = 0; i < 60; i++) model.UserEntry('t', 'prompt $i'),
            ],
          ),
        );
        addTearDown(scroll.dispose);
        addTearDown(state.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: state,
            builder: (context) => Transcript(
              transcript: state.value,
              controller: scroll,
              footer: input,
            ),
          ),
          size: size,
        );
        expect(scroll.isFollowing, isTrue);
        expect(t.screen, shows('prompt 59'));
        await t.press('pageup');
        expect(scroll.isFollowing, isFalse);
        expect(t.screen, shows('lines below'));
        final top = t.screen.lines.first;
        state.value = model.Transcript(
          entries: [
            ...state.value.entries,
            for (var i = 60; i < 160; i++) model.UserEntry('t', 'prompt $i'),
          ],
        );
        applyScrollEffect(scroll, ScrollEffect.news);
        await t.pump();
        expect(t.screen.lines.first, top);
        expect(t.screen, shows('↓ new output'));
        await t.press('shift+up');
        final offset = scroll.offset;
        await t.press('up');
        expect(scroll.offset, offset);
        await t.press('shift+home');
        expect(scroll.offset, 0);
        expect(t.screen, shows('prompt 0'));
        await t.press('shift+end');
        expect(scroll.isFollowing, isTrue);
        expect(scroll.hasNews, isFalse);
        expect(t.screen, shows('prompt 159'));
        await t.press('home');
        expect(scroll.offset, 0);
        await t.press('end');
        expect(scroll.isFollowing, isTrue);
        await t.press('shift+pageup');
        expect(scroll.isFollowing, isFalse);
        await t.press('shift+pagedown');
        expect(scroll.isFollowing, isTrue);
      },
    );
    testWidgets('ctrl+o and resize retain the anchored entry at $size', (
      t,
    ) async {
      final scroll = ScrollController(follow: Follow.bottom);
      addTearDown(scroll.dispose);
      final transcript = model.Transcript(
        entries: [
          model.ThoughtEntry('t', TextRun.empty.plus('a\nb\nc\nd\ne')),
          for (var i = 0; i < 70; i++) model.UserEntry('t', 'prompt $i'),
        ],
      );
      await t.pumpWidget(
        Transcript(transcript: transcript, controller: scroll, footer: input),
        size: size,
      );
      scroll.jumpTo(scroll.itemTop(30) + 1);
      await t.pump();
      final top = t.screen.lines.first;
      expect(top, contains('prompt 29'));
      await t.press('ctrl+o');
      expect(t.screen.lines.first, top);
      await t.resize(const Size(80, 24));
      expect(t.screen.lines.first, top);
      await t.press('ctrl+o');
      expect(t.screen.lines.first, top);
      applyScrollEffect(scroll, ScrollEffect.bottom);
      await t.pump();
      expect(scroll.isFollowing, isTrue);
      expect(t.screen, shows('prompt 69'));
    });
    testWidgets(
      'fitting transcript has no rule and open assistant renders at $size',
      (t) async {
        final scroll = ScrollController(follow: Follow.bottom);
        addTearDown(scroll.dispose);
        await t.pumpWidget(
          Transcript(
            controller: scroll,
            transcript: model.Transcript(
              turn: const model.Working('t', 0),
              entries: [
                model.AssistantEntry(
                  't',
                  TextRun.empty.plus('```dart\nfinal x = 1;\n'),
                ),
              ],
            ),
            footer: input,
          ),
          size: size,
        );
        expect(scroll.isFollowing, isTrue);
        expect(t.screen, shows('final x = 1;'));
        expect(t.screen, isNot(shows('lines below')));
        await t.press('pageup');
        expect(scroll.isFollowing, isTrue);
      },
    );
  }
  testWidgets(
    'offscreen tool extent updates when its turn settles without new entries',
    (t) async {
      final scroll = ScrollController(follow: Follow.bottom);
      final entries = <model.Entry>[
        const model.ToolEntry(
          't',
          model.ToolCall('a', title: 'Run', status: 'in_progress'),
        ),
        for (var i = 0; i < 60; i++) model.UserEntry('t', 'prompt $i'),
      ];
      final state = ValueNotifier(
        model.Transcript(entries: entries, turn: const model.Working('t', 0)),
      );
      addTearDown(scroll.dispose);
      addTearDown(state.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: state,
          builder: (context) => Transcript(
            transcript: state.value,
            controller: scroll,
            footer: input,
          ),
        ),
      );
      scroll.jumpTo(scroll.itemTop(30) + 1);
      await t.pump();
      final top = t.screen.lines.first;
      final total = scroll.contentRows;
      final offset = scroll.offset;
      expect(scroll.itemRows(0), 3);
      state.value = state.value.withTurn(const model.Idle());
      await t.pump();
      expect(state.value.entries, same(entries));
      expect(scroll.itemRows(0), 2);
      expect(scroll.contentRows, total - 1);
      expect(scroll.offset, offset - 1);
      expect(t.screen.lines.first, top);
    },
  );
  testWidgets(
    'changed display paths invalidate offscreen diff headline extents',
    (t) async {
      final scroll = ScrollController(follow: Follow.bottom);
      final directory = '/fixture/${'nested/' * 30}';
      final paths = ValueNotifier(
        pathView(directory, null, real: (path) => path),
      );
      final transcript = model.Transcript(
        entries: [
          model.ToolEntry(
            't',
            model.ToolCall(
              'a',
              title: 'Edit',
              status: 'completed',
              content: [
                acp.ToolCallContent.fromJson({
                  'type': 'diff',
                  'path': '${directory}a.ts',
                  'oldText': 'a',
                  'newText': 'b',
                }),
              ],
            ),
          ),
          for (var i = 0; i < 60; i++) model.UserEntry('t', 'prompt $i'),
        ],
      );
      addTearDown(scroll.dispose);
      addTearDown(paths.dispose);
      await t.pumpWidget(
        ListenableBuilder(
          listenable: paths,
          builder: (context) => Transcript(
            transcript: transcript,
            controller: scroll,
            paths: paths.value,
            footer: input,
          ),
        ),
      );
      scroll.jumpTo(scroll.itemTop(30) + 1);
      await t.pump();
      final top = t.screen.lines.first;
      final rows = scroll.itemRows(0), total = scroll.contentRows;
      paths.value = pathView('/elsewhere', null, real: (path) => path);
      await t.pump();
      expect(scroll.itemRows(0), greaterThan(rows));
      expect(scroll.contentRows, total + scroll.itemRows(0) - rows);
      expect(t.screen.lines.first, top);
    },
  );
  testWidgets('Below clips using the same middle mode at tiny widths', (
    t,
  ) async {
    await t.pumpWidget(
      const Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 12,
          height: 1,
          child: Below(ScrollState(content: 100, view: 20, top: 0, news: true)),
        ),
      ),
    );
    expect(t.screen.lines.first, '── ↓...elow');
  });
}
