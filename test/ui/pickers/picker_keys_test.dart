// The pickers' keys follow the keybindings file, as the original reads
// select:cancel, select:toggleScope and the model picker's effort through
// its keymap (src/ui/app/state.ts).
import 'dart:convert';

import 'package:chord/session/agent_state.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord/ui/pickers/state.dart';
import 'package:chord/ui/shortcuts/bindings.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

import 'resume_picker_cap_test.dart' show saved;
import 'settings_picker_test.dart' show options;

KeymapData file(List<Object?> blocks) =>
    readKeybindings(jsonEncode({'bindings': blocks})).keymap.data;

void main() {
  for (final size in const [Size(120, 40), Size(80, 24)]) {
    testWidgets('the resume picker closes and changes scope on the file\'s '
        'keys, at $size', (t) async {
      var scopes = 0, cancels = 0;
      await t.pumpWidget(
        Keymap(
          data: file([
            {
              'context': 'Select',
              'bindings': {
                'escape': null,
                'ctrl+g': 'select:cancel',
                'ctrl+a': null,
                'ctrl+t': 'select:toggleScope',
              },
            },
          ]),
          child: ResumePicker(
            picker: saved(2, 'Short'),
            agent: 'fake',
            rows: 10,
            room: size.height,
            onToggleScope: () => scopes++,
            onCanceled: () => cancels++,
            onSelected: (_) {},
          ),
        ),
        size: size,
      );
      await t.press('esc');
      await t.press('ctrl+a');
      expect((scopes, cancels), (0, 0));
      await t.press('ctrl+t');
      await t.press('ctrl+g');
      expect((scopes, cancels), (1, 1));
    });

    testWidgets('the model picker moves effort and closes on the file\'s '
        'keys, at $size', (t) async {
      final moves = <int>[];
      var cancels = 0;
      await t.pumpWidget(
        Keymap(
          data: file([
            {
              'context': 'ModelPicker',
              'bindings': {
                'left': null,
                '[': 'modelPicker:decreaseEffort',
                ']': 'modelPicker:increaseEffort',
              },
            },
            {
              'context': 'Select',
              'bindings': {'q': 'select:cancel'},
            },
          ]),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: SettingsPicker(
              state: const SettingsPickerState('model'),
              agent: AgentState(configOptions: options),
              agentName: 'fake',
              windowRows: size.height,
              onAction: (action) {
                if (action is EffortMoved) moves.add(action.by);
              },
              onSelected: (_) {},
              onCanceled: () => cancels++,
            ),
          ),
        ),
        size: size,
      );
      await t.press('left');
      expect(moves, isEmpty);
      await t.press('[');
      await t.press(']');
      await t.press('right');
      expect(moves, [-1, 1, 1]);
      await t.press('q');
      expect(cancels, 1);
    });
  }
}
