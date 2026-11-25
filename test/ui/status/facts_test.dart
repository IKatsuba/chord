import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/transcript/reducer.dart';
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/status/facts.dart';
import 'package:test/test.dart';

Map<String, Object?> option(
  String id,
  String category,
  String current,
  List<Object?> options,
) => {
  'id': id,
  'type': 'select',
  'category': category,
  'currentValue': current,
  'options': options,
};
Map<String, Object?> value(String id, String name) => {
  'value': id,
  'name': name,
};

void main() {
  test(
    'model config beats legacy models, including grouped values and id fallback',
    () {
      final legacy = {
        'currentModelId': 'old',
        'availableModels': [
          {'modelId': 'old', 'name': 'Legacy'},
        ],
      };
      final state = AgentState(
        models: legacy,
        configOptions: [
          option('runtime-model', 'model', 'new', [
            {
              'group': 'group',
              'options': [value('new', 'Reported model')],
            },
          ]),
        ],
      );
      expect(modelName(state), 'Reported model');
      expect(modelName(AgentState(models: legacy)), 'Legacy');
      expect(
        modelName(
          AgentState(
            configOptions: [
              option('model', 'other', 'new', [value('new', '')]),
            ],
          ),
        ),
        'new',
      );
      expect(
        modelName(
          AgentState(
            models: {'currentModelId': 'unlisted', 'availableModels': []},
          ),
        ),
        'unlisted',
      );
      expect(modelName(const AgentState()), isNull);
    },
  );
  test(
    'effort uses only thought_level category and displays the current id',
    () {
      expect(
        effortOf(
          AgentState(
            configOptions: [
              option('effort', 'other', 'high', [value('high', 'High')]),
            ],
          ),
        ),
        isNull,
      );
      expect(
        effortOf(
          AgentState(
            configOptions: [
              option('reasoning_effort', 'thought_level', 'high', [
                {
                  'group': 'group',
                  'options': [value('high', 'High display name')],
                },
              ]),
            ],
          ),
        ),
        'high',
      );
      expect(
        effortOf(
          AgentState(
            configOptions: [option('effort', 'thought_level', 'high', [])],
          ),
        ),
        isNull,
      );
    },
  );
  test('session/new mode options and legacy modes seed read-only status', () {
    final state = stateOf(
      acp.NewSessionResponse.fromJson({
        'sessionId': 's',
        'configOptions': [
          option('mode', 'mode', 'read-only', [
            value('read-only', 'Read Only'),
          ]),
        ],
      }),
    );
    final facts = statusFactsOf(state, Transcript.empty);
    expect((facts.mode, facts.modeName), ('read-only', 'Read Only'));
    final legacy = statusFactsOf(
      const AgentState(
        modes: {
          'currentModeId': 'plan',
          'availableModes': [
            {'id': 'plan', 'name': 'Plan'},
          ],
        },
      ),
      Transcript.empty,
    );
    expect((legacy.mode, legacy.modeName), ('plan', 'Plan'));
  });
  test(
    'mode update without option or legacy state falls through to transcript',
    () {
      final update = acp.SessionUpdate.fromJson({
        'sessionUpdate': 'current_mode_update',
        'currentModeId': 'plan',
      });
      final transcript = reduceTranscript(
        Transcript.empty,
        UpdateAction('t', update),
      );
      final state = foldUpdate(const AgentState(), update);
      expect(statusFactsOf(state, transcript).mode, 'plan');
    },
  );
  test(
    'config update after mode update reflects the newly reported option',
    () {
      var state = AgentState(
        configOptions: [
          option('mode', 'mode', 'default', [
            value('default', 'Default'),
            value('plan', 'Plan'),
          ]),
        ],
      );
      final update = acp.SessionUpdate.fromJson({
        'sessionUpdate': 'current_mode_update',
        'currentModeId': 'plan',
      });
      state = foldUpdate(state, update);
      final transcript = reduceTranscript(
        Transcript.empty,
        UpdateAction('t', update),
      );
      expect(statusFactsOf(state, transcript).mode, 'plan');
      state = foldUpdate(
        state,
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'config_option_update',
          'configOptions': [
            option('mode', 'mode', 'read-only', [
              value('read-only', 'Read Only'),
            ]),
          ],
        }),
      );
      final facts = statusFactsOf(state, transcript);
      expect((facts.mode, facts.modeName), ('read-only', 'Read Only'));
    },
  );
  group('tester U10 reported fact sources', () {
    test('mode id and display name come from the same winning source', () {
      const transcript = Transcript(
        entries: [],
        plan: [],
        turn: Idle(),
        mode: 'transcript-mode',
      );
      const legacy = {
        'currentModeId': 'same',
        'availableModes': [
          {'id': 'same', 'name': 'Legacy Name'},
        ],
      };
      final config = AgentState(
        modes: legacy,
        configOptions: [
          option('permissions', 'mode', 'same', [
            {
              'group': 'group',
              'options': [value('same', 'Config Name')],
            },
          ]),
        ],
      );
      final preferred = statusFactsOf(config, transcript);
      expect((preferred.mode, preferred.modeName), ('same', 'Config Name'));
      final fallback = statusFactsOf(
        const AgentState(modes: legacy),
        transcript,
      );
      expect((fallback.mode, fallback.modeName), ('same', 'Legacy Name'));
      final last = statusFactsOf(const AgentState(), transcript);
      expect((last.mode, last.modeName), ('transcript-mode', null));
    });

    test('model id fallback and effort category retain exact reported ids', () {
      final state = AgentState(
        configOptions: [
          option('runtime-model', 'model', 'unlisted-model', [
            value('other', 'Other'),
          ]),
          option('effort', 'other', 'wrong', [value('wrong', 'Wrong')]),
          option('custom', 'thought_level', 'ultra-id', [
            value('ultra-id', 'Display name'),
          ]),
        ],
      );
      expect(modelName(state), 'unlisted-model');
      expect(effortOf(state), 'ultra-id');
      expect(
        modelName(
          const AgentState(
            models: {
              'currentModelId': 'bad',
              'availableModels': [7],
            },
          ),
        ),
        isNull,
      );
    });

    test(
      'facts preserve reported usage identity and never infer absent fields',
      () {
        const usage = Usage(123.5, 999.5);
        const transcript = Transcript(
          entries: [],
          plan: [],
          turn: Idle(),
          usage: usage,
        );
        final facts = statusFactsOf(
          const AgentState(),
          transcript,
          notice: 'notice',
        );
        expect(identical(facts.usage, usage), isTrue);
        expect(
          (facts.model, facts.effort, facts.mode, facts.notice),
          (null, null, null, 'notice'),
        );
      },
    );
  });
}
