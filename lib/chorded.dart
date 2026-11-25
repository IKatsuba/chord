// chord's own npx agents, the packages of the original's repository, in the
// registry's shape. Frozen from the original's src/chorded.ts: each version
// is the literal it pins.

import 'registry.dart';

/// One of chord's own agents: a registry entry, and whether it takes MCP
/// servers.
class ChordedAgent extends RegistryAgent {
  /// One of chord's own agents, as the original lists it.
  const ChordedAgent({
    required super.id,
    required super.name,
    required super.runner,
    required super.package,
    required super.version,
    required super.args,
    required super.env,
    super.website,
    super.repository,
  });

  /// A cloud VM reaches neither chord's MCP server nor the person's local
  /// ones, so chord says it holds them back rather than the agent dropping
  /// them.
  bool get mcpServers => false;
}

/// chord's own npx agents.
const chordedAgents = <ChordedAgent>[
  ChordedAgent(
    id: 'cursor-cloud',
    name: 'Cursor Cloud Agents',
    runner: Runner.npx,
    package: '@chorded/cursor-cloud-acp',
    version: '0.2.0',
    args: [],
    env: {},
    repository:
        'https://github.com/IKatsuba/chord/tree/main/packages/cursor-cloud-acp',
  ),
];
