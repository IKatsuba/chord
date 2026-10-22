import { useMemo } from 'react';
import stripAnsi from 'strip-ansi';
import { useColours, useSelectable } from '../app/context.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { DIM_BORDER, FILL, TEXT } from '../theme/text.ts';
import { markdown, QUOTE_INSET } from './markdown.ts';

/**
 * A reply as markdown, laid out by markdansi to the width it is drawn in;
 * rendered again only when the text or the width changes. It takes the rest
 * of its row, so its texts are measured whole (`FILL`).
 */
export function Reply({ text, width }: { text: string; width: number }) {
  const colours = useColours();
  const blocks = useMemo(
    // An agent's own escapes are text, not styling chord answers for.
    () => markdown(stripAnsi(text), width, undefined, colours),
    [text, width, colours],
  );
  const selectable = useSelectable();

  return (
    <box gap={1} flexGrow={1}>
      {blocks.map((block, index) =>
        block.quote ? (
          <box
            key={index}
            flexDirection='row'
            border={['left']}
            borderStyle='single'
            borderColor={DIM_BORDER}
            paddingLeft={QUOTE_INSET - 1}
          >
            <text {...FILL} {...selectable}>
              <Ansi text={block.text} />
            </text>
          </box>
        ) : (
          <text key={index} {...TEXT} {...selectable}>
            <Ansi text={block.text} />
          </text>
        ),
      )}
    </box>
  );
}
