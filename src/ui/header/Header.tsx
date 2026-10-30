import { TextAttributes } from '@opentui/core';
import { useSelectable } from '../app/context.ts';
import { CUT, DIM } from '../theme/text.ts';
import {
  type HeaderFacts,
  headerLines,
  MARK_GAP,
  textWidth,
} from './header.ts';
import { Mark } from './Mark.tsx';

/**
 * The startup header, the first thing in a session's transcript: Chorded's
 * mark and the session's lines beside it.
 */
export function Header({
  facts,
  columns,
}: {
  facts: HeaderFacts;
  /** The window's width, which the lines are cut to. */
  columns: number;
}) {
  const lines = headerLines(facts, textWidth(columns), Date.now());
  const selectable = useSelectable();

  return (
    <box flexDirection='row' flexShrink={0}>
      <box flexShrink={0} marginRight={MARK_GAP}>
        <Mark />
      </box>
      <box flexShrink={1}>
        {lines.map((line, index) => (
          <text key={index} {...CUT} {...selectable}>
            {line.map((part, at) => (
              <span key={at} attributes={part.bold ? TextAttributes.BOLD : DIM}>
                {part.text}
              </span>
            ))}
          </text>
        ))}
      </box>
    </box>
  );
}
