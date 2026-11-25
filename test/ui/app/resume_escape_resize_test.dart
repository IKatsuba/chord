import 'package:chord/ui/pickers/pickers.dart';
import '../../../tool/resume.dart' show resumeFixtureState;
import 'package:chord/ui/start_state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'failed_start_window_test.dart' as failed;
import 'window_fake_test.dart' show until;

void main() {
  _testerResumeFocusBoundaries();
  testWidgets('fresh narrow resume retains Escape ownership without resize', (
    t,
  ) async {
    final f = await failed.failedFixture(t, const Size(32, 10));
    await f.saved('local');
    await failed.command(t, '/resume');
    expect(f.connection.app.value.resumePicker, isNotNull);
    await t.press('esc');
    expect(f.connection.app.value.resumePicker, isNull);
  });

  testWidgets('parser-pending Escape closes after resize before paint', (
    t,
  ) async {
    final f = await failed.failedFixture(t, const Size(80, 24));
    await f.saved('local');
    await failed.command(t, '/resume');
    final parser = InputParser();
    expect(parser.feed('\x1b'), isEmpty);
    t.host.updateSize(const Size(32, 10));
    for (final event in parser.flush().whereType<KeyEvent>()) {
      t.host.handleKey(event);
    }
    await t.resize(const Size(32, 10));
    expect(f.connection.app.value.resumePicker, isNull);
  });

  testWidgets('accepted Escape cannot reopen after a same-batch resize', (
    t,
  ) async {
    final f = await failed.failedFixture(t, const Size(80, 24));
    await f.saved('local');
    await failed.command(t, '/resume');
    t.host.handleKey(const KeyEvent('escape'));
    t.host.updateSize(const Size(32, 10));
    await t.resize(const Size(32, 10));
    expect(f.connection.app.value.resumePicker, isNull);
  });

  testWidgets('narrow-to-wide keeps scope and Escape actions', (t) async {
    final f = await failed.failedFixture(t, const Size(32, 10));
    await f.saved('local');
    await failed.command(t, '/resume');
    await t.press('ctrl+a');
    expect(f.connection.app.value.resumePicker?.everywhere, isTrue);
    await t.resize(const Size(80, 24));
    expect(t.screen, shows('Choice local'));
    await t.press('esc');
    expect(f.connection.app.value.resumePicker, isNull);
  });

  testWidgets('zero-room Enter is never replayed when list returns', (t) async {
    final f = await failed.failedFixture(t, const Size(80, 24));
    await f.saved('local');
    await failed.command(t, '/resume');
    await t.resize(const Size(8, 3));
    await t.press('enter');
    expect(f.openings, 1);
    await t.resize(const Size(80, 24));
    expect(f.connection.app.value.resumePicker, isNotNull);
    expect(f.openings, 1);
    await t.press('esc');
    expect(f.connection.app.value.resumePicker, isNull);
  });

  testWidgets('scope change and resize in one raw key batch still cancel', (
    t,
  ) async {
    final f = await failed.failedFixture(t, const Size(80, 24));
    await f.saved('local');
    await failed.command(t, '/resume');
    t.host.handleKey(KeyCombo.parse('ctrl+a').toEvent());
    t.host.updateSize(const Size(32, 10));
    t.host.handleKey(const KeyEvent('escape'));
    await t.resize(const Size(32, 10));
    expect(f.connection.app.value.resumePicker, isNull);
    expect(f.openings, 1);
  });

  testWidgets('a still-visible list keeps its highlight across resize', (
    t,
  ) async {
    final f = await failed.failedFixture(t, const Size(80, 24));
    await f.saved('old');
    await f.saved('new', at: 2);
    await failed.command(t, '/resume');
    await t.press('down');
    await t.resize(const Size(120, 40));
    await t.press('enter');
    await until(
      () => f.connection.app.value.start.phase == StartPhase.connected,
    );
    await t.pump();
    expect(f.connection.app.value.resumed?.sessionId, 'old');
  });

  testWidgets('retained cancel callback cannot close a later picker', (
    t,
  ) async {
    final f = await failed.failedFixture(t, const Size(80, 24));
    await f.saved('local');
    await failed.command(t, '/resume');
    final oldCancel = t.focusManager
        .matchKey(const KeyEvent('escape'))
        .binding!
        .onInvoke;
    await t.resize(const Size(32, 10));
    await t.press('esc');
    expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
    await failed.command(t, '/resume');
    final current = f.connection.app.value.resumePicker;
    oldCancel();
    await t.pump();
    expect(f.connection.app.value.resumePicker, same(current));
    await t.press('esc');
    expect(f.connection.app.value.resumePicker, isNull);
  });

  for (final fromFailedReopen in [false, true]) {
    testWidgets(
      'resume Escape remains owned after list disappears on resize $fromFailedReopen',
      (t) async {
        final f = await failed.failedFixture(t, const Size(80, 24));
        await f.saved('local');
        if (fromFailedReopen) {
          f.failuresRemaining = 1;
          await failed.command(t, '/resume');
          await t.press('enter');
          await until(
            () =>
                f.openings == 2 &&
                f.connection.app.value.start.phase == StartPhase.failed,
          );
          await t.pump();
        }
        await failed.command(t, '/resume');
        expect(f.connection.app.value.resumePicker, isNotNull);
        expect(t.screen, shows('Choice local'));
        final beforeFocus = t.focusManager.primaryFocus;
        await t.resize(const Size(32, 10));
        expect(t.screen, shows('Resume a session'));
        expect(t.screen, isNot(shows('Choice local')));
        final afterFocus = t.focusManager.primaryFocus;
        final binding = t.focusManager
            .matchKey(const KeyEvent('escape'))
            .binding
            ?.description;
        t.host.handleKey(const KeyEvent('escape'));
        await t.pump();
        expect(
          f.connection.app.value.resumePicker,
          isNull,
          reason: 'before=$beforeFocus after=$afterFocus binding=$binding',
        );
      },
    );
  }
}

void _testerResumeFocusBoundaries() {
  group('tester: U52e modal focus ownership', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'scope replacement invalidates a retained cancel before resize at $size',
        (t) async {
          final f = await failed.failedFixture(t, size);
          await f.saved('local');
          await failed.command(t, '/resume');
          final oldCancel = t.focusManager
              .matchKey(const KeyEvent('escape'))
              .binding!
              .onInvoke;
          await t.press('ctrl+a');
          final current = f.connection.app.value.resumePicker;
          expect(current?.everywhere, isTrue);
          oldCancel();
          await t.pump();
          expect(f.connection.app.value.resumePicker, same(current));
          await t.resize(const Size(32, 10));
          await t.press('esc');
          expect(f.connection.app.value.resumePicker, isNull);
          expect(f.openings, 1);
          expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
        },
      );

      testWidgets(
        'inactive list disappearance never steals another owner focus at $size',
        (t) async {
          final room = ValueNotifier(size.height);
          final other = FocusNode();
          final state = resumeFixtureState(['--many']);
          var cancels = 0, scopes = 0, outsideKeys = 0;
          await t.pumpWidget(
            ListenableBuilder(
              listenable: room,
              builder: (_) => Column(
                children: [
                  Expanded(
                    child: ResumePicker(
                      picker: state,
                      agent: 'fake',
                      rows: 8,
                      room: room.value,
                      active: false,
                      onToggleScope: () => scopes++,
                      onCanceled: () => cancels++,
                      onSelected: (_) => fail('Inactive picker accepted'),
                    ),
                  ),
                  Focus(
                    focusNode: other,
                    autofocus: true,
                    onKey: (_) {
                      outsideKeys++;
                      return true;
                    },
                    child: Text('Other owner'),
                  ),
                ],
              ),
            ),
            size: size,
          );
          other.requestFocus();
          await t.pump();
          for (final next in [0, size.height, 0, size.height]) {
            room.value = next;
            await t.pump();
            expect(other.hasFocus, isTrue);
            await t.press('ctrl+a esc');
          }
          expect(cancels, 0);
          expect(scopes, 0);
          expect(outsideKeys, 8);
          t.dispose();
          room.dispose();
          other.dispose();
        },
      );
    }
  });
}
