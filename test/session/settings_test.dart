import 'package:chord/session/choice.dart';
import 'package:chord/session/config.dart';
import 'package:chord/session/efforts.dart';
import 'package:chord/session/models.dart';
import 'package:chord/session/modes.dart';
import 'package:chord/session/parameters.dart';
import 'package:test/test.dart';

Map<String, Object?> select(
  String id,
  String category,
  List<Object?> values, {
  String current = 'unknown',
}) => {
  'id': id,
  'name': id,
  'type': 'select',
  'category': category,
  'currentValue': current,
  'options': values,
};
Map<String, Object?> value(String id, [String? name]) => {
  'value': id,
  'name': name ?? id,
};

void main() {
  test('mode config wins over legacy and grouped choices preserve order', () {
    final options = [
      select('permissions', 'mode', [
        value('plan'),
        {
          'group': 'g',
          'options': [value('accept'), value('default')],
        },
      ]),
    ];
    final modes = modesFrom(options, {
      'currentModeId': 'legacy',
      'availableModes': [
        {'id': 'legacy', 'name': 'Old'},
      ],
    })!;
    expect(modes.current, 'unknown');
    expect(modes.available.map((v) => v.id), ['plan', 'accept', 'default']);
    expect(modeConfigId(options), 'permissions');
    expect(nextMode(modes.available, modes.current), 'plan');
    expect(nextMode(modes.available, 'default'), 'plan');
    expect(nextMode([modes.available.first], 'plan'), isNull);
    expect(modesFrom([select('mode', 'other', [])]), isNull);
  });
  test('models prefer config, retain unknown current and validate legacy', () {
    final legacy = {
      'currentModelId': 'm',
      'availableModels': [
        {'modelId': 'm', 'name': ''},
      ],
    };
    expect(modelsFrom([], legacy)?.available.single.name, 'm');
    expect(
      modelsFrom([], {
        'currentModelId': 'm',
        'availableModels': [3],
      }),
      isNull,
    );
    final models = modelsFrom([
      select('which', 'model', [value('m', '')]),
    ], legacy)!;
    expect(models.available.single.name, 'm');
    expect(modelName(models), 'unknown');
    expect(
      modelsFrom([select('model', 'model', [], current: '')], legacy),
      isNull,
    );
  });
  test(
    'config excludes mode and model, leaves other selects in agent order',
    () {
      final options = [
        select('mode', 'misc', [value('a')]),
        select('m', 'model', [value('a')]),
        select('context', 'model_config', [value('large')]),
        select('empty', 'misc', []),
        {'id': 'future', 'type': 'future'},
        select('effort', 'thought_level', [
          value('low'),
          value('high'),
        ], current: 'high'),
      ];
      final found = optionsFromConfigOptions(options);
      expect(found.map((v) => v.id), ['context', 'effort']);
      expect(valueName(found.last, 'high'), 'high');
      expect(valueName(found.last, 'future'), 'future');
      expect(
        effortsFrom([
          select('effort', 'misc', [value('high')]),
        ]),
        isNull,
      );
      expect(effortsFrom(options)?.option, 'effort');
      expect(effortById(options, 'High'), isNull);
    },
  );
  test('effort after model uses fresh option id and exact value only', () {
    const effort = (option: 'old', value: 'high', name: 'High');
    const choice = ModelChoice(
      model: (id: 'next', name: 'Next'),
      effort: effort,
    );
    final options = [
      select('fresh', 'thought_level', [value('high')]),
    ];
    expect(effortStep(choice, options)?.option, 'fresh');
    expect(effortStep(const ModelChoice(effort: effort), options), isNull);
    expect(
      effortStep(choice, [
        select('fresh', 'thought_level', [value('High')]),
      ]),
      isNull,
    );
    expect(
      choiceNote(
        choice,
        const ChoiceResult(model: 'switched', effort: 'not_offered'),
        [],
        'Old',
      ).text,
      'Switched to Next; it offers no High effort.',
    );
  });
  test(
    'fast metadata wins over recorded id and ambiguous selects are refused',
    () {
      final recorded = select('recorded', 'model_config', [
        value('off'),
        value('on'),
      ], current: 'off');
      final marked = {
        ...select('marked', 'model_config', [
          value('no'),
          value('yes'),
        ], current: 'no'),
        '_meta': {'chord/parameter': 'fast'},
      };
      final fast = fastOption([recorded, marked], 'recorded')!;
      expect(fast.id, 'marked');
      expect(fastToggled(fast)?.value, 'yes');
      expect(
        fastToggled((
          id: 'bad',
          name: 'Bad',
          values: [(value: 'a', name: 'A'), (value: 'a', name: 'A')],
          current: 'a',
        )),
        isNull,
      );
    },
  );
}
