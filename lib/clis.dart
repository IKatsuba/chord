// The agents chord starts by a CLI the person installs themselves, each with
// the argv its own CLI takes ACP on stdio. Frozen from the original's
// src/clis.ts, where each argv is checked against the agent's own doc. A
// name the registry also starts is the registry's.

/// An agent its own CLI starts, as the table writes it.
class CliAgent {
  /// An agent of the table.
  const CliAgent({
    required this.name,
    required this.title,
    required this.argv,
    required this.install,
    this.mcpServers,
  });

  /// What `chord <name>` calls it: the registry's id where it lists one.
  final String name;

  /// What the agent calls itself, for people.
  final String title;

  /// The command and its words, taken whole.
  final List<String> argv;

  /// Where the agent says to install the CLI.
  final String install;

  /// `false` for an agent that refuses a session given any MCP server, which
  /// then gets none.
  final bool? mcpServers;
}

/// The agents started by their own CLI, in the table's order.
const cliAgents = <CliAgent>[
  CliAgent(
    name: 'autohand',
    title: 'Autohand Code',
    argv: ['autohand', '--acp'],
    install: 'https://github.com/autohandai/code-cli#installation',
  ),
  CliAgent(
    name: 'cursor',
    title: 'Cursor',
    argv: ['agent', 'acp'],
    install: 'https://cursor.com/docs/cli/installation',
  ),
  CliAgent(
    name: 'devin',
    title: 'Devin',
    argv: ['devin', 'acp'],
    install: 'https://docs.devin.ai/cli',
  ),
  CliAgent(
    name: 'fx',
    title: 'fx',
    argv: ['fx', 'acp'],
    install: 'https://github.com/vercel-labs/fx',
  ),
  CliAgent(
    name: 'goose',
    title: 'goose',
    argv: ['goose', 'acp'],
    install: 'https://goose-docs.ai/docs/getting-started/installation',
  ),
  CliAgent(
    name: 'junie',
    title: 'Junie',
    argv: ['junie', '--acp', 'true'],
    install: 'https://junie.jetbrains.com/docs/junie-cli.html',
  ),
  CliAgent(
    name: 'kiro',
    title: 'Kiro',
    argv: ['kiro-cli', 'acp', '--agent-engine=v3'],
    install: 'https://kiro.dev/docs/getting-started/installation/',
  ),
  CliAgent(
    name: 'openclaw',
    title: 'OpenClaw',
    argv: ['openclaw', 'acp'],
    install: 'https://docs.openclaw.ai/install',
    mcpServers: false,
  ),
  CliAgent(
    name: 'opencode',
    title: 'OpenCode',
    argv: ['opencode', 'acp'],
    install: 'https://opencode.ai/docs/',
  ),
  CliAgent(
    name: 'poolside',
    title: 'Poolside',
    argv: ['pool', 'acp'],
    install: 'https://github.com/poolsideai/pool',
  ),
  CliAgent(
    name: 'zeroclaw',
    title: 'ZeroClaw',
    argv: ['zeroclaw', 'acp'],
    install: 'https://github.com/zeroclaw-labs/zeroclaw',
  ),
];
