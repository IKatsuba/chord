import 'package:chord/session/agent_state.dart';
import 'package:chord/session/efforts.dart';
import 'package:chord/session/parameters.dart';
import 'package:chord/ui/app/state.dart';
import 'package:chord/ui/start_state.dart';
import 'package:chord/session/conversation.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord/ui/pickers/state.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';
import '../../../tool/settings.dart' show settingsFixtureAgent;
import '../../session/settings_test.dart' show select, value;

final options = [
  select('model', 'model', [
    value('large', 'Large'),
    value('small', 'Small'),
  ], current: 'large'),
  select('effort', 'thought_level', [
    value('low', 'Low'),
    value('high', 'High'),
  ], current: 'low'),
];

void main() {
  test('initialized setting state matches original ready after exit', () {
    for (final phase in StartPhase.values) {
      expect(
        settingsSessionInitialized(phase),
        phase == StartPhase.connected || phase == StartPhase.gone,
      );
      expect(settingsSessionInitialized(phase, closing: true), isFalse);
    }
  });
  testWidgets('narrow model hint wraps whole and moves frame top up', (
    t,
  ) async {
    await t.pumpWidget(
      Align(
        alignment: Alignment.bottomLeft,
        child: SettingsPicker(
          state: const SettingsPickerState('model'),
          agent: AgentState(configOptions: options),
          agentName: 'fake',
          windowRows: 24,
          onAction: (_) {},
          onSelected: (_) {},
          onCanceled: () {},
        ),
      ),
      size: const Size(40, 24),
    );
    final lines = t.screen.lines;
    expect(lines.any((line) => line.contains('to close')), isTrue);
    final top = lines.indexWhere((line) => line.startsWith('╭'));
    expect(24 - top, 12);
  });

  test('effort preview reconciles removed values and unknown current ids', () {
    const pending = SettingsPickerState(
      'model',
      effort: (option: 'effort', value: 'high', name: 'High'),
    );
    const efforts = (
      option: 'effort',
      current: 'medium',
      available: [(id: 'low', name: 'Low'), (id: 'medium', name: 'Medium')],
    );
    expect(movedEffort(pending, efforts, 1).effort, isNull);
    expect(movedEffort(pending, efforts, -1).effort?.value, 'low');
    const unknown = (
      option: 'effort',
      current: 'unknown',
      available: [(id: 'low', name: 'Low')],
    );
    const state = SettingsPickerState('model');
    expect(movedEffort(state, unknown, 1), same(state));
    expect(
      movedEffort(state, (
        option: 'effort',
        current: 'none',
        available: <({String id, String name})>[],
      ), -1),
      same(state),
    );
    expect(
      movedEffort(
        const SettingsPickerState(
          'model',
          effort: (option: 'effort', value: 'low', name: 'Low'),
        ),
        efforts,
        1,
      ).effort,
      isNull,
    );
  });
  for (final kind in ['model', 'config', 'values']) {
    testWidgets(
      'long $kind labels and description retain both ends and graphemes',
      (t) async {
        await t.pumpWidget(
          SettingsPicker(
            state: SettingsPickerState(
              kind == 'model' ? 'model' : 'config',
              option: kind == 'values' ? 'effort' : null,
            ),
            agent: settingsFixtureAgent(),
            agentName: 'fake-${'界👩‍💻long' * 12}-tail',
            windowRows: 24,
            onAction: (_) {},
            onSelected: (_) {},
            onCanceled: () {},
          ),
          size: const Size(40, 24),
        );
        expect(t.screen.text, contains('...'));
        if (kind != 'config') expect(t.screen, shows('tail ✔'));
        if (kind == 'config') expect(t.screen, shows('tail'));
        expect(t.screen.text, contains('session.'));
        expect(t.screen.text, isNot(contains('�')));
      },
    );
  }

  test('pending mode acknowledgements cannot clear a newer mode request', () {
    var state = reduceApp(
      const AppState(),
      const ModePending('a', pending: true),
    );
    state = reduceApp(state, const ModePending('b', pending: true));
    state = reduceApp(state, const ModePending('a', pending: false));
    expect(state.pendingMode, 'b');
    expect(
      reduceApp(state, const ModePending('b', pending: false)).pendingMode,
      isNull,
    );
  });
  test('pending notes replace in place without replacing another entry', () {
    var state = reduceApp(
      const AppState(),
      const SettingNoted('a', 'model', 'Switching…'),
    );
    state = reduceApp(state, const SettingNoted('b', 'config', 'other'));
    final other = state.transcript.entries.last;
    state = reduceApp(state, const SettingNoted('a', 'model', 'Switched'));
    expect(state.transcript.entries, hasLength(2));
    expect((state.transcript.entries.first as NotedEntry).text, 'Switched');
    expect(state.transcript.entries.last, same(other));
  });
  test('settings line follows wide narrow pending and legacy rules', () {
    expect(settingsLine(options: [], inUse: 'Legacy', width: 80), isNull);
    expect(
      settingsLine(options: options, inUse: 'Large', width: 100)?.text,
      'Low effort  ←/→ to adjust',
    );
    expect(
      settingsLine(
        options: options,
        inUse: 'Large',
        highlighted: 'Small',
        pending: 'high',
        width: 200,
      )?.text,
      'High effort •  ←/→ to adjust · asked for once Small is in use, if it offers High',
    );
    expect(
      settingsLine(options: options, inUse: 'Large', width: 15)?.narrow,
      isTrue,
    );
    expect(
      cellWidth(
        settingsLine(options: options, inUse: 'Large', width: 15)!.text,
      ),
      lessThanOrEqualTo(15),
    );
  });
  for (final size in [const Size(120, 40), const Size(80, 24)]) {
    for (final theme in [
      ThemeData.dark(),
      ThemeData.light(),
      ThemeData.plain(),
    ]) {
      testWidgets(
        'setting frame previews without accepting at $size ${theme.brightness}',
        (t) async {
          final state = ValueNotifier(const SettingsPickerState('model'));
          final picked = <String>[];
          await t.pumpWidget(
            Theme(
              data: theme,
              child: ListenableBuilder(
                listenable: state,
                builder: (_) => Align(
                  alignment: Alignment.bottomLeft,
                  child: SettingsPicker(
                    state: state.value,
                    agent: AgentState(configOptions: options),
                    agentName: 'fake',
                    windowRows: size.height,
                    onAction: (action) => state.value = settingsPickerChanged(
                      state.value,
                      action,
                      effortsFrom(options),
                    ),
                    onSelected: picked.add,
                    onCanceled: () {},
                  ),
                ),
              ),
            ),
            size: size,
          );
          expect(t.screen, shows('Select model'));
          expect(t.screen, shows('Large ✔'));
          await t.press('right');
          expect(t.screen, shows('High effort •'));
          expect(picked, isEmpty);
          await t.press('down');
          expect(state.value.highlighted, 'small');
          await t.press('enter');
          expect(picked, ['small']);
          final title = t.screen.lines.indexWhere(
            (row) => row.contains('Select model'),
          );
          expect(t.screen.styleAt(2, title).fg, theme.focus.fg);
          t.dispose();
          state.dispose();
        },
      );
    }
    testWidgets(
      'short frame has only Esc and absent models invent no choice at $size',
      (t) async {
        final picked = <String>[];
        var canceled = false;
        await t.pumpWidget(
          Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              height: 6,
              child: SettingsPicker(
                state: const SettingsPickerState('model'),
                agent: AgentState(configOptions: options),
                agentName: 'fake',
                windowRows: size.height,
                onAction: (_) {},
                onSelected: picked.add,
                onCanceled: () => canceled = true,
              ),
            ),
          ),
          size: size,
        );
        await t.press('enter');
        await t.press('1');
        await t.press('right');
        expect(picked, isEmpty);
        await t.press('esc');
        expect(canceled, isTrue);
        await t.pumpWidget(
          SettingsPicker(
            state: const SettingsPickerState('model'),
            agent: AgentState.empty,
            agentName: 'fake',
            windowRows: size.height,
            onAction: (_) {},
            onSelected: picked.add,
            onCanceled: () {},
          ),
          size: size,
        );
        expect(t.screen, shows('fake offers no models to choose from.'));
        await t.press('enter');
        expect(picked, isEmpty);
      },
    );
  }
}
