import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/teams.dart';
import 'package:chord/ui/transcript/transcript.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

/// What one session gives its transcript, as the window passes it.
class Shown {
  Shown(this.name, this.last);

  final String name;
  model.Entry last;
  String? chordServer;
  String? agent;
  int windowRows = 40;
  final controller = ScrollController(follow: Follow.bottom);

  /// Fillers, then [last], so a view at the top leaves it below.
  model.Transcript get transcript => model.Transcript(
    entries: [
      for (var i = 0; i < 60; i++) model.UserEntry('t', 'filler $i'),
      last,
    ],
  );
}

/// The picked session's transcript, keyed by it as the window keys it, so
/// a switch builds a new list over that session's retained controller.
class Window {
  final picked = ValueNotifier<Shown?>(null);

  Widget get widget => ListenableBuilder(
    listenable: picked,
    builder: (_) {
      final s = picked.value!;
      return Transcript(
        key: ValueKey(('transcript', s.name)),
        transcript: s.transcript,
        controller: s.controller,
        chordServer: s.chordServer,
        agent: s.agent,
        windowRows: s.windowRows,
      );
    },
  );

  Future<void> show(WidgetTester t, Shown s) async {
    picked.value = s;
    await t.pump();
  }

  /// [s] shown at the top, and its screen.
  Future<List<String>> top(WidgetTester t, Shown s) async {
    await show(t, s);
    s.controller.toTop();
    await t.pump();
    return List.of(t.screen.lines);
  }
}

/// Session `a`'s screen at the top after it was left there, [change] made
/// to it while `b` was shown; and the same, measured fresh.
Future<(List<String>, List<String>, int, int)> switched(
  WidgetTester t,
  Size size,
  model.Entry last,
  void Function(Shown a) change,
) async {
  final w = Window();
  final a = Shown('a', last);
  final b = Shown('b', const model.UserEntry('t', 'b last'));
  w.picked.value = a;
  await t.pumpWidget(w.widget, size: size);
  await w.top(t, a);
  await w.show(t, b);
  change(a);
  final reused = await w.top(t, a);
  final fresh = Shown('fresh', a.last)
    ..chordServer = a.chordServer
    ..agent = a.agent
    ..windowRows = a.windowRows;
  await w.show(t, fresh);
  final freshRows = fresh.controller.contentRows;
  return (reused, await w.top(t, fresh), a.controller.contentRows, freshRows);
}

/// The rows [last] takes in a fresh transcript after [change].
Future<int> rowsOf(
  WidgetTester t,
  Size size,
  model.Entry last, [
  void Function(Shown s)? change,
]) async {
  final w = Window();
  final s = Shown('a', last);
  change?.call(s);
  w.picked.value = s;
  await t.pumpWidget(w.widget, size: size);
  return s.controller.itemRows(60);
}

final sendMessage = model.ToolEntry(
  't',
  model.ToolCall(
    'send',
    title: 'mcp__chord__send_message',
    rawInput: {'to': 'reviewer', 'text': 'word ' * 60},
    status: 'completed',
  ),
);

const linkAsked = model.ElicitationEntry(
  't',
  model.LinkWait('l', 'Sign in to continue', 'https://example.com'),
  model.ElicitationOutcome.declined,
);

final teamShown = model.TeamShownEntry(
  't',
  'team show ship',
  model.ShownTeam(
    name: 'ship',
    file: '.chord/teams/ship.md',
    team: Team(
      description: 'Ships a slice',
      lead: const TeamLead(agent: 'claude'),
      members: const [],
      body: [for (var i = 0; i < 8; i++) 'Paragraph $i.'].join('\n\n'),
    ),
  ),
);

void main() {
  group('tester: transcript reattachment and independent sessions', () {
    for (final size in [
      const Size(120, 40),
      const Size(80, 24),
      const Size(18, 8),
    ]) {
      testWidgets(
        'context can shrink back to defaults while detached at $size',
        (t) async {
          for (final entry in [sendMessage, linkAsked, teamShown]) {
            final w = Window();
            final a = Shown('a', entry)
              ..agent = 'long agent name ' * 12
              ..chordServer = 'chord'
              ..windowRows = 80;
            final b = Shown('b', const model.UserEntry('t', 'other session'));
            w.picked.value = a;
            await t.pumpWidget(w.widget, size: size);
            final oldRows = a.controller.itemRows(60);
            await w.show(t, b);
            a.agent = null;
            a.chordServer = null;
            a.windowRows = 8;
            await w.show(t, a);
            a.controller.toBottom();
            await t.pump();
            final reused = t.screen.text;
            final rows = a.controller.contentRows;
            final lastRows = a.controller.itemRows(60);
            final fresh = Shown('fresh', entry)..windowRows = 8;
            await w.show(t, fresh);
            expect(rows, fresh.controller.contentRows);
            expect(lastRows, fresh.controller.itemRows(60));
            expect(t.screen.text, reused);
            expect(
              lastRows,
              isNot(oldRows),
              reason: 'the case must change height',
            );
          }
        },
      );

      testWidgets(
        'three sessions retain separate geometry after a burst and resize at $size',
        (t) async {
          final w = Window();
          final sessions = [
            Shown('a', sendMessage)..chordServer = 'chord',
            Shown('b', linkAsked)..agent = '界é🙂',
            Shown('c', teamShown)..windowRows = 24,
          ];
          w.picked.value = sessions[0];
          await t.pumpWidget(w.widget, size: size);
          for (final s in sessions) {
            await w.show(t, s);
          }
          for (var i = 0; i < 1000; i++) {
            sessions[0].last = model.UserEntry(
              't',
              'reply $i 界é🙂\nsecond\nlast',
            );
          }
          await t.resize(Size(size.width + 1, size.height));
          await t.resize(size);
          for (final s in sessions) {
            await w.show(t, s);
            s.controller.toBottom();
            await t.pump();
            final before = t.screen.text;
            final rows = s.controller.contentRows;
            final fresh = Shown('fresh ${s.name}', s.last)
              ..agent = s.agent
              ..chordServer = s.chordServer
              ..windowRows = s.windowRows;
            await w.show(t, fresh);
            expect(fresh.controller.contentRows, rows);
            expect(t.screen.text, before);
          }
        },
      );
    }

    testWidgets(
      'scroll keys and details still act after remounting a cached transcript',
      (t) async {
        final w = Window();
        final a = Shown('a', teamShown);
        final b = Shown('b', linkAsked);
        w.picked.value = a;
        await t.pumpWidget(w.widget, size: const Size(80, 24));
        await t.press('ctrl+o');
        final expandedRows = a.controller.contentRows;
        await w.show(t, b);
        await w.show(t, a);
        expect(a.controller.contentRows, lessThan(expandedRows));
        for (final key in ['home', 'shift+home']) {
          await t.press(key);
          expect(a.controller.offset, 0);
        }
        for (final key in ['pagedown', 'shift+pagedown', 'shift+down']) {
          final before = a.controller.offset;
          await t.press(key);
          expect(a.controller.offset, greaterThan(before));
        }
        for (final key in ['pageup', 'shift+pageup', 'shift+up']) {
          a.controller.jumpTo(100);
          await t.pump();
          await t.press(key);
          expect(a.controller.offset, lessThan(100));
        }
        for (final key in ['end', 'shift+end']) {
          await t.press('home');
          await t.press(key);
          expect(a.controller.isFollowing, isTrue);
        }
        await t.press('ctrl+o');
        expect(a.controller.contentRows, expandedRows);
      },
    );
  });

  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    group('at ${size.width}x${size.height}', () {
      testWidgets('an entry changed while its session was hidden', (t) async {
        const longer = model.UserEntry('t', 'a last\nnow\nfour\nrows');
        expect(
          await rowsOf(t, size, longer),
          greaterThan(await rowsOf(t, size, const model.UserEntry('t', 'x'))),
        );
        final (reused, fresh, rows, freshRows) = await switched(
          t,
          size,
          const model.UserEntry('t', 'a last'),
          (a) => a.last = longer,
        );
        expect(rows, freshRows);
        expect(reused, fresh);
        expect(reused.last, contains('lines below'));
      });

      testWidgets('chord\'s server named while its session was hidden', (
        t,
      ) async {
        expect(
          await rowsOf(t, size, sendMessage, (s) => s.chordServer = 'chord'),
          isNot(await rowsOf(t, size, sendMessage)),
        );
        final (reused, fresh, rows, freshRows) = await switched(
          t,
          size,
          sendMessage,
          (a) => a.chordServer = 'chord',
        );
        expect(rows, freshRows);
        expect(reused, fresh);
      });

      testWidgets('the agent renamed while its session was hidden', (t) async {
        final long = 'agent ' * (size.width ~/ 6);
        expect(
          await rowsOf(t, size, linkAsked, (s) => s.agent = long),
          greaterThan(await rowsOf(t, size, linkAsked, (s) => s.agent = 'a')),
        );
        final (reused, fresh, rows, freshRows) = await switched(
          t,
          size,
          linkAsked,
          (a) => a.agent = long,
        );
        expect(rows, freshRows);
        expect(reused, fresh);
      });

      testWidgets('the window\'s rows changed while its session was hidden', (
        t,
      ) async {
        expect(
          await rowsOf(t, size, teamShown, (s) => s.windowRows = 24),
          lessThan(await rowsOf(t, size, teamShown)),
        );
        final (reused, fresh, rows, freshRows) = await switched(
          t,
          size,
          teamShown,
          (a) => a.windowRows = 24,
        );
        expect(rows, freshRows);
        expect(reused, fresh);
      });
    });
  }
}
