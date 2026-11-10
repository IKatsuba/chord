/**
 * Session grants and admission before part 6's safety review (CHD-485,
 * CHD-604b, CHD-605). Grants hold in both modes; edit and write share one
 * real-path grant, and shell grants cover only the exact command.
 */
import type { PermissionOption } from '@agentclientprotocol/sdk/unstable';
import type { RiffMode } from '../models.ts';
import { isInside, shown } from './paths.ts';
import { sensitivePath } from './sensitive_path.ts';

/** What a call reaches, as a grant names it. */
export type Reach =
  | { readonly tool: 'read'; readonly real: string }
  | { readonly tool: 'edit' | 'write'; readonly real: string }
  | { readonly tool: 'shell'; readonly command: string }
  | { readonly tool: 'list' | 'search' };

/** The session's grants: a set of keys, kept while the session lives. */
export type Grants = Set<string>;

/** The key a grant of `reach` is kept under in `directory`'s session. */
export function grantKey(reach: Reach, directory: string): string {
  switch (reach.tool) {
    case 'read':
      return `read:${reach.real}`;
    case 'edit':
    case 'write':
      return `edit:${reach.real}`;
    case 'shell':
      return `shell:${reach.command}`;
    default:
      return `${reach.tool}:${directory}`;
  }
}

/** Whether a call reaching `reach` asks the person first. */
export function asks(
  mode: RiffMode,
  reach: Reach,
  directory: string,
  grants: Grants,
): boolean {
  if (grants.has(grantKey(reach, directory))) {
    return false;
  }

  if (mode === 'ask') {
    return true;
  }

  switch (reach.tool) {
    case 'shell':
      return true;
    case 'edit':
    case 'write':
      return !isInside(directory, reach.real) || sensitivePath(reach.real);
    case 'read':
      return !isInside(directory, reach.real);
    default:
      return false;
  }
}

export const ALLOW = 'allow';
export const ALLOW_SESSION = 'allow_session';
export const DENY = 'deny';

/** The three options of an ask, the second saying what its grant covers. */
export function permissionOptions(
  reach: Reach,
  directory: string,
): PermissionOption[] {
  let grant: string;

  switch (reach.tool) {
    case 'read':
      grant = `Allow reads of ${shown(directory, reach.real)} for this session`;

      break;
    case 'edit':
    case 'write':
      grant = `Allow edits to ${shown(directory, reach.real)} for this session`;

      break;
    case 'shell':
      grant = 'Allow this exact command for this session';

      break;
    default:
      grant = `Allow every ${reach.tool} in this directory for this session`;
  }

  return [
    { optionId: ALLOW, name: 'Allow', kind: 'allow_once' },
    { optionId: ALLOW_SESSION, name: grant, kind: 'allow_always' },
    { optionId: DENY, name: 'Deny', kind: 'reject_once' },
  ];
}
