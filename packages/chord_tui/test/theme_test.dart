import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/widgets/theme.dart' show TerminalEnvironment;
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  group('ThemeData', () {
    test('dark and light are chord\'s DARK and LIGHT', () {
      final dark = ThemeData.dark();
      expect(dark.brightness, Brightness.dark);
      expect(dark.accent, Style(fg: RgbColor.hex('#47e7a5')));
      expect(dark.focus, Style(fg: RgbColor.hex('#b1b9f9')));
      expect(dark.selection, const Style(bg: IndexedColor(66)));
      expect(dark.diff.tint!.added, Style(bg: RgbColor.hex('#1f3b24')));
      expect(dark.code!.tint, dark.code!.terminal);
      final light = ThemeData.light();
      expect(light.brightness, Brightness.light);
      expect(light.accent, Style(fg: RgbColor.hex('#147d55')));
      expect(light.selection, const Style(bg: IndexedColor(152)));
      expect(light.code!.terminal.keyword, Style(fg: RgbColor.hex('#8250df')));
      expect(light.code!.tint.keyword, Style(fg: RgbColor.hex('#7a45d0')));
      for (final t in [dark, light]) {
        expect(t.text, Style.plain);
        expect(t.dim, Style.dim);
        expect(t.border, const Style(fg: IndexedColor(244)));
        expect(t.cursor, Style.inverse);
      }
    });

    test('plain paints no colour', () {
      final plain = ThemeData.plain(brightness: Brightness.light);
      expect(plain.brightness, Brightness.light);
      final roles = [
        plain.text,
        plain.dim,
        plain.accent,
        plain.link,
        plain.inlineCode,
        plain.success,
        plain.warning,
        plain.error,
        plain.border,
        plain.focus,
        plain.selection,
        plain.cursor,
        plain.diff.added,
        plain.diff.removed,
      ];
      for (final r in roles) {
        expect(r.fg, isNull);
        expect(r.bg, isNull);
      }
      expect(plain.border, Style.dim);
      expect(plain.focus, Style.bold);
      expect(plain.selection, Style.inverse);
      expect(plain.diff.tint, isNull);
      expect(plain.code, isNull);
    });

    test('fallback is dark', () {
      expect(ThemeData.fallback(), ThemeData.dark());
    });

    test('equal by value; copyWith replaces only what is given', () {
      expect(ThemeData.dark(), ThemeData.dark());
      expect(ThemeData.dark().hashCode, ThemeData.dark().hashCode);
      expect(ThemeData.dark(), isNot(ThemeData.light()));
      const magenta = Style(fg: Colors.magenta);
      final changed = ThemeData.dark().copyWith(accent: magenta);
      expect(changed.accent, magenta);
      expect(changed, isNot(ThemeData.dark()));
      expect(
        changed.copyWith(accent: ThemeData.dark().accent),
        ThemeData.dark(),
      );
      final tinted = ThemeData.light().diff.copyWith(added: magenta);
      expect(tinted.added, magenta);
      expect(tinted.tint, ThemeData.light().diff.tint);
    });
  });

  group('Theme', () {
    Widget probe(void Function(BuildContext) read) => Builder(
      builder: (context) {
        read(context);
        final theme = Theme.of(context);
        return Text('accent', style: theme.accent);
      },
    );

    testWidgets('with none above, Theme.of is dark and the terminal unknown', (
      t,
    ) async {
      late TerminalBackground background;
      late bool noColor;
      await t.pumpWidget(
        probe((c) {
          background = Theme.backgroundOf(c);
          noColor = Theme.noColorOf(c);
        }),
      );
      expect(t.screen.styleAt(0, 0), ThemeData.dark().accent);
      expect(
        background,
        const TerminalBackground(Brightness.dark, BrightnessSource.fallback),
      );
      expect(noColor, isFalse);
    });

    testWidgets('the nearest Theme wins', (t) async {
      await t.pumpWidget(
        Theme(
          data: ThemeData.light(),
          child: Theme(data: ThemeData.plain(), child: probe((_) {})),
        ),
        size: const Size(120, 40),
      );
      expect(t.screen.styleAt(0, 0), Style.plain);
    });

    testWidgets('a change of data rebuilds what reads it', (t) async {
      final data = ValueNotifier(ThemeData.dark());
      await t.pumpWidget(
        ListenableBuilder(
          listenable: data,
          builder: (_) => Theme(data: data.value, child: probe((_) {})),
        ),
      );
      expect(t.screen.styleAt(0, 0), ThemeData.dark().accent);
      data.value = ThemeData.light();
      await t.pump();
      expect(t.screen.styleAt(0, 0), ThemeData.light().accent);
    });

    testWidgets('backgroundOf and noColorOf read what runApp provides', (
      t,
    ) async {
      late TerminalBackground background;
      late bool noColor;
      const light = TerminalBackground(
        Brightness.light,
        BrightnessSource.colorFgBg,
      );
      await t.pumpWidget(
        TerminalEnvironment(
          background: light,
          noColor: true,
          child: Theme(
            data: ThemeData.dark(),
            child: probe((c) {
              background = Theme.backgroundOf(c);
              noColor = Theme.noColorOf(c);
            }),
          ),
        ),
      );
      expect(background, light);
      expect(noColor, isTrue);
    });
  });

  group('the framework\'s widgets read the theme', () {
    const sizes = [Size(120, 40), Size(80, 24)];
    const magenta = Style(fg: Colors.magenta);

    for (final size in sizes) {
      final at = '${size.width}x${size.height}';

      testWidgets('a border with no style is the theme\'s, at $at', (t) async {
        await t.pumpWidget(
          const Box(border: Border.rounded, title: 'log', height: 3),
          size: size,
        );
        expect(t.screen.charAt(0, 0), '╭');
        expect(t.screen.styleAt(0, 0), ThemeData.dark().border);
        expect(t.screen.styleAt(size.width - 1, 2), ThemeData.dark().border);
        // The title is the border's style, bold.
        expect(
          t.screen.styleAt(2, 0),
          ThemeData.dark().border.merge(Style.bold),
        );
        await t.pumpWidget(
          Theme(
            data: ThemeData.plain(),
            child: const Box(border: Border.single, height: 3),
          ),
          size: size,
        );
        expect(t.screen.styleAt(0, 0), Style.dim);
      });

      testWidgets('an explicit border style wins, at $at', (t) async {
        await t.pumpWidget(
          Theme(
            data: ThemeData.light(),
            child: Box(border: Border.single.withStyle(magenta), height: 3),
          ),
          size: size,
        );
        expect(t.screen.styleAt(0, 0), magenta);
      });

      testWidgets('KeyHelp\'s keys and descriptions, at $at', (t) async {
        Widget help(KeyHelp k) =>
            Actions(bindings: [Binding('ctrl+o', 'Toggle', () {})], child: k);
        await t.pumpWidget(
          Theme(
            data: ThemeData.dark().copyWith(
              text: const Style(fg: Colors.cyan),
              dim: const Style(fg: Colors.gray),
            ),
            child: help(const KeyHelp()),
          ),
          size: size,
        );
        expect(t.screen, shows('ctrl+o Toggle'));
        expect(
          t.screen.styleAt(0, 0),
          const Style(fg: Colors.cyan, bold: true),
        );
        expect(t.screen.styleAt(8, 0), const Style(fg: Colors.gray));
        await t.pumpWidget(
          help(
            const KeyHelp(keyStyle: magenta, descriptionStyle: Style.italic),
          ),
          size: size,
        );
        expect(t.screen.styleAt(0, 0), magenta);
        expect(t.screen.styleAt(8, 0), Style.italic);
      });

      testWidgets('TextInput\'s cursor, placeholder and prefix, at $at', (
        t,
      ) async {
        const cursor = Style(bg: Colors.yellow);
        const dim = Style(fg: Colors.gray);
        await t.pumpWidget(
          Theme(
            data: ThemeData.dark().copyWith(cursor: cursor, dim: dim),
            child: const TextInput(
              autofocus: true,
              prefix: '> ',
              placeholder: 'say',
            ),
          ),
          size: size,
        );
        expect(t.screen, shows('>  say'));
        expect(t.screen.styleAt(0, 0), dim);
        expect(t.screen.buffer.cursor, const Offset(2, 0));
        expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
        expect(t.screen.styleAt(3, 0), dim);
        await t.pumpWidget(
          Theme(
            data: ThemeData.dark().copyWith(cursor: cursor, dim: dim),
            child: const TextInput(
              autofocus: true,
              prefix: '> ',
              placeholder: 'say',
              cursorStyle: CursorStyle.steadyUnderline,
              placeholderStyle: Style.italic,
              prefixStyle: magenta,
            ),
          ),
          size: size,
        );
        expect(t.screen.styleAt(0, 0), magenta);
        expect(t.screen.buffer.cursor, const Offset(2, 0));
        expect(t.screen.buffer.cursorStyle, CursorStyle.steadyUnderline);
        expect(t.screen.styleAt(3, 0), Style.italic);
        await t.type('a');
        expect(t.screen.buffer.cursor, const Offset(3, 0));
        expect(t.screen.buffer.cursorStyle, CursorStyle.steadyUnderline);
      });
    }

    testWidgets('a border follows a change of theme', (t) async {
      final data = ValueNotifier(ThemeData.dark());
      await t.pumpWidget(
        ListenableBuilder(
          listenable: data,
          builder: (_) => Theme(
            data: data.value,
            child: const Box(border: Border.single, height: 3),
          ),
        ),
      );
      expect(t.screen.styleAt(0, 0), ThemeData.dark().border);
      data.value = ThemeData.plain();
      await t.pump();
      expect(t.screen.styleAt(0, 0), Style.dim);
    });
  });

  group('tester: inherited theme lifecycle', () {
    testWidgets('an identical child updates only for unequal theme values', (
      t,
    ) async {
      final revision = ValueNotifier(0);
      addTearDown(revision.dispose);
      var data = ThemeData.dark();
      var builds = 0;
      final child = Builder(
        builder: (c) {
          builds++;
          return Text('accent', style: Theme.of(c).accent);
        },
      );
      await t.pumpWidget(
        ListenableBuilder(
          listenable: revision,
          builder: (_) => Theme(data: data, child: child),
        ),
      );
      expect(builds, 1);
      data = ThemeData.dark();
      revision.value++;
      await t.pump();
      expect(builds, 1);
      data = ThemeData.light();
      revision.value++;
      await t.pump();
      expect(builds, 2);
      expect(t.screen.styleAt(0, 0), data.accent);
      await t.resize(const Size(120, 40));
      expect(t.screen.styleAt(0, 0), data.accent);
      await t.resize(const Size(1, 1));
      expect(t.screen.charAt(0, 0), 'a');
      await t.resize(Size.zero);
      await t.resize(const Size(80, 24));
      expect(t.screen, shows('accent'));
    });

    testWidgets(
      'environment changes reach a fixed child below an app override',
      (t) async {
        final revision = ValueNotifier(0);
        addTearDown(revision.dispose);
        var background = const TerminalBackground(
          Brightness.dark,
          BrightnessSource.fallback,
        );
        var noColor = false;
        var builds = 0;
        late TerminalBackground seen;
        late bool seenNoColor;
        final child = Theme(
          data: ThemeData.plain(),
          child: Builder(
            builder: (c) {
              builds++;
              seen = Theme.backgroundOf(c);
              seenNoColor = Theme.noColorOf(c);
              return Text('plain', style: Theme.of(c).accent);
            },
          ),
        );
        await t.pumpWidget(
          ListenableBuilder(
            listenable: revision,
            builder: (_) => TerminalEnvironment(
              background: background,
              noColor: noColor,
              child: child,
            ),
          ),
        );
        expect(builds, 1);
        background = const TerminalBackground(
          Brightness.dark,
          BrightnessSource.terminal,
        );
        revision.value++;
        await t.pump();
        expect(builds, 2);
        expect(seen, background);
        noColor = true;
        revision.value++;
        await t.pump();
        expect(builds, 3);
        expect(seenNoColor, isTrue);
        expect(t.screen.styleAt(0, 0), Style.plain);
        background = const TerminalBackground(
          Brightness.dark,
          BrightnessSource.terminal,
        );
        revision.value++;
        await t.pump();
        expect(builds, 3);
      },
    );

    testWidgets(
      'a thousand changes settle before a frame and detach on removal',
      (t) async {
        final data = ValueNotifier(ThemeData.dark());
        addTearDown(data.dispose);
        var builds = 0;
        final child = Builder(
          builder: (c) {
            builds++;
            return Text('日本語🙂e\u0301', style: Theme.of(c).accent);
          },
        );
        await t.pumpWidget(
          ListenableBuilder(
            listenable: data,
            builder: (_) => Theme(data: data.value, child: child),
          ),
        );
        for (var i = 0; i < 1000; i++) {
          data.value = i.isEven ? ThemeData.light() : ThemeData.dark();
        }
        data.value = ThemeData.light();
        await t.pump();
        expect(t.screen, shows('日本語🙂e\u0301'));
        expect(t.screen.styleAt(0, 0), ThemeData.light().accent);
        await t.pumpWidget(Text('removed'));
        final afterRemoval = builds;
        data.value = ThemeData.dark();
        await t.pump();
        expect(builds, afterRemoval);
        expect(t.screen, shows('removed'));
      },
    );

    test('nullable copyWith arguments preserve optional code and tint', () {
      final data = ThemeData.light();
      expect(data.copyWith(code: null), data);
      expect(data.diff.copyWith(tint: null), data.diff);
      expect(data.copyWith(diff: const DiffTheme()).diff.tint, isNull);
      expect(ThemeData.plain().copyWith(code: data.code).code, data.code);
    });
  });

  group('tester: themed widget state and overrides', () {
    for (final size in [const Size(80, 24), const Size(120, 40)]) {
      testWidgets('fixed help follows theme during a pending chord at $size', (
        t,
      ) async {
        final data = ValueNotifier(ThemeData.dark());
        addTearDown(data.dispose);
        await t.pumpWidget(
          ListenableBuilder(
            listenable: data,
            builder: (_) => Theme(
              data: data.value,
              child: Actions(
                bindings: [Binding('ctrl+x b', 'Busy', () {})],
                child: const KeyHelp(),
              ),
            ),
          ),
          size: size,
        );
        await t.press('ctrl+x');
        expect(t.screen, shows('ctrl+x …'));
        data.value = ThemeData.light().copyWith(
          text: const Style(fg: Colors.red),
          dim: Style.italic,
        );
        await t.pump();
        expect(t.screen.styleAt(0, 0), const Style(fg: Colors.red, bold: true));
        expect(t.screen, shows('Busy'));
        await t.press('b');
        expect(t.screen, shows('ctrl+x b Busy'));
        expect(t.screen.styleAt(9, 0), Style.italic);
      });

      testWidgets(
        'input preserves content and focus across theme changes at $size',
        (t) async {
          final data = ValueNotifier(ThemeData.dark());
          final controller = TextEditingController();
          addTearDown(data.dispose);
          addTearDown(controller.dispose);
          final input = Column(
            children: [
              TextInput(
                controller: controller,
                autofocus: true,
                placeholder: 'hint',
                prefix: '>',
              ),
              const TextInput(placeholder: 'second'),
            ],
          );
          await t.pumpWidget(
            ListenableBuilder(
              listenable: data,
              builder: (_) => Theme(data: data.value, child: input),
            ),
            size: size,
          );
          data.value = ThemeData.light().copyWith(
            dim: const Style(fg: Colors.green),
            cursor: Style.underline,
          );
          await t.pump();
          expect(t.screen.styleAt(0, 0), const Style(fg: Colors.green));
          expect(t.screen.buffer.cursor, const Offset(1, 0));
          expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
          expect(t.screen.styleAt(2, 0), const Style(fg: Colors.green));
          await t.paste('日🙂e\u0301');
          expect(controller.text, '日🙂e\u0301');
          await t.press('home');
          expect(t.screen.charAt(1, 0), '日');
          expect(t.screen.buffer.cursor, const Offset(1, 0));
          expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
          await t.press('tab');
          expect(t.screen.buffer.cursor, const Offset(0, 1));
          await t.press('shift+tab');
          expect(t.screen.buffer.cursor, const Offset(1, 0));
          expect(t.screen.buffer.cursorStyle, CursorStyle.steadyBlock);
          await t.resize(const Size(1, 1));
          await t.resize(Size.zero);
          await t.resize(size);
          expect(t.screen, shows('日🙂e\u0301'));
          await t.pumpWidget(Text('removed'));
          controller.text = 'late';
          data.value = ThemeData.plain();
          await t.pump();
          expect(t.screen, shows('removed'));
        },
      );
    }

    testWidgets(
      'plain explicit styles and inherited text survive a coloured theme',
      (t) async {
        const inherited = Style(fg: Colors.blue, bg: Colors.red);
        await t.pumpWidget(
          Theme(
            data: ThemeData.dark().copyWith(
              cursor: const Style(bg: Colors.yellow),
            ),
            child: DefaultTextStyle(
              style: inherited,
              child: Actions(
                bindings: [Binding('ctrl+o', 'Toggle', () {})],
                child: Column(
                  children: [
                    const Box(border: Border(style: Style.plain), height: 3),
                    const KeyHelp(
                      keyStyle: Style.plain,
                      descriptionStyle: Style.plain,
                    ),
                    const TextInput(
                      autofocus: true,
                      prefix: '>',
                      placeholder: 'hint',
                      cursorStyle: CursorStyle.steadyBlock,
                      prefixStyle: Style.plain,
                      placeholderStyle: Style.plain,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        expect(t.screen.styleAt(0, 0), Style.plain);
        expect(t.screen.styleAt(0, 3), inherited, reason: t.screen.text);
        expect(t.screen.styleAt(8, 3), inherited);
        for (var x = 0; x < 6; x++) {
          expect(t.screen.styleAt(x, 4), inherited);
        }
      },
    );
  });
}
