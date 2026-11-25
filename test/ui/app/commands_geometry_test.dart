import 'package:chord/session/start_connection.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart' as model;
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/app/window.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'window_fake_test.dart' show launch;
import 'wheel_window_test.dart' show seed, wheel;

void main() {
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    testWidgets(
      'mode keeps original precedence over hidden-completion hint at $size',
      (t) async {
        final c = seed();
        addTearDown(c.close);
        c.app.value = AppState(
          start: c.app.value.start,
          transcript: model.Transcript(
            entries: c.app.value.transcript.entries,
            mode: 'acceptEdits',
          ),
        );
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: size,
        );
        await t.pump();
        await t.type('/sta');
        await t.pump();
        await t.resize(const Size(80, 5));
        await t.press('tab');
        expect(t.screen, shows('accept edits on'));
        expect(t.screen, isNot(shows('not enough space')));
        expect(c.app.value.draft, '/sta');
      },
    );
    testWidgets(
      'windowed fitting completion body and rule bubble wheel without changing draft at $size',
      (t) async {
        final StartConnection c = seed();
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: size,
        );
        await t.pump();
        await t.type('/');
        await t.pump();
        final focus = t.focusManager.primaryFocus;
        final row = t.screen.lines.indexWhere(
          (line) => line.contains('/clear'),
        );
        expect(row, greaterThanOrEqualTo(1));
        var top = c.app.value.scroll.offset;
        await t.mouse(wheel(10, row));
        expect(c.app.value.scroll.offset, top - 1);
        top = c.app.value.scroll.offset;
        await t.mouse(wheel(10, row - 1));
        expect(c.app.value.scroll.offset, top - 1);
        expect(c.app.value.draft, '/');
        expect(t.focusManager.primaryFocus, same(focus));
        await t.press('up');
        top = c.app.value.scroll.offset;
        await t.resize(
          size == const Size(120, 40)
              ? const Size(80, 24)
              : const Size(120, 40),
        );
        expect(c.app.value.draft, '/');
        await t.press('tab');
        expect(c.app.value.draft, '/vim ');
        expect(c.app.value.scroll.following, isFalse);
        expect(
          c.app.value.transcript.entries.whereType<model.ReportEntry>(),
          isEmpty,
        );
        expect(top, greaterThan(0));
      },
    );
    testWidgets(
      'Closing rejects a current completion before the next frame at $size',
      (t) async {
        final c = seed();
        addTearDown(c.close);
        await t.pumpWidget(
          TranscriptWindow(launch: launch, connection: c),
          size: size,
        );
        await t.pump();
        await t.type('/sta');
        await t.pump();
        c.app.value = reduceApp(c.app.value, const Closing());
        t.host.handleKey(KeyCombo.parse('tab').toEvent());
        t.host.handleKey(KeyCombo.parse('enter').toEvent());
        await t.pump();
        expect(c.app.value.draft, '/sta');
        expect(
          c.app.value.transcript.entries.whereType<model.ReportEntry>(),
          isEmpty,
        );
      },
    );
  }
}
