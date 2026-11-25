/// What a saved setting changes in a running process. Nothing watches the
/// file and sessions keep what they were started with, so a saved `theme`,
/// `editorMode` or `offeredAgents` takes the same change its command makes,
/// a removed one falling to what an absent key gives; every other key
/// waits for the next start, or is read when it is needed. From the
/// original's `session/setting_picked_up.ts`.
library;

import '../settings.dart';

/// A saved setting's change, as whatever is running takes it up.
sealed class SettingPickedUp {
  const SettingPickedUp();
}

/// The theme to draw in, `auto` once removed.
final class ThemePickedUp extends SettingPickedUp {
  const ThemePickedUp(this.theme);
  final String theme;
}

/// Vim mode on or off.
final class EditorModePickedUp extends SettingPickedUp {
  const EditorModePickedUp({required this.vim});
  final bool vim;
}

/// The agents offered, none once removed.
final class OfferedAgentsPickedUp extends SettingPickedUp {
  const OfferedAgentsPickedUp(this.offered);
  final List<String>? offered;
}

/// What a running window takes up of [change] saved at [path]; null for a
/// key that waits for the next start.
SettingPickedUp? settingPickedUp(List<String> path, SettingChange change) {
  if (path.length != 1) return null;
  final value = change is SetSetting ? change.value : null;
  return switch (path.single) {
    'theme' => ThemePickedUp(value as String? ?? 'auto'),
    'editorMode' => EditorModePickedUp(vim: value == 'vim'),
    'offeredAgents' => OfferedAgentsPickedUp(
      (value as List<Object?>?)?.cast<String>(),
    ),
    _ => null,
  };
}
