// chord's themes, from the original's tests/ui/theme/theme_test.ts.
import 'dart:math' as math;

import 'package:chord/ui/theme/theme.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

/// WCAG's contrast ratio of two `#rrggbb` colours.
double contrast(String a, String b) {
  double luminance(String hex) {
    final channels =
        [
              for (final at in [1, 3, 5])
                int.parse(hex.substring(at, at + 2), radix: 16) / 255,
            ]
            .map(
              (c) => c <= 0.03928
                  ? c / 12.92
                  : math.pow((c + 0.055) / 1.055, 2.4).toDouble(),
            )
            .toList();
    return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
  }

  final x = luminance(a), y = luminance(b);
  return (math.max(x, y) + 0.05) / (math.min(x, y) + 0.05);
}

const light = TerminalBackground(Brightness.light, BrightnessSource.terminal);

void main() {
  test('auto comes to the background; a named theme is itself', () {
    expect(resolveTheme('auto', light), 'light');
    expect(resolveTheme('dark', light), 'dark');
    expect(resolveTheme('light-ansi', light), 'light-ansi');
  });

  test('Auto says what it found and where', () {
    expect(themeLabel('auto', light), 'Auto (light, from the terminal)');
    expect(
      themeLabel(
        'auto',
        const TerminalBackground(Brightness.dark, BrightnessSource.fallback),
      ),
      'Auto (dark: the terminal did not say)',
    );
    expect(
      themeLabel(
        'auto',
        const TerminalBackground(Brightness.light, BrightnessSource.colorFgBg),
      ),
      'Auto (light, from COLORFGBG)',
    );
  });

  test("/theme lists Claude Code's seven ids, the one in use marked", () {
    final choices = themeChoices(
      'light',
      const TerminalBackground(Brightness.dark, BrightnessSource.terminal),
    );
    expect(choices.map((c) => c.value), themeSettingIds);
    expect(choices.map((c) => c.label), [
      'Auto (dark, from the terminal)',
      'Dark',
      'Light ✔',
      'Dark, colour-blind friendly',
      'Light, colour-blind friendly',
      "Dark, the terminal's 16 colours",
      "Light, the terminal's 16 colours",
    ]);
    expect(choices.where((c) => c.current), hasLength(1));
    expect(themeName('auto'), 'Auto');
    expect(themeName('light'), 'Light');
    expect(isThemeSetting('dark-ansi'), isTrue);
    expect(isThemeSetting('solarized'), isFalse);
  });

  test('the light diff is pale tints under dark text', () {
    final tint = palettes['light']!.tint!;
    expect(tint, (added: '#dcf5e0', removed: '#fde2e2', text: '#1f2328'));
    expect(contrast(tint.added, '#ffffff'), lessThan(1.3));
    expect(contrast(tint.text, tint.added), greaterThan(12));
    expect(
      contrast(palettes['light']!.diffAdded!, tint.added),
      greaterThanOrEqualTo(4.5),
    );
  });

  test('every light colour reads on white, every dark one on black', () {
    for (final (name, ground) in [('light', '#ffffff'), ('dark', '#000000')]) {
      final p = palettes[name]!;
      for (final role in [
        p.accent,
        p.permission,
        p.inlineCode,
        p.link,
        p.bash,
        p.plan,
        p.edits,
        p.auto,
        p.error,
        p.warning,
        p.success,
      ]) {
        expect(
          contrast(role!, ground),
          greaterThanOrEqualTo(4.5),
          reason: '$name $role on $ground',
        );
      }
      for (final tone in p.code!.values) {
        expect(
          contrast(tone, ground),
          greaterThanOrEqualTo(4.5),
          reason: '$name $tone on $ground',
        );
      }
      for (final tint in [p.tint!.added, p.tint!.removed]) {
        for (final tone in p.codeOnTint!.values) {
          expect(
            contrast(tone, tint),
            greaterThanOrEqualTo(4.1),
            reason: '$name $tone on $tint',
          );
        }
      }
    }
  });

  test('the 16-colour themes have no tint and no hex', () {
    for (final name in ['dark-ansi', 'light-ansi']) {
      final p = palettes[name]!;
      expect(p.tint, isNull);
      final all = [
        p.accent,
        p.permission,
        p.inlineCode,
        p.link,
        p.bash,
        p.plan,
        p.edits,
        p.auto,
        p.error,
        p.warning,
        p.success,
        p.selection,
        p.diffAdded,
        p.diffRemoved,
        ...?p.agents,
        ...?p.code?.values,
      ];
      expect(all.any((c) => c != null && c.contains('#')), isFalse);
    }
    expect(palettes['dark-ansi']!.diffAdded, 'greenBright');
    expect(palettes['light-ansi']!.diffRemoved, 'red');
  });

  test('colour-blind themes move only the diff, off red and green', () {
    final blind = palettes['light-daltonized']!, plain = palettes['light']!;
    expect(blind.accent, plain.accent);
    expect(blind.code, plain.code);
    expect(blind.agents, plain.agents);
    expect(blind.selection, plain.selection);
    expect(blind.tint?.added, '#dbeeff');
    expect(blind.tint?.removed, '#fde8d4');
  });

  test('no colour leaves no role painted', () {
    expect(paletteOf('light', false), same(plainPalette));
    expect(paletteOf('light', true), same(palettes['light']));
  });

  test("/theme fits a 24-row window's room with its sample; a shorter room "
      'drops it, then choices', () {
    expect(themePickerLayout(35), (choices: 7, sample: true));
    expect(themePickerLayout(18), (choices: 7, sample: true));
    expect(themePickerLayout(17), (choices: 7, sample: false));
    expect(themePickerLayout(14), (choices: 7, sample: false));
    // Fewer: the row that counts the hidden ones takes one of theirs.
    expect(themePickerLayout(13), (choices: 5, sample: false));
    expect(themePickerLayout(9), (choices: 1, sample: false));
    expect(themePickerLayout(7), (choices: 0, sample: false));
  });

  test("every theme gives a session's agents six colours", () {
    for (final MapEntry(:key, :value) in palettes.entries) {
      expect(value.agents, hasLength(6), reason: key);
    }
    expect(agentColour(palettes['dark']!, 0), '#6cb6ff');
    expect(agentColour(palettes['light']!, 7), '#7a3fd6');
    expect(agentColour(palettes['dark-ansi']!, 5), 'redBright');
    expect(agentColour(plainPalette, 0), isNull);
    expect(agentColour(palettes['dark']!, null), isNull);
  });

  test('every theme paints a selection, plain included', () {
    for (final name in ['dark', 'dark-daltonized', 'dark-ansi']) {
      expect(palettes[name]!.selection, 'ansi256(66)');
    }
    for (final name in ['light', 'light-daltonized', 'light-ansi']) {
      expect(palettes[name]!.selection, 'ansi256(152)');
    }
    expect(paletteOf('light', false).selection, 'ansi256(66)');
  });

  group('the framework theme of each palette', () {
    test('dark and light draw as the framework defaults, chord roles with '
        'them', () {
      final dark = themeData('dark'), framework = ThemeData.dark();
      expect(dark.brightness, Brightness.dark);
      expect(dark.accent, framework.accent);
      expect(dark.focus, framework.focus);
      expect(dark.selection, framework.selection);
      expect(dark.diff, framework.diff);
      expect(dark.code, framework.code);
      final light = themeData('light');
      expect(light.diff, ThemeData.light().diff);
      expect(light.code, ThemeData.light().code);
      expect(light.extension<ChordTheme>()!.bash.fg, RgbColor.hex('#d1006f'));
    });

    test('the sixteen colours are the terminal\'s own; no colour is plain', () {
      final ansi = themeData('dark-ansi');
      expect(ansi.accent.fg, Colors.brightYellow);
      expect(ansi.diff.tint, isNull);
      expect(ansi.selection.bg, const IndexedColor(66));
      expect(themeData('light-ansi').brightness, Brightness.light);
      final none = themeData('light', colour: false);
      expect(none.accent, Style.plain);
      expect(none.extension<ChordTheme>(), same(chordPlain));
    });

    test('a daltonized theme moves only its diff', () {
      final blind = themeData('dark-daltonized');
      expect(blind.diff.added.fg, RgbColor.hex('#6cb6ff'));
      expect(blind.accent, themeData('dark').accent);
    });
  });
}
