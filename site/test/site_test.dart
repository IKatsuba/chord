import 'package:chord_site/site.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'fake_host.dart';

const _sizes = [Size(120, 40), Size(80, 24), Size(43, 37)];

void main() {
  testWidgets('home at 120x40: header, menu, the try-it box, keys', (t) async {
    final host = FakeHost();
    await t.pumpWidget(Site(host: host), size: const Size(120, 40));
    final lines = t.screen.lines;
    expect(lines[0], startsWith(' chord'));
    expect(lines[0], endsWith('github.com/IKatsuba/chord   vdev'));
    expect(lines[1], '─' * 120);
    expect(t.screen, shows('❯ 1. chord'));
    expect(t.screen, shows('4. Install'));
    expect(t.screen, shows('Try it'));
    expect(lines.last, ' up/down move  enter open  1/2/3/4 jump  ? keys');
    expect(host.titles, ['chord and chord_tui']);
  });

  testWidgets('home at 80x24: the link folds under the name', (t) async {
    await t.pumpWidget(Site(host: FakeHost()), size: const Size(80, 24));
    final lines = t.screen.lines;
    expect(lines[0], matches(RegExp(r'^ chord +vdev$')));
    expect(lines[1], ' github.com/IKatsuba/chord');
    expect(lines[2], '─' * 80);
    expect(t.screen, isNot(shows('Try it')));
    expect(t.screen, shows('2. chord_tui'));
  });

  testWidgets('a phone: no link, a key row, only esc and ? help', (t) async {
    await t.pumpWidget(
      Site(host: FakeHost('/install')),
      size: const Size(43, 37),
    );
    final lines = t.screen.lines;
    expect(lines[0], matches(RegExp(r'^ chord › install +vdev$')));
    expect(t.screen, isNot(shows('github.com')));
    expect(lines[35], startsWith('  esc   tab   ←   ↑   ↓   →   enter'));
    expect(lines.last, ' escape up  ? keys');
  });

  testWidgets('enter and digits open pages; esc goes up', (t) async {
    final host = FakeHost();
    await t.pumpWidget(Site(host: host), size: const Size(120, 40));
    await t.press('down');
    await t.press('down');
    await t.press('enter');
    expect(host.pushed, ['/chord_tui/gallery']);
    expect(t.screen.lines[0], startsWith(' chord › chord_tui › gallery'));
    expect(host.titles.last, 'gallery · chord_tui');
    await t.press('esc');
    expect(host.pushed.last, '/chord_tui');
    await t.press('esc');
    expect(host.pushed.last, '/');
    await t.press('4');
    expect(host.pushed.last, '/install');
    expect(t.screen, shows('Homebrew, npm, from source.'));
  });

  testWidgets('a tap opens the row tapped', (t) async {
    final host = FakeHost();
    await t.pumpWidget(Site(host: host), size: const Size(120, 40));
    final row = t.screen.lines.indexWhere((l) => l.contains('2. chord_tui'));
    await t.mouse(_tapAt(5, row));
    expect(host.pushed, ['/chord_tui']);
  });

  testWidgets('back and forward show the page without pushing', (t) async {
    final host = FakeHost();
    await t.pumpWidget(Site(host: host), size: const Size(80, 24));
    host.popped.add('/chord');
    await t.pump();
    expect(t.screen, shows('What chord is'));
    expect(host.pushed, isEmpty);
    expect(host.titles.last, 'chord');
  });

  testWidgets('a deep link opens its page at once', (t) async {
    final host = FakeHost('/chord_tui');
    await t.pumpWidget(Site(host: host), size: const Size(80, 24));
    expect(t.screen.lines[0], startsWith(' chord › chord_tui '));
    expect(host.titles, ['chord_tui']);
  });

  for (final size in _sizes) {
    testWidgets('not found keeps the path and offers home, $size', (t) async {
      final host = FakeHost('/chord_tui/markdwon');
      await t.pumpWidget(Site(host: host), size: size);
      expect(t.screen, shows('Nothing here: /chord_tui/markdwon'));
      expect(t.screen, shows('❯ home'));
      expect(host.titles, ['not found · chord']);
      expect(t.screen.lines.last, contains('escape home  ? keys'));
      await t.press('enter');
      expect(host.pushed, ['/']);
    });
  }

  testWidgets('quit keys go home, and do nothing at home', (t) async {
    final host = FakeHost('/install');
    await t.pumpWidget(Site(host: host), size: const Size(120, 40));
    await t.press('ctrl+c');
    expect(host.pushed, ['/']);
    await t.press('ctrl+q');
    await t.press('ctrl+c');
    expect(host.pushed, ['/']);
    expect(t.exitRequested, isFalse);
    await t.press('esc');
    expect(host.pushed, ['/']);
  });

  testWidgets('? lists every key, esc closes it', (t) async {
    await t.pumpWidget(Site(host: FakeHost()), size: const Size(120, 40));
    await t.press('?');
    expect(t.screen, shows(' Keys'));
    expect(t.screen, shows(RegExp(r'ctrl\+q/ctrl\+c\s+home')));
    expect(t.screen, shows(RegExp(r'g\s+open GitHub')));
    expect(t.screen.lines.last, contains('escape close'));
    await t.press('esc');
    expect(t.screen, isNot(shows(' Keys')));
  });

  testWidgets('g and a tap on the link open the repository', (t) async {
    final host = FakeHost();
    await t.pumpWidget(Site(host: host), size: const Size(120, 40));
    await t.press('g');
    final column = t.screen.lines[0].indexOf('github.com');
    await t.mouse(_tapAt(column, 0));
    expect(host.opened, [
      'https://github.com/IKatsuba/chord',
      'https://github.com/IKatsuba/chord',
    ]);
  });

  testWidgets('the key row taps send keys to the page', (t) async {
    final host = FakeHost();
    await t.pumpWidget(Site(host: host), size: const Size(43, 37));
    final row = t.screen.lines[35];
    Future<void> tap(String label) => t.mouse(_tapAt(row.indexOf(label), 35));
    await tap('↓');
    await tap('enter');
    expect(host.pushed, ['/chord_tui']);
    await tap('esc');
    expect(host.pushed.last, '/');
  });
}

MouseEvent _tapAt(int x, int y) => MouseEvent(
  MouseEventKind.press,
  position: Offset(x, y),
  button: MouseButton.primary,
);
