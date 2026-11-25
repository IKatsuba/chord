import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/agent_state.dart';
import 'package:chord/session/enrich.dart';
import 'package:test/test.dart';

acp.SessionUpdate update(Map<String, Object?> json) =>
    acp.SessionUpdate.fromJson(json);
Map<String, Object?> toolsOf(Wire wire, String id) => {
  for (final entry in wire.tools[id]!.entries)
    entry.key: {
      'title': entry.value.title,
      'kind': entry.value.kind,
      'ownContent': entry.value.ownContent,
    },
};
Map<String, Object?> stateOf(Wire wire, String id) {
  final state = wire.sessions[id]!;
  return {
    'options': state.configOptions,
    'modes': state.modes,
    'models': state.models,
    'commands': state.commands
        .map((c) => {'name': c.name, 'description': c.description})
        .toList(),
  };
}

void main() {
  test(
    'bulk recall equals ordinary fold, preserves order/ownContent and leaves source detached',
    () {
      const other = <String, ToolFacts>{'other': ToolFacts(title: 'other')};
      const original = Wire(
        tools: {
          'session': {'existing': ToolFacts(title: 'before', ownContent: true)},
          'other': other,
        },
        sessions: {
          'session': AgentState(
            modes: {'currentModeId': 'old', 'availableModes': <Object?>[]},
          ),
        },
      );
      final updates = [
        update({
          'sessionUpdate': 'tool_call',
          'toolCallId': '__proto__',
          'title': 'first',
          'kind': 'read',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': 'own'},
            },
          ],
        }),
        update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': '__proto__',
          'title': 'second',
        }),
        update({
          'sessionUpdate': 'tool_call_update',
          'toolCallId': 'existing',
          'content': <Object?>[],
        }),
        update({
          'sessionUpdate': 'tool_call',
          'toolCallId': 'filled',
          'content': [
            {
              'type': 'content',
              'content': {'type': 'text', 'text': 'filled'},
            },
          ],
          '_meta': {
            'chord/filled': ['content'],
          },
        }),
        update({'sessionUpdate': 'current_mode_update', 'currentModeId': 'A'}),
        update({
          'sessionUpdate': 'config_option_update',
          'configOptions': [
            {'id': 'mode', 'type': 'select', 'currentValue': 'B'},
          ],
        }),
        update({'sessionUpdate': 'current_mode_update', 'currentModeId': 'C'}),
        update({
          'sessionUpdate': 'available_commands_update',
          'availableCommands': [
            {'name': 'hello', 'description': 'command'},
          ],
        }),
      ];
      var ordinary = original;
      for (final report in updates) {
        ordinary = heardFromAgent(ordinary, {
          'method': 'session/update',
          'params': {'sessionId': 'session', 'update': report.toJson()},
        });
      }
      final work = RecallWork();
      final bulk = recalled(original, 'session', updates, work: work);
      expect(toolsOf(bulk, 'session'), toolsOf(ordinary, 'session'));
      expect(stateOf(bulk, 'session'), stateOf(ordinary, 'session'));
      expect(bulk.tools['session']!['__proto__']!.title, 'second');
      expect(bulk.tools['session']!['__proto__']!.ownContent, isTrue);
      expect(bulk.tools['session']!['existing']!.ownContent, isFalse);
      expect(bulk.tools['session']!['filled']!.ownContent, isFalse);
      expect(original.tools['session'], hasLength(1));
      expect(original.tools['session']!['existing']!.ownContent, isTrue);
      expect(identical(bulk.tools['other'], other), isTrue);
      expect(identical(bulk.asked, original.asked), isTrue);
      expect(
        () => bulk.tools['session']!['new'] = const ToolFacts(),
        throwsUnsupportedError,
      );
      expect(work.reports, updates.length);
      expect(work.copiedToolEntries, 1);
      expect(work.toolWrites, 4);
    },
  );

  test(
    '5000 distinct saved tools copy initial entries once rather than accumulated prefixes',
    () {
      const original = Wire(
        tools: {
          'session': {'existing': ToolFacts(title: 'before')},
        },
      );
      final work = RecallWork();
      final bulk = recalled(original, 'session', [
        for (var i = 0; i < 5000; i++)
          update({
            'sessionUpdate': 'tool_call',
            'toolCallId': 'tool-$i',
            'title': 'tool $i',
          }),
      ], work: work);
      expect(bulk.tools['session'], hasLength(5001));
      expect(work.reports, 5000);
      expect(work.toolWrites, 5000);
      expect(work.copiedToolEntries, 1);
      print(
        'recall reports=${work.reports} toolWrites=${work.toolWrites} copiedToolEntries=${work.copiedToolEntries} finalTools=${bulk.tools['session']!.length}',
      );
      expect(bulk.tools['session']!['tool-4999']!.title, 'tool 4999');
    },
  );

  test(
    'recall never marks a pending live setting as reported by historical state',
    () {
      var wire = heardFromChord(Wire.empty, {
        'id': 1,
        'method': 'session/set_mode',
        'params': {'sessionId': 'session', 'modeId': 'new'},
      });
      final before = wire.asked;
      wire = recalled(wire, 'session', [
        update({
          'sessionUpdate': 'current_mode_update',
          'currentModeId': 'historical',
        }),
      ]);
      expect(identical(wire.asked, before), isTrue);
      expect(wire.asked['1']!.modeReported, isFalse);
      expect(wire.sessions['session']!.modes, isNull);
    },
  );
}
