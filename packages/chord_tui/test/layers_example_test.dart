import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import '../example/layers.dart';

/// The status line's numbers.
String status(WidgetTester t) =>
    t.screen.lines.firstWhere((l) => l.startsWith('page builds'));

void main() {
  testerEdges();
  setUp(() => Layers.pageBuilds = 0);

  for (final size in const [Size(120, 40), Size(80, 24)]) {
    final at = '${size.width}x${size.height}';
    // The anchor sits above the gap, the prompt, the status and the keys.
    final anchor = size.height - 4;

    testWidgets('the picker sits on the anchor, the page untouched, $at', (
      t,
    ) async {
      await t.pumpWidget(const Layers(stream: false), size: size);
      final before = status(t);
      expect(before, startsWith('page builds 1 · rows 60 '));
      await t.press('ctrl+p');
      final rows = t.screen.lines;
      expect(rows[anchor - 7], startsWith('╭ Models '));
      expect(rows[anchor - 6], startsWith('│ ❯ Careful'));
      expect(rows[anchor - 1], startsWith('╰'));
      expect(rows[anchor], '');
      expect(rows[anchor + 1], '> /model');
      expect(t.focusManager.primaryFocus?.debugLabel, 'Careful');
      expect(status(t), before);

      await t.press('tab');
      expect(t.focusManager.primaryFocus?.debugLabel, 'Balanced');
      await t.press('enter');
      expect(t.screen, isNot(shows('Models')));
      expect(t.screen, shows('chose Balanced'));
      expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
      expect(Layers.pageBuilds, 1);
    });

    testWidgets('completions leave focus on the prompt, $at', (t) async {
      await t.pumpWidget(const Layers(stream: false), size: size);
      await t.press('ctrl+o');
      final rows = t.screen.lines;
      expect(rows[anchor - 4], '─' * size.width);
      expect(rows[anchor - 1], '  /config');
      expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
      expect(t.screen, isNot(shows('tab Next field')));
      await t.press('ctrl+o');
      expect(t.screen, isNot(shows('/config')));
      expect(Layers.pageBuilds, 1);
    });

    testWidgets('a tall picker stops at the top row, $at', (t) async {
      await t.pumpWidget(const Layers(stream: false), size: size);
      await t.press('ctrl+x p');
      expect(t.screen.lines.first, startsWith('╭ Models '));
      expect(t.screen.lines[anchor - 1], startsWith('╰'));
      expect(t.screen.lines[anchor + 1], '> /model');
    });
  }

  testWidgets('the picker follows the anchor and survives a resize', (t) async {
    await t.pumpWidget(const Layers(stream: false), size: const Size(80, 24));
    await t.press('ctrl+p');
    expect(t.screen.lines[13], startsWith('╭ Models '));
    await t.press('ctrl+x g');
    expect(t.screen.lines[12], startsWith('╭ Models '));
    expect(t.screen.lines[19], '');
    await t.resize(const Size(120, 40));
    expect(t.screen.lines[28], startsWith('╭ Models '));
    expect(t.focusManager.primaryFocus?.debugLabel, 'Careful');
    // The rows the page lays out do not change, nor do its builds.
    expect(Layers.pageBuilds, 1);
  });

  testWidgets('without its anchor the picker hides and lets go of focus', (
    t,
  ) async {
    await t.pumpWidget(const Layers(stream: false));
    await t.press('ctrl+p');
    await t.press('tab');
    expect(t.focusManager.primaryFocus?.debugLabel, 'Balanced');
    await t.press('ctrl+x a');
    expect(t.screen, isNot(shows('Models')));
    expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
    await t.press('esc');
    expect(t.screen, isNot(shows('Models')));
    await t.press('ctrl+x a');
    expect(t.screen, shows('Models'));
    expect(t.focusManager.primaryFocus?.debugLabel, 'Balanced');
    await t.press('esc');
    expect(t.screen, isNot(shows('Models')));
    expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
  });

  testWidgets('the stream grows the page under an open picker', (t) async {
    await t.pumpWidget(const Layers(stream: false));
    await t.press('ctrl+p');
    await t.press('ctrl+s');
    await t.pump(const Duration(milliseconds: 700));
    await t.press('ctrl+s');
    expect(status(t), startsWith('page builds 1 · rows 61 · offset 41'));
    expect(status(t), endsWith('following'));
    expect(t.screen, shows('╭ Models '));
    // The new line is under the picker until it closes.
    await t.press('esc');
    expect(t.screen.lines[19], startsWith('streamed'));
  });

  testWidgets('scrolling back keeps the picker where it is', (t) async {
    await t.pumpWidget(const Layers(stream: false));
    await t.press('ctrl+p');
    await t.press('pageup');
    expect(status(t), endsWith('scrolled back'));
    expect(t.screen.lines[13], startsWith('╭ Models '));
  });

  testWidgets('a theme change keeps the open picker and its focus', (t) async {
    await t.pumpWidget(const Layers(stream: false));
    await t.press('ctrl+p');
    await t.press('tab');
    expect(t.focusManager.primaryFocus?.debugLabel, 'Balanced');
    final dark = ThemeData.dark(), light = ThemeData.light();
    for (final (theme, next) in [(dark, 'dark'), (light, 'light')]) {
      await t.press('ctrl+t');
      expect(t.screen, shows('╭ Models '), reason: next);
      expect(t.focusManager.primaryFocus?.debugLabel, 'Balanced');
      final top = t.screen.lines.indexWhere((l) => l.startsWith('╭ Models'));
      expect(t.screen.styleAt(0, top), theme.focus);
    }
    await t.press('ctrl+t');
    await t.press('ctrl+t');
    expect(t.screen, shows('╭ Models '), reason: 'back to auto');
    await t.press('esc');
    expect(t.screen, isNot(shows('Models')));
    await t.press('ctrl+p');
    expect(t.screen, shows('╭ Models '), reason: 'no stale picker left');
  });
}

LayersState testerState(WidgetTester t) {
  LayersState? found;
  void walk(Element e) {
    if (e is StatefulElement && e.state is LayersState) {
      found = e.state as LayersState;
    }
    e.visitChildren(walk);
  }

  walk(t.host.rootElement);
  return found!;
}

void testerEdges() {
  group('tester: layers fixture retained stream and focus', () {
    for (final size in const [Size(120, 40), Size(80, 24)]) {
      testWidgets(
        'a thousand stream updates preserve scroll-back under layers at $size',
        (t) async {
          await t.pumpWidget(const Layers(stream: false), size: size);
          await t.press('pageup');
          final state = testerState(t),
              beforeOffset = testerState(t).scroll.offset;
          final first = t.screen.lines.first;
          await t.press('ctrl+p');
          await t.press('tab');
          for (var i = 0; i < 1000; i++) {
            state.transcript.stream();
          }
          await t.pump();
          expect(state.scroll.offset, beforeOffset);
          expect(state.scroll.isFollowing, isFalse);
          expect(t.screen.lines.first, first);
          expect(t.focusManager.primaryFocus?.debugLabel, 'Balanced');
          expect(Layers.pageBuilds, 1);
          expect(state.scroll.contentRows, greaterThan(60));
          await t.press('esc');
          expect(state.scroll.offset, beforeOffset);
          await t.press('end');
          expect(state.scroll.isFollowing, isTrue);
        },
      );
      testWidgets(
        'layer and selection survive every theme and no-room boundary at $size',
        (t) async {
          await t.pumpWidget(const Layers(stream: false), size: size);
          await t.press('ctrl+p');
          await t.press('tab');
          for (var theme = 0; theme < 4; theme++) {
            await t.press('ctrl+t');
            expect(t.focusManager.primaryFocus?.debugLabel, 'Balanced');
            expect(t.screen, shows('Models'));
          }
          final buildsAfterThemes = Layers.pageBuilds;
          for (final next in const [Size.zero, Size(1, 1), Size(80, 4)]) {
            await t.resize(next);
            await t.press('enter');
            await t.press('esc');
          }
          await t.resize(size);
          expect(t.focusManager.primaryFocus?.debugLabel, 'Balanced');
          expect(t.screen, isNot(shows('chose Balanced')));
          await t.press('enter');
          expect(t.screen, shows('chose Balanced'));
          expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
          expect(Layers.pageBuilds, buildsAfterThemes);
        },
      );
      testWidgets(
        'passive and focused layers coexist without stealing focus at $size',
        (t) async {
          await t.pumpWidget(const Layers(stream: false), size: size);
          await t.press('ctrl+o');
          expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
          await t.press('ctrl+p');
          await t.press('shift+tab');
          expect(t.focusManager.primaryFocus?.debugLabel, 'Thorough');
          await t.press('ctrl+x a');
          expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
          await t.press('enter');
          await t.press('ctrl+x a');
          expect(t.focusManager.primaryFocus?.debugLabel, 'Thorough');
          await t.press('ctrl+o');
          expect(t.focusManager.primaryFocus?.debugLabel, 'Thorough');
          await t.press('esc');
          expect(t.focusManager.primaryFocus?.debugLabel, 'prompt');
          expect(t.screen, isNot(shows('/config')));
          await t.press('ctrl+q');
          expect(t.exitRequested, isTrue);
        },
      );
    }
    testWidgets('unmount with live timer closes all owned resources', (
      t,
    ) async {
      await t.pumpWidget(const Layers());
      final state = testerState(t);
      await t.press('ctrl+p');
      await t.press('ctrl+o');
      final before = List<String>.of(state.transcript.lines);
      await t.pumpWidget(Text('removed'));
      expect(state.transcript.isDisposed, isTrue);
      expect(state.scroll.isDisposed, isTrue);
      expect(state.anchored.isDisposed, isTrue);
      expect(state.promptRows.isDisposed, isTrue);
      await t.pump(const Duration(milliseconds: 650));
      expect(state.transcript.lines, before);
      expect(t.screen.text, 'removed');
      expect(t.focusManager.activeBindings, isEmpty);
    });
  });
}
