// Which key does what, handed down as the palette is, so every hint that
// names a key names the one bound to it, as the original's
// src/ui/app/context.ts.
import 'package:chord_tui/chord_tui.dart';

import '../shortcuts/bindings.dart';

/// The keybindings file over chord's keys, for the widgets under it.
class Keys extends InheritedWidget {
  const Keys({super.key, required this.keymap, required super.child});

  final Keybindings keymap;

  /// The nearest keymap; chord's own keys without one.
  static Keybindings of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<Keys>()?.keymap ??
      defaultKeymap;

  @override
  bool updateShouldNotify(Keys oldWidget) => keymap != oldWidget.keymap;
}

/// [action]'s key as a hint names it; none when nothing is bound to it.
String? hintKeyOf(BuildContext context, String action) =>
    hintKey(Keys.of(context), action);

/// The key that closes a picker, then [words]; none when nothing does.
String? closeHint(BuildContext context, [String words = 'to close']) {
  final key = hintKeyOf(context, 'select:cancel');
  return key == null ? null : '${capital(key)} $words';
}

/// [key] as a hint starts a sentence with it: `Esc`, `Ctrl+g`.
String capital(String key) =>
    key.isEmpty ? key : key[0].toUpperCase() + key.substring(1);

/// The first keys of [actions] as the file binds them, as the framework
/// spells them: a list or picker inside leaves them to the actions, which
/// the original hears before the list's own keys.
Set<String> boundKeys(BuildContext context, List<String> actions) {
  final keymap = Keys.of(context);
  return {
    for (final action in actions)
      for (final keys in keysOf(keymap, action)) '${keys.first.combo}',
  };
}
