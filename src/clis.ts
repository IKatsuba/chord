/**
 * The agents chord starts by a CLI the person installs themselves, each with
 * the argv its own CLI takes ACP on stdio. Written by hand from acpx 0.19.4's
 * table, every argv checked against the doc named beside it; one whose ACP
 * command no doc of the agent's states is left out (`docs/decisions.md`,
 * "Agents started by their own CLI"). A name the registry also starts is the
 * registry's.
 */

/** An agent its own CLI starts, as the table writes it. */
export interface CliAgent {
  /** What `chord <name>` calls it: the registry's id where it lists one. */
  readonly name: string;
  readonly title: string;
  readonly argv: readonly string[];
  /** Where the agent says to install the CLI. */
  readonly install: string;
  /**
   * `false` for an agent that refuses a session given any MCP server, which
   * then gets none, as `agents.<name>.mcpServers: false` gives; a setting
   * of `true` gives them back (CHD-441).
   */
  readonly mcpServers?: false;
}

export const CLI_AGENTS: readonly CliAgent[] = [
  {
    // https://cursor.com/docs/cli/acp
    name: 'cursor',
    title: 'Cursor',
    argv: ['agent', 'acp'],
    install: 'https://cursor.com/docs/cli/installation',
  },
  {
    // https://docs.devin.ai/cli/acp/zed
    name: 'devin',
    title: 'Devin',
    argv: ['devin', 'acp'],
    install: 'https://docs.devin.ai/cli',
  },
  {
    // https://github.com/vercel-labs/fx
    name: 'fx',
    title: 'fx',
    argv: ['fx', 'acp'],
    install: 'https://github.com/vercel-labs/fx',
  },
  {
    // https://goose-docs.ai/docs/gdk/acp/
    name: 'goose',
    title: 'goose',
    argv: ['goose', 'acp'],
    install: 'https://goose-docs.ai/docs/getting-started/installation',
  },
  {
    // https://junie.jetbrains.com/docs/junie-cli-acp.html
    name: 'junie',
    title: 'Junie',
    argv: ['junie', '--acp', 'true'],
    install: 'https://junie.jetbrains.com/docs/junie-cli.html',
  },
  {
    // https://www.kimi.com/code/docs/en/kimi-code-cli/reference/kimi-acp
    name: 'kimi',
    title: 'Kimi Code',
    argv: ['kimi', 'acp'],
    install:
      'https://www.kimi.com/code/docs/en/kimi-code-cli/guides/getting-started.html',
  },
  {
    // https://kiro.dev/docs/cli/acp/
    name: 'kiro',
    title: 'Kiro',
    argv: ['kiro-cli', 'acp'],
    install: 'https://kiro.dev/docs/getting-started/installation/',
  },
  {
    // https://docs.openclaw.ai/cli/acp
    name: 'openclaw',
    title: 'OpenClaw',
    argv: ['openclaw', 'acp'],
    install: 'https://docs.openclaw.ai/install',
    // Its ACP bridge refuses any non-empty mcpServers on new, load and
    // resume (docs/agent-capabilities.md oc3; the owner's Q90).
    mcpServers: false,
  },
  {
    // https://opencode.ai/docs/acp/
    name: 'opencode',
    title: 'OpenCode',
    argv: ['opencode', 'acp'],
    install: 'https://opencode.ai/docs/',
  },
  {
    // https://github.com/poolsideai/pool
    name: 'poolside',
    title: 'Poolside',
    argv: ['pool', 'acp'],
    install: 'https://github.com/poolsideai/pool',
  },
  {
    // https://github.com/zeroclaw-labs/zeroclaw/blob/master/docs/book/src/channels/acp.md
    name: 'zeroclaw',
    title: 'ZeroClaw',
    argv: ['zeroclaw', 'acp'],
    install: 'https://github.com/zeroclaw-labs/zeroclaw',
  },
];
