/**
 * When riff's read, list and search ask the person, and what they offer
 * (CHD-485, "Permission prompts"; CHD-604b, "What each grant covers", "The
 * words"). In ask every call asks; in auto, until the review of part 6, a
 * read outside the session's directory asks and nothing else does. A grant
 * is kept in the session's memory, on a read's real path or the directory
 * for list and search, and holds in both modes.
 */
import type { PermissionOption } from '@agentclientprotocol/sdk/unstable';
import type { RiffMode } from '../models.ts';
import { isInside, shown } from './paths.ts';

/** What a call reaches, as a grant names it. */
export type Reach =
  | { readonly tool: 'read'; readonly real: string }
  | { readonly tool: 'list' | 'search' };

/** The session's grants: a set of keys, kept while the session lives. */
export type Grants = Set<string>;

/** The key a grant of `reach` is kept under in `directory`'s session. */
export function grantKey(reach: Reach, directory: string): string {
  return reach.tool === 'read'
    ? `read:${reach.real}`
    : `${reach.tool}:${directory}`;
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

  return reach.tool === 'read' && !isInside(directory, reach.real);
}

export const ALLOW = 'allow';
export const ALLOW_SESSION = 'allow_session';
export const DENY = 'deny';

/** The three options of an ask, the second saying what its grant covers. */
export function permissionOptions(
  reach: Reach,
  directory: string,
): PermissionOption[] {
  const grant =
    reach.tool === 'read'
      ? `Allow reads of ${shown(directory, reach.real)} for this session`
      : `Allow every ${reach.tool} in this directory for this session`;

  return [
    { optionId: ALLOW, name: 'Allow', kind: 'allow_once' },
    { optionId: ALLOW_SESSION, name: grant, kind: 'allow_always' },
    { optionId: DENY, name: 'Deny', kind: 'reject_once' },
  ];
}
