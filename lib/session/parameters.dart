import 'package:chord_tui/chord_tui.dart' show cellWidth, truncate;

import 'config.dart';
import 'efforts.dart';

/// The fast option, identified by metadata before a recorded adapter id.
AgentOption? fastOption(Object? options, [String? recorded]) {
  String? id = recorded;
  for (final option in selects(options)) {
    final meta = option['_meta'];
    if (meta is Map && meta['chord/parameter'] == 'fast') {
      id = option['id'] as String?;
      break;
    }
  }
  for (final option in optionsFromConfigOptions(options)) {
    if (option.id == id) return option;
  }
  return null;
}

/// The other fast value only for an unambiguous two-value select.
AgentOptionValue? fastToggled(AgentOption option) {
  final using = option.values.where((v) => v.value == option.current);
  final others = option.values.where((v) => v.value != option.current);
  return option.values.length == 2 && using.length == 1 && others.length == 1
      ? others.single
      : null;
}

/// An effort as asked, kept across a model change until acceptance.
typedef PendingEffort = ({String option, String value, String name});

/// Finds an effort by exact value id, never by its display name.
PendingEffort? effortById(Object? options, String value) {
  final efforts = effortsFrom(options);
  if (efforts == null) return null;
  for (final effort in efforts.available) {
    if (effort.id == value) {
      return (option: efforts.option, value: value, name: effort.name);
    }
  }
  return null;
}

/// Model settings in the order the agent offers them.
List<AgentOption> modelConfigOptions(Object? options) {
  final ids = {
    for (final option in selects(options))
      if (option['category'] == 'model_config') option['id'],
  };
  return optionsFromConfigOptions(
    options,
  ).where((o) => ids.contains(o.id)).toList();
}

/// Whether config has settings beyond the model's settings line.
bool hasOtherOptions(Object? options) {
  final effort = effortsFrom(options)?.option;
  final shown = {for (final o in modelConfigOptions(options)) o.id};
  return optionsFromConfigOptions(
    options,
  ).any((o) => o.id != effort && !shown.contains(o.id));
}

/// The model preview line and whether its shortened wording was used.
typedef SettingsLine = ({String text, bool dim, bool narrow});

/// Original model settings wording, with effort first as the width narrows.
SettingsLine? settingsLine({
  required Object? options,
  required String inUse,
  String? highlighted,
  String? pending,
  required int width,
  // The keys that move the effort, as the hint names them; none unbound.
  String? keys = '←/→',
}) {
  final effort = effortsFrom(options);
  final configs = modelConfigOptions(options);
  final others = hasOtherOptions(options);
  SettingsLine fit(List<String> wide, List<String> narrow) {
    final long = wide.join(' · ');
    final short = narrow.join(' · ');
    final fits = cellWidth(long) <= width;
    return (
      text: fits ? long : truncate(short, width < 1 ? 1 : width),
      dim: false,
      narrow: !fits,
    );
  }

  if (effort == null && configs.isEmpty) {
    if (configSelect(options, 'model') == null && !others) return null;
    return others
        ? fit(['/config for all settings'], ['/config…'])
        : (
            text: truncate('$inUse has no effort or settings to change', width),
            dim: true,
            narrow: false,
          );
  }
  AgentEffort? moved;
  AgentEffort? shown;
  for (final each in effort?.available ?? <AgentEffort>[]) {
    if (each.id == pending && pending != effort?.current) moved = each;
    if (each.id == effort?.current) shown = each;
  }
  final name = moved?.name ?? shown?.name ?? effort?.current ?? '';
  final mark = moved == null ? '' : ' •';
  final wide = [
    if (effort != null)
      '$name effort$mark${keys == null ? '' : '  $keys to adjust'}',
  ];
  final narrow = [
    if (effort != null) '$name effort$mark${keys == null ? '' : ' $keys'}',
  ];
  if (highlighted != null) {
    if (moved != null) {
      wide.add(
        'asked for once $highlighted is in use, if it offers ${moved.name}',
      );
      narrow.add('asked for on $highlighted, if offered');
    }
    return fit(wide, narrow);
  }
  for (final option in configs) {
    final value = valueName(option, option.current);
    wide.add('${option.name}  $value');
    narrow.add('${option.name} $value');
  }
  if (others) {
    wide.add('/config for all settings');
    narrow.add('/config…');
  }
  return fit(wide, narrow);
}
