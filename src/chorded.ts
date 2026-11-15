/**
 * chord's own npx agents, the packages of this repository, in the
 * registry's shape (CHD-622). Each version is a literal, and the pin may
 * lead; the package is published before chord's next release, and chord's
 * release preflight asks npm for each.
 */
import type { RegistryAgent } from './registry.ts';

/** One of chord's own agents: a registry entry, and whether it takes MCP servers. */
export interface ChordedAgent extends RegistryAgent {
  /**
   * A cloud VM reaches neither chord's MCP server nor the person's local
   * ones, so chord says it holds them back rather than the agent dropping
   * them.
   */
  readonly mcpServers: false;
}

export const CHORDED_AGENTS: readonly ChordedAgent[] = [
  {
    id: 'cursor-cloud',
    name: 'Cursor Cloud Agents',
    runner: 'npx',
    package: '@chorded/cursor-cloud-acp',
    version: '0.2.0',
    args: [],
    env: {},
    repository:
      'https://github.com/IKatsuba/chord/tree/main/packages/cursor-cloud-acp',
    mcpServers: false,
  },
];
