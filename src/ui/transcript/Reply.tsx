import { useMemo } from 'react';
import type { RGBA } from '@opentui/core';
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import { useColours, useSelectable } from '../app/context.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { DIM_BORDER, FILL, TEXT } from '../theme/text.ts';
import { QUOTE_INSET, type Soft, softMarkdown } from './markdown.ts';

/**
 * A reply as markdown, rendered by markdansi for the width it is drawn in,
 * its paragraphs and list items left whole for OpenTUI to wrap, so a copy
 * joins them; rendered again only when the text or the width changes. It
 * takes the rest of its row, so its texts are measured whole (`FILL`).
 */
export function Reply({ text, width }: { text: string; width: number }) {
  const colours = useColours();
  const blocks = useMemo(
    // An agent's own escapes are text, not styling chord answers for.
    () => softMarkdown(stripAnsi(text), width, undefined, colours),
    [text, width, colours],
  );

  return (
    <box gap={1} flexGrow={1}>
      {blocks.map((block, index) => (
        <SoftBlock key={index} block={block} />
      ))}
    </box>
  );
}

/** What a text of a block is drawn in beside markdansi's own styles. */
export interface Look {
  readonly attributes?: number;
  readonly fg?: RGBA;
}

/**
 * One of `softMarkdown`'s blocks: a text, a quote beside its bar, or a list,
 * each item's marker a text of its own that a drag does not copy, and its
 * blocks hanging beside it.
 */
export function SoftBlock({ block, look }: { block: Soft; look?: Look }) {
  const selectable = useSelectable();

  if (block.kind === 'list') {
    const gap = block.loose ? 1 : 0;

    return (
      <box gap={gap}>
        {block.items.map((item, index) => (
          // The item's blocks one box level under the list, the marker laid
          // over its indent: OpenTUI widens a selection by one box level per
          // drag event, so a drag down to the next item reaches it at once.
          <box
            key={index}
            gap={gap}
            paddingLeft={stringWidth(stripAnsi(item.marker))}
          >
            <text {...TEXT} {...look} position='absolute' left={0} top={0}>
              <Ansi text={item.marker} />
            </text>
            {item.blocks.map((inner, at) => (
              <SoftBlock key={at} block={inner} {...(look && { look })} />
            ))}
          </box>
        ))}
      </box>
    );
  }

  return block.kind === 'quote' ? (
    <box
      flexDirection='row'
      border={['left']}
      borderStyle='single'
      borderColor={DIM_BORDER}
      paddingLeft={QUOTE_INSET - 1}
    >
      <text {...FILL} {...selectable} {...look}>
        <Ansi text={block.text} />
      </text>
    </box>
  ) : (
    <text {...TEXT} {...selectable} {...look}>
      <Ansi text={block.text} />
    </text>
  );
}
