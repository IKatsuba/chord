import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import 'steering_window_test.dart' show connected;

void main() {
  for (final size in [
    const Size(120, 40),
    const Size(80, 24),
    const Size(32, 10),
  ]) {
    testWidgets(
      'F1 advertises injected controls then restores normal cells $size',
      (t) async {
        await connected(t, size);
        final before = List.of(t.screen.lines);
        final cursor = t.screen.buffer.cursor;
        expect(t.screen, isNot(shows('Fixture controls')));
        await t.press('f1');
        expect(t.screen, shows('Fixture controls'));
        for (final words in [
          'f1  Close controls',
          'f2  Accept pending steer',
          'f3  Refuse pending steer',
          'f4  Finish current prompt',
          'f5  Toggle open call',
          'f6  Ask permission',
          'f7  Emit late text',
          'ctrl+q  Quit fixture',
        ]) {
          expect(t.screen, shows(words));
        }
        await t.press('f1');
        expect(t.screen.lines, before);
        expect(t.screen.buffer.cursor, cursor);
        await t.press('ctrl+q');
        expect(t.exitRequested, isTrue);
      },
    );
  }
  testWidgets('compact modal scrolls without leaking input or agent controls', (
    t,
  ) async {
    final f = await connected(t, const Size(32, 6));
    await t.type('draft');
    final before = List.of(t.screen.lines), cursor = t.screen.buffer.cursor;
    await t.press('f1');
    expect(t.screen.lines.first, ' Fixture controls');
    expect(t.screen.lines.last, ' F1 close · ↑↓ scroll');
    expect(t.screen, shows('ctrl+q  Quit fixture'));
    expect(t.screen, isNot(shows('╭')));
    await t.type('ignored');
    await t.paste('ignored');
    await t.press('enter f2 f3 f4 f5 f6 f7');
    expect(
      f.agent.requests.where((r) => r['method'] == 'session/prompt'),
      isEmpty,
    );
    expect(f.agent.callOpen, isFalse);
    expect(f.agent.hasPermission, isFalse);
    expect(f.connection.app.value.draft, 'draft');
    await t.press('end');
    expect(t.screen, shows('f7  Emit late text'));
    expect(t.screen.lines.last, ' F1 close · ↑↓ scroll');
    await t.press('home');
    expect(t.screen, shows('ctrl+q  Quit fixture'));
    await t.resize(const Size(32, 2));
    expect(t.screen.lines, [' Fixture controls', ' F1 close · ↑↓ scroll']);
    await t.resize(const Size(32, 1));
    expect(t.screen.lines, [' F1 close · ↑↓ scroll']);
    await t.resize(Size.zero);
    await t.press('down end f5 f6 enter');
    expect(f.agent.callOpen, isFalse);
    expect(f.agent.hasPermission, isFalse);
    await t.resize(const Size(32, 6));
    await t.press('f1');
    expect(t.screen.lines, before);
    expect(t.screen.buffer.cursor, cursor);
    await t.press('f1');
    expect(t.screen, shows('ctrl+q  Quit fixture'));
    await t.press('f1');
  });
}
