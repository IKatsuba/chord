import 'package:chord/chorded.dart';
import 'package:chord/clis.dart';
import 'package:chord/registry.dart';
import 'package:test/test.dart';

void main() {
  test('each agent is listed once', () {
    final ids = [
      for (final agent in [...registryAgents, ...chordedAgents]) agent.id,
    ];
    final names = [for (final agent in cliAgents) agent.name];

    expect(ids.toSet(), hasLength(ids.length));
    expect(names.toSet(), hasLength(names.length));
  });

  test('every registry agent is at an exact version', () {
    for (final agent in [...registryAgents, ...chordedAgents]) {
      expect(
        RegExp(r'^\d+\.\d+\.\d+$').hasMatch(agent.version),
        isTrue,
        reason: agent.id,
      );
    }
  });

  test(
    'an agent npx and uvx both start is frozen as npx, one uvx alone as uvx',
    () {
      expect(
        [
          for (final agent in registryAgents)
            if (agent.runner == Runner.uvx) agent.id,
        ],
        ['fast-agent', 'minion-code'],
      );
    },
  );

  test(
    "chord's own agent and the table's MCP refusals are as the original's",
    () {
      expect(chordedAgents.single.id, 'cursor-cloud');
      expect(chordedAgents.single.mcpServers, isFalse);
      expect(
        [
          for (final agent in cliAgents)
            if (agent.mcpServers == false) agent.name,
        ],
        ['openclaw'],
      );
    },
  );

  group('tester: frozen launch data', () {
    test('registry arguments preserve every word and its order', () {
      expect(
        {for (final agent in registryAgents) agent.id: agent.args},
        {
          'agoragentic-acp': ['--acp'],
          'auggie': ['--acp'],
          'bob': ['acp'],
          'claude-acp': <String>[],
          'cline': ['--acp'],
          'codebuddy-code': ['--acp'],
          'codex-acp': <String>[],
          'deepagents': <String>[],
          'dimcode': ['acp'],
          'dirac': ['--acp'],
          'factory-droid': ['exec', '--output-format', 'acp-daemon'],
          'fast-agent': ['-x'],
          'gemini': ['--acp'],
          'github-copilot-cli': ['--acp'],
          'glm-acp-agent': <String>[],
          'grok-build': ['agent', 'stdio'],
          'kilo': ['acp'],
          'kimi-code': ['acp'],
          'minimax-code': ['acp'],
          'minion-code': ['acp'],
          'nova': ['acp'],
          'pi-acp': <String>[],
          'qoder': ['--acp'],
          'qwen-code': ['--acp', '--experimental-skills'],
          'sigit': <String>[],
        },
      );
    });

    test('only the original environment overrides are supplied', () {
      expect(
        {
          for (final agent in registryAgents)
            if (agent.env.isNotEmpty) agent.id: agent.env,
        },
        {
          'auggie': {'AUGMENT_DISABLE_AUTO_UPDATE': '1'},
          'factory-droid': {
            'DROID_DISABLE_AUTO_UPDATE': 'true',
            'FACTORY_DROID_AUTO_UPDATE_ENABLED': 'false',
          },
          'fast-agent': {'FAST_AGENT_MODEL': 'codexplan'},
        },
      );
      expect(chordedAgents.single.args, isEmpty);
      expect(chordedAgents.single.env, isEmpty);
    });

    test('own CLI commands preserve executable aliases and arguments', () {
      expect(
        {for (final agent in cliAgents) agent.name: agent.argv},
        {
          'autohand': ['autohand', '--acp'],
          'cursor': ['agent', 'acp'],
          'devin': ['devin', 'acp'],
          'fx': ['fx', 'acp'],
          'goose': ['goose', 'acp'],
          'junie': ['junie', '--acp', 'true'],
          'kiro': ['kiro-cli', 'acp', '--agent-engine=v3'],
          'openclaw': ['openclaw', 'acp'],
          'opencode': ['opencode', 'acp'],
          'poolside': ['pool', 'acp'],
          'zeroclaw': ['zeroclaw', 'acp'],
        },
      );
    });
  });
}
