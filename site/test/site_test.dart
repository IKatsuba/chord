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
    expect(lines[0], endsWith('github.com/IKatsuba/chord   dev'));
    expect(lines[1], '─' * 120);
    expect(t.screen, shows('❯ 1. chord'));
    expect(t.screen, shows('4. Install'));
    expect(t.screen, shows('Try it'));
    expect(lines.last, ' up/down move  enter open  1–4 jump  ? keys');
    expect(host.titles, ['chord and chord_tui']);
  });

  testWidgets('home at 80x24: the link folds under the name', (t) async {
    await t.pumpWidget(Site(host: FakeHost()), size: const Size(80, 24));
    final lines = t.screen.lines;
    expect(lines[0], matches(RegExp(r'^ chord +dev$')));
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
    expect(lines[0], matches(RegExp(r'^ chord › install +dev$')));
    expect(lines[0], isNot(contains('github.com')));
    expect(lines[1], startsWith('──'));
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
    expect(t.screen, shows('brew install ikatsuba/tap/chord'));
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
    expect(t.screen, shows('One terminal for every coding agent.'));
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
      expect(
        t.screen.lines.last,
        size.width < 60
            ? ' escape home  ? keys'
            : ' enter open  escape home  ? keys',
      );
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

  testWidgets('? and f1 both open the panel outside examples', (t) async {
    final host = FakeHost();
    await t.pumpWidget(Site(host: host), size: const Size(120, 40));
    expect(t.screen.lines.last, endsWith('  ? keys'));
    await t.press('f1');
    expect(t.screen, shows(' Keys'));
    expect(t.screen.lines, contains(matches(RegExp(r'^ +\?/f1 +keys$'))));
    expect(t.screen.lines.last, ' escape close  f1 close  ctrl+q home');
    // The open panel takes the menu's keys too.
    await t.press('down');
    await t.press('enter');
    expect(host.pushed, isEmpty);
    await t.press('?');
    expect(t.screen, isNot(shows(' Keys')));
    await t.press('?');
    await t.press('f1');
    expect(t.screen, isNot(shows(' Keys')));
    await t.press('enter');
    expect(host.pushed, ['/chord']);
  });

  testWidgets('the panel is one rule wide and writes digit runs as ranges', (
    t,
  ) async {
    await t.pumpWidget(Site(host: FakeHost()), size: const Size(80, 24));
    await t.press('f1');
    final lines = t.screen.lines;
    final rules = [
      for (final l in lines)
        if (l.startsWith('─')) l,
    ];
    expect(rules, ['─' * 80, '─' * 80]);
    expect(lines, contains(matches(RegExp(r'^ +1–4 +jump$'))));
    expect(lines.last, ' escape close  f1 close  ctrl+q home');
  });

  testWidgets('the phone key row has f1, which opens the panel', (t) async {
    await t.pumpWidget(
      Site(host: FakeHost('/install')),
      size: const Size(43, 37),
    );
    final row = t.screen.lines[35];
    expect(row, endsWith(' f1'));
    await t.mouse(_tapAt(row.lastIndexOf('f1'), 35));
    expect(t.screen, shows(' Keys'));
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

  testWidgets('an overflowing help row ends in an ellipsis', (t) async {
    await t.pumpWidget(
      Actions(
        bindings: [Binding('f5', 'a description too long for the row', () {})],
        child: Site(host: FakeHost()),
      ),
      size: const Size(64, 24),
    );
    expect(t.screen.lines.last, hasLength(64));
    expect(t.screen.lines.last, endsWith('…'));
  });

  testWidgets('panel-only keys stay out of the help row', (t) async {
    await t.pumpWidget(
      Actions(
        bindings: [Binding('f2', 'back', () {}, id: '${panelOnly}back')],
        child: Site(host: FakeHost()),
      ),
      size: const Size(120, 40),
    );
    expect(t.screen.lines.last, isNot(contains('back')));
    await t.press('?');
    expect(t.screen, shows(RegExp(r'f2\s+back')));
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
