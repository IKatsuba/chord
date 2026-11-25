// Frozen from the original's src/registry.ts, which `bun dev registry`
// generates from the ACP Registry,
// https://cdn.agentclientprotocol.com/registry/v1/latest/registry.json.
// Entry for entry and in its order: refresh it from the original, never by
// hand.

/// What starts a registry agent: npx or uvx, with the registry's package.
enum Runner { npx, uvx }

/// An agent the ACP Registry offers through npx or uvx, at the version
/// fetched, with where it says to install it from.
class RegistryAgent {
  /// An agent as the registry lists it.
  const RegistryAgent({
    required this.id,
    required this.name,
    required this.runner,
    required this.package,
    required this.version,
    required this.args,
    required this.env,
    this.website,
    this.repository,
  });

  /// The registry's id, which `chord <name>` takes unless an alias stands in.
  final String id;

  /// What the registry calls it, for people.
  final String name;

  /// Whether npx or uvx runs it.
  final Runner runner;

  /// The package npx or uvx runs.
  final String package;

  /// The exact version of [package] that runs.
  final String version;

  /// The words after the package.
  final List<String> args;

  /// Laid over chord's own environment for the agent alone.
  final Map<String, String> env;

  /// The agent's site, where the registry gives one.
  final String? website;

  /// The agent's repository, where the registry gives one.
  final String? repository;
}

/// The day the registry was fetched.
const fetched = '2026-11-14';

/// The registry's npx and uvx agents, in the registry's order.
const registryAgents = <RegistryAgent>[
  RegistryAgent(
    id: 'agoragentic-acp',
    name: 'Agoragentic',
    runner: Runner.npx,
    package: 'agoragentic-mcp',
    version: '1.3.0',
    args: ['--acp'],
    env: {},
    website: 'https://agoragentic.com',
    repository: 'https://github.com/rhein1/agoragentic-integrations',
  ),
  RegistryAgent(
    id: 'auggie',
    name: 'Auggie CLI',
    runner: Runner.npx,
    package: '@augmentcode/auggie',
    version: '0.37.0',
    args: ['--acp'],
    env: {'AUGMENT_DISABLE_AUTO_UPDATE': '1'},
    website: 'https://www.augmentcode.com/',
    repository: 'https://github.com/augmentcode/auggie',
  ),
  RegistryAgent(
    id: 'bob',
    name: 'Bob',
    runner: Runner.npx,
    package: '@ibm/bob',
    version: '2.1.0',
    args: ['acp'],
    env: {},
    website: 'https://bob.ibm.com',
  ),
  RegistryAgent(
    id: 'claude-acp',
    name: 'Claude Agent',
    runner: Runner.npx,
    package: '@agentclientprotocol/claude-agent-acp',
    version: '0.107.0',
    args: [],
    env: {},
    repository: 'https://github.com/agentclientprotocol/claude-agent-acp',
  ),
  RegistryAgent(
    id: 'cline',
    name: 'Cline',
    runner: Runner.npx,
    package: 'cline',
    version: '3.0.74',
    args: ['--acp'],
    env: {},
    website: 'https://cline.bot/cli',
    repository: 'https://github.com/cline/cline',
  ),
  RegistryAgent(
    id: 'codebuddy-code',
    name: 'Codebuddy Code',
    runner: Runner.npx,
    package: '@tencent-ai/codebuddy-code',
    version: '2.184.0',
    args: ['--acp'],
    env: {},
    website: 'https://www.codebuddy.cn/cli/',
  ),
  RegistryAgent(
    id: 'codex-acp',
    name: 'Codex',
    runner: Runner.npx,
    package: '@agentclientprotocol/codex-acp',
    version: '2.6.0',
    args: [],
    env: {},
    repository: 'https://github.com/agentclientprotocol/codex-acp',
  ),
  RegistryAgent(
    id: 'deepagents',
    name: 'DeepAgents',
    runner: Runner.npx,
    package: 'deepagents-acp',
    version: '0.1.7',
    args: [],
    env: {},
    website: 'https://docs.langchain.com/oss/javascript/deepagents/overview',
    repository: 'https://github.com/langchain-ai/deepagentsjs',
  ),
  RegistryAgent(
    id: 'dimcode',
    name: 'DimCode',
    runner: Runner.npx,
    package: 'dimcode',
    version: '0.5.28',
    args: ['acp'],
    env: {},
    website: 'https://dimagent.cn/',
  ),
  RegistryAgent(
    id: 'dirac',
    name: 'Dirac',
    runner: Runner.npx,
    package: 'dirac-cli',
    version: '0.6.0',
    args: ['--acp'],
    env: {},
    website: 'https://dirac.run',
    repository: 'https://github.com/dirac-run/dirac',
  ),
  RegistryAgent(
    id: 'factory-droid',
    name: 'Factory Droid',
    runner: Runner.npx,
    package: 'droid',
    version: '1.11.0',
    args: ['exec', '--output-format', 'acp-daemon'],
    env: {
      'DROID_DISABLE_AUTO_UPDATE': 'true',
      'FACTORY_DROID_AUTO_UPDATE_ENABLED': 'false',
    },
    website: 'https://factory.ai/product/cli',
  ),
  RegistryAgent(
    id: 'fast-agent',
    name: 'fast-agent',
    runner: Runner.uvx,
    package: 'fast-agent-acp',
    version: '0.10.1',
    args: ['-x'],
    env: {'FAST_AGENT_MODEL': 'codexplan'},
    website: 'https://fast-agent.ai',
    repository: 'https://github.com/evalstate/fast-agent',
  ),
  RegistryAgent(
    id: 'gemini',
    name: 'Gemini CLI',
    runner: Runner.npx,
    package: '@google/gemini-cli',
    version: '0.68.0',
    args: ['--acp'],
    env: {},
    website: 'https://geminicli.com',
    repository: 'https://github.com/google-gemini/gemini-cli',
  ),
  RegistryAgent(
    id: 'github-copilot-cli',
    name: 'GitHub Copilot',
    runner: Runner.npx,
    package: '@github/copilot',
    version: '1.0.112',
    args: ['--acp'],
    env: {},
    website: 'https://github.com/features/copilot/cli/',
    repository: 'https://github.com/github/copilot-cli',
  ),
  RegistryAgent(
    id: 'glm-acp-agent',
    name: 'GLM Agent',
    runner: Runner.npx,
    package: 'glm-acp-agent',
    version: '1.17.1',
    args: [],
    env: {},
    repository: 'https://github.com/stefandevo/glm-acp-agent',
  ),
  RegistryAgent(
    id: 'grok-build',
    name: 'Grok Build',
    runner: Runner.npx,
    package: '@xai-official/grok',
    version: '1.0.85',
    args: ['agent', 'stdio'],
    env: {},
    website: 'https://x.ai/cli',
  ),
  RegistryAgent(
    id: 'kilo',
    name: 'Kilo',
    runner: Runner.npx,
    package: '@kilocode/cli',
    version: '7.8.27',
    args: ['acp'],
    env: {},
    website: 'https://kilo.ai/',
    repository: 'https://github.com/Kilo-Org/kilocode',
  ),
  RegistryAgent(
    id: 'kimi-code',
    name: 'Kimi Code',
    runner: Runner.npx,
    package: '@moonshot-ai/kimi-code',
    version: '2.6.2',
    args: ['acp'],
    env: {},
    website: 'https://moonshotai.github.io/kimi-code/',
    repository: 'https://github.com/MoonshotAI/kimi-code',
  ),
  RegistryAgent(
    id: 'minimax-code',
    name: 'MiniMax Code',
    runner: Runner.npx,
    package: '@minimax-ai/code',
    version: '0.2.7',
    args: ['acp'],
    env: {},
    website: 'https://agent.minimax.io',
  ),
  RegistryAgent(
    id: 'minion-code',
    name: 'Minion Code',
    runner: Runner.uvx,
    package: 'minion-code',
    version: '0.1.44',
    args: ['acp'],
    env: {},
    repository: 'https://github.com/femto/minion-code',
  ),
  RegistryAgent(
    id: 'nova',
    name: 'Nova',
    runner: Runner.npx,
    package: '@compass-ai/nova',
    version: '1.1.65',
    args: ['acp'],
    env: {},
    website: 'https://www.compassap.ai/portfolio/nova.html',
    repository: 'https://github.com/Compass-Agentic-Platform/nova',
  ),
  RegistryAgent(
    id: 'pi-acp',
    name: 'pi ACP',
    runner: Runner.npx,
    package: 'pi-acp',
    version: '0.0.34',
    args: [],
    env: {},
    repository: 'https://github.com/svkozak/pi-acp',
  ),
  RegistryAgent(
    id: 'qoder',
    name: 'Qoder CLI',
    runner: Runner.npx,
    package: '@qoder-ai/qodercli',
    version: '1.1.89',
    args: ['--acp'],
    env: {},
    website: 'https://qoder.com',
  ),
  RegistryAgent(
    id: 'qwen-code',
    name: 'Qwen Code',
    runner: Runner.npx,
    package: '@qwen-code/qwen-code',
    version: '0.27.3',
    args: ['--acp', '--experimental-skills'],
    env: {},
    website: 'https://qwenlm.github.io/qwen-code-docs/en/users/overview',
    repository: 'https://github.com/QwenLM/qwen-code',
  ),
  RegistryAgent(
    id: 'sigit',
    name: 'siGit Code',
    runner: Runner.npx,
    package: '@smbcloud/sigit',
    version: '1.7.10',
    args: [],
    env: {},
    website: 'https://github.com/getsigit/sigit',
    repository: 'https://github.com/getsigit/sigit',
  ),
];
