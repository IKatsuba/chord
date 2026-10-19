import { useColours } from '../app/context.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { BOLD, DIM, fg, TEXT } from '../theme/text.ts';
import type { Palette } from '../theme/theme.ts';
import type { AskerPart } from './asker.ts';

/** Said dim after who asks a request that came with no turn running. */
const BETWEEN = ' · between turns';

/**
 * A box's heading that names who asks, `<asker> <says>`, in the permission
 * colour, each of the asker's pieces in its own role; one asked between turns
 * says so after it, dim. It wraps rather than cut, so the name stays whole
 * (CHD-389).
 */
export function AskerHeading({
  asker,
  says,
  between = false,
  grow = false,
}: {
  asker: readonly AskerPart[];
  /** What the asker does: `asks you 2 questions`. */
  says: string;
  between?: boolean;
  /** It takes the row's room left, beside something drawn after it. */
  grow?: boolean;
}) {
  const colours = useColours();

  return (
    <text
      {...TEXT}
      {...(grow ? { flexGrow: 1 } : {})}
      {...fg(colours.permission)}
      attributes={BOLD}
    >
      {asker.map((part, index) => (
        <span key={index} {...partStyle(part, colours)}>
          <Ansi text={part.text} />
        </span>
      ))}
      <Ansi text={`${asker.length > 0 ? ' ' : ''}${says}`} />
      {between && <span attributes={DIM}>{BETWEEN}</span>}
    </text>
  );
}

/**
 * The permission box's row naming who asks, `<asker> asks`: a subagent's
 * way down in the accent colour, an agent's name in its own; one asked
 * between turns says so after it, dim. None when nothing names it. It wraps
 * rather than cut.
 */
export function AskerRow({
  asker,
  between = false,
}: {
  asker: readonly AskerPart[];
  between?: boolean;
}) {
  const colours = useColours();

  if (asker.length === 0) {
    return null;
  }

  const accent = asker[0]!.tone === 'accent';

  return (
    <text {...TEXT} {...(accent ? fg(colours.accent) : {})} flexShrink={0}>
      {asker.map((part, index) => (
        <span key={index} {...partStyle(part, colours)}>
          <Ansi text={part.text} />
        </span>
      ))}
      {' asks'}
      {between && <span attributes={DIM}>{BETWEEN}</span>}
    </text>
  );
}

/** How a piece of the asker is drawn, as the permission box's row draws it. */
function partStyle(part: AskerPart, colours: Palette) {
  const weight = part.bold ? BOLD : 0;

  switch (part.tone) {
    case 'accent':
      return { ...fg(colours.accent), attributes: weight };
    case 'agent':
      return { ...fg(part.colour), attributes: BOLD };
    case 'dim':
      return { attributes: DIM };
    case 'plain':
      return part.bold ? { attributes: BOLD } : {};
  }
}
