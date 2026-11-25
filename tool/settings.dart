import 'package:chord/session/agent_state.dart';
import 'package:chord/session/efforts.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord/ui/pickers/state.dart';
import 'package:chord_tui/chord_tui.dart';

/// Reported choices with long grapheme-rich labels for setting-frame checks.
AgentState settingsFixtureAgent() {
  final middle = 'long label 界👩‍💻 ' * 12;
  Map<String, Object?> option(
    String id,
    String name,
    String category,
    List<Map<String, Object?>> values,
  ) => {
    'id': id,
    'name': name,
    'type': 'select',
    'category': category,
    'currentValue': values.first['value'],
    'options': values,
  };
  return AgentState(
    configOptions: [
      option('model', 'Model', 'model', [
        {'value': 'long', 'name': 'Model $middle tail'},
        {'value': 'short', 'name': 'Short model'},
      ]),
      option('effort', 'Effort', 'thought_level', [
        {'value': 'long', 'name': 'Value $middle tail'},
        {'value': 'short', 'name': 'Short value'},
      ]),
      option('other', 'Option $middle tail', 'other', [
        {'value': 'long', 'name': 'Value tail'},
      ]),
    ],
  );
}

void main(List<String> args) => runApp(
  _SettingsFixture(
    initial: SettingsPickerState(
      args.contains('--config') || args.contains('--values')
          ? 'config'
          : 'model',
      option: args.contains('--values') ? 'effort' : null,
    ),
  ),
);

class _SettingsFixture extends StatefulWidget {
  const _SettingsFixture({required this.initial});
  final SettingsPickerState initial;
  @override
  State<_SettingsFixture> createState() => _SettingsFixtureState();
}

class _SettingsFixtureState extends State<_SettingsFixture> {
  late var _state = widget.initial;
  final _agent = settingsFixtureAgent();
  @override
  Widget build(BuildContext context) => Actions(
    bindings: [Binding('ctrl+q', 'Quit fixture', () => exitApp(context))],
    child: LayoutBuilder(
      builder: (context, constraints) => Align(
        alignment: Alignment.bottomLeft,
        child: SettingsPicker(
          state: _state,
          agent: _agent,
          agentName: 'fixture-${'界👩‍💻long' * 12}-tail',
          windowRows: constraints.maxHeight,
          onAction: (action) => setState(
            () => _state = settingsPickerChanged(
              _state,
              action,
              effortsFrom(_agent.configOptions),
            ),
          ),
          onSelected: (_) {},
          onCanceled: () => exitApp(context),
        ),
      ),
    ),
  );
}
