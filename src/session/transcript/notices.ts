/**
 * An agent's `notice` (CHD-629): advice the agent sends a client that
 * declared `session.notices`, in place of the reply text it sends otherwise.
 * Each is a line of its own, never merged: notices carry no id.
 */
import type { Notice } from '@agentclientprotocol/sdk/unstable';
import { appended } from './entries.ts';
import type { NoticeSeverity, Transcript } from './types.ts';

const SEVERITIES: readonly string[] = ['info', 'warning', 'error'];

/**
 * `state` with `notice` as its last entry. A severity ACP's schema leaves
 * open draws as `info`; a description omitted, `null` or empty is none.
 */
export function addNotice(
  state: Transcript,
  turnId: string,
  notice: Notice,
): Transcript {
  const severity = (
    SEVERITIES.includes(notice.severity) ? notice.severity : 'info'
  ) as NoticeSeverity;
  const description =
    typeof notice.description === 'string' && notice.description !== ''
      ? notice.description
      : undefined;

  return {
    ...state,
    entries: appended(state.entries, {
      kind: 'notice',
      turnId,
      severity,
      title: notice.title,
      ...(description === undefined ? {} : { description }),
    }),
  };
}
