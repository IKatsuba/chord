import 'package:chord_tui/chord_tui.dart' show KeyCombo;

/// The panel and the framework's pending chord, with no second key recognizer.
final class ShortcutsState {
  const ShortcutsState({
    this.help = false,
    this.panelOverflows = false,
    this.pendingKeys = const [],
  });
  final bool help;
  final bool panelOverflows;
  final List<KeyCombo> pendingKeys;
}

/// An intent changing the shortcuts panel's plain state.
sealed class ShortcutsAction {
  const ShortcutsAction();
}

final class HelpToggled extends ShortcutsAction {
  const HelpToggled();
}

final class HelpClosed extends ShortcutsAction {
  const HelpClosed();
}

/// `/help`: opens the panel, and leaves it open when it is.
final class HelpOpened extends ShortcutsAction {
  const HelpOpened();
}

final class KeysPending extends ShortcutsAction {
  const KeysPending(this.keys);
  final List<KeyCombo> keys;
}

final class PanelOverflowed extends ShortcutsAction {
  const PanelOverflowed(this.overflows);
  final bool overflows;
}

/// The original M1 panel reducer, retaining identity for unchanged facts.
ShortcutsState reduceShortcuts(ShortcutsState state, ShortcutsAction action) {
  switch (action) {
    case HelpToggled():
      return ShortcutsState(help: !state.help, pendingKeys: state.pendingKeys);
    case HelpOpened():
      return state.help
          ? state
          : ShortcutsState(help: true, pendingKeys: state.pendingKeys);
    case HelpClosed():
      return state.help || state.panelOverflows
          ? ShortcutsState(pendingKeys: state.pendingKeys)
          : state;
    case KeysPending(:final keys):
      if (keys.length == state.pendingKeys.length &&
          List.generate(
            keys.length,
            (i) => keys[i] == state.pendingKeys[i],
          ).every((same) => same)) {
        return state;
      }
      return ShortcutsState(
        help: state.help,
        panelOverflows: state.panelOverflows,
        pendingKeys: List.unmodifiable(keys),
      );
    case PanelOverflowed(:final overflows):
      final next = state.help && overflows;
      return next == state.panelOverflows
          ? state
          : ShortcutsState(
              help: state.help,
              panelOverflows: next,
              pendingKeys: state.pendingKeys,
            );
  }
}
