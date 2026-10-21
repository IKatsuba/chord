/**
 * The line an ended background item leaves in its owner's transcript:
 * `<marker> <name> · <kind> · <end>`, its end in the view's state words, a
 * failure's reason after a colon (docs/design/CHD-479.md).
 */
import cliTruncate from 'cli-truncate';
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import { timeoutWords } from '../../session/monitors.ts';
import type { Entry } from '../../session/transcript/types.ts';

type ItemEnded = Extract<Entry, { kind: 'item_ended' }>;

/** The line's parts, each in its own colour. */
export interface EndedLine {
  /** Where `⏺` stands. */
  readonly marker: string;
  /** The marker's and the end words' colour. */
  readonly tone: 'success' | 'error' | 'dim';
  readonly name: string;
  /** ` · agent · `, dim. */
  readonly kind: string;
  readonly end: string;
  /** A failure's reason, cut to the width with `…`. */
  readonly reason?: string;
}

/** The line for `entry`, `width` cells past the gutter. */
export function endedLine(entry: ItemEnded, width: number): EndedLine {
  const took =
    entry.startedAt === undefined || entry.endedAt === undefined
      ? undefined
      : timeoutWords(Math.max(0, entry.endedAt - entry.startedAt));
  const after = took === undefined ? '' : ` after ${took}`;
  const kind = ` · ${entry.item} · `;
  const [marker, tone, end] = ((): [string, EndedLine['tone'], string] => {
    switch (entry.end) {
      case 'done':
        return [
          '✓',
          'success',
          `done${took === undefined ? '' : ` in ${took}`}`,
        ];
      case 'failed':
        return ['✗', 'error', `failed${after}`];
      case 'disconnected':
        return ['✗', 'error', `disconnected${after}`];
      case 'stopped':
        return [
          '■',
          'dim',
          `stopped${entry.byPerson === true ? ' with x' : ''}${after}`,
        ];
      case 'ended':
        return [
          '■',
          'dim',
          `${entry.byPerson === true ? 'stopped with x' : 'ended'}${after}`,
        ];
    }
  })();
  const first =
    stripAnsi(entry.error ?? '')
      .split('\n')[0]
      ?.trim() ?? '';

  if (first === '') {
    return { marker, tone, name: entry.name, kind, end };
  }

  const room = width - stringWidth(`${entry.name}${kind}${end}: `);

  return {
    marker,
    tone,
    name: entry.name,
    kind,
    end,
    reason: cliTruncate(first, Math.max(1, room), { position: 'end' }),
  };
}
