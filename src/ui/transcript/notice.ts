/**
 * How an agent's notice reads on screen (CHD-629): its title, and its
 * description under it, wrapped and never cut.
 */
import type { Palette } from '../theme/theme.ts';
import type { NoticeSeverity } from '../../session/transcript/types.ts';

/** The description with each run of blank lines folded to one break. */
export function noticeDescription(description: string): string {
  return description.replace(/\n(?:[ \t]*\n)+/g, '\n').trim();
}

/**
 * The colour of the notice's `⏺`: none for `info`, which draws it dim, and
 * the severity's own role for the others (the owner's Q7 a).
 */
export function noticeMarker(
  severity: NoticeSeverity,
  colours: Pick<Palette, 'warning' | 'error'>,
): string | undefined {
  return severity === 'info' ? undefined : colours[severity];
}
