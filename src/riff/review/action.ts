/** The actual resolved operation, before review and before any effect. */
import { diffLines } from 'diff';
import type { Proposal } from '../tools/mutation.ts';
import type { Reach } from '../tools/permission.ts';
import type { ReviewAction } from './input.ts';

export function reviewAction(
  reach: Reach,
  directory: string,
  proposal?: Proposal,
): ReviewAction | undefined {
  switch (reach.tool) {
    case 'shell':
      return { tool: 'shell', command: reach.command, cwd: directory };
    case 'read':
      return { tool: 'read', real: reach.real };
    case 'mcp':
      return {
        tool: 'mcp',
        server: reach.server,
        name: reach.name,
        arguments: JSON.stringify(reach.input ?? {}),
      };
    case 'edit':
    case 'write': {
      if (proposal === undefined) {
        throw new Error('A file review needs the proposed change.');
      }

      const changes = diffLines(proposal.oldText ?? '', proposal.newText);

      return {
        tool: reach.tool,
        real: proposal.real,
        existed: proposal.oldText !== null,
        additions: changes.reduce(
          (sum, change) => sum + (change.added ? change.count : 0),
          0,
        ),
        deletions: changes.reduce(
          (sum, change) => sum + (change.removed ? change.count : 0),
          0,
        ),
        diff: proposal.patch,
      };
    }
    default:
      return undefined;
  }
}
