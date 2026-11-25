import '../terminal/background.dart';
import 'framework.dart';
import 'theme_data.dart';

/// Hands [data] to everything below; the nearest one wins.
class Theme extends InheritedWidget {
  /// A theme of [data] over [child].
  const Theme({super.key, required this.data, required super.child});

  /// The roles the subtree paints with.
  final ThemeData data;

  /// The nearest Theme's data, or [ThemeData.fallback] with none above.
  static ThemeData of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Theme>()?.data ??
      ThemeData.fallback();

  /// What runApp found about the terminal's background; dark from
  /// [BrightnessSource.fallback] with no runApp above, as in the tester.
  static TerminalBackground backgroundOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TerminalEnvironment>()
          ?.background ??
      const TerminalBackground(Brightness.dark, BrightnessSource.fallback);

  /// Whether NO_COLOR was set; false with no runApp above.
  static bool noColorOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<TerminalEnvironment>()
          ?.noColor ??
      false;

  @override
  bool updateShouldNotify(Theme oldWidget) => data != oldWidget.data;
}

/// What runApp learnt about the terminal, above the app's own [Theme], so an
/// app that brings its own still knows what the terminal said. Not exported:
/// only runApp provides it.
class TerminalEnvironment extends InheritedWidget {
  /// The terminal's [background], and whether [noColor] was asked for.
  const TerminalEnvironment({
    super.key,
    required this.background,
    required this.noColor,
    required super.child,
  });

  /// The terminal's background and what said so.
  final TerminalBackground background;

  /// Whether NO_COLOR was set.
  final bool noColor;

  @override
  bool updateShouldNotify(TerminalEnvironment oldWidget) =>
      background != oldWidget.background || noColor != oldWidget.noColor;
}
