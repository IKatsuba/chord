import { Fragment, type ReactNode, useMemo } from 'react';
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
    <box flexGrow={1}>
      {spaced(
        blocks.map((block, index) => <SoftBlock key={index} block={block} />),
      )}
    </box>
  );
}

/**
 * `nodes` with a blank row between each two that a drag selects, so a copy
 * across them keeps the blank line the screen shows (Q151). It holds one
 * space: OpenTUI leaves an empty text out of a selection, and a gap is no
 * text at all (Q186, until OpenTUI PR #1403 copies an empty row).
 */
function spaced(nodes: readonly ReactNode[]): ReactNode[] {
  return nodes.map((node, index) => (
    <Fragment key={index}>
      {index > 0 && <Blank />}
      {node}
    </Fragment>
  ));
}

function Blank() {
  return (
    <text {...TEXT} {...useSelectable()}>
      {' '}
    </text>
  );
}

/** What a text of a block is drawn in beside markdansi's own styles. */
export interface Look {
  readonly attributes?: number;
  readonly fg?: RGBA;
}

/**
 * One of `softMarkdown`'s blocks: a text, a quote beside its bar, a code
 * block in a box whose border a drag does not copy, or a list, each item's
 * marker a text of its own that a drag does not copy, and its blocks hanging
 * beside it.
 */
export function SoftBlock({ block, look }: { block: Soft; look?: Look }) {
  const selectable = useSelectable();

  if (block.kind === 'list') {
    // A loose list's blank rows are a copy's too; a tight one has none.
    const rows = (nodes: ReactNode[]) => (block.loose ? spaced(nodes) : nodes);

    return (
      <box>
        {rows(
          block.items.map((item, index) => (
            // The item's blocks one box level under the list, the marker laid
            // over its indent: OpenTUI widens a selection by one box level per
            // drag event, so a drag down to the next item reaches it at once.
            <box key={index} paddingLeft={stringWidth(stripAnsi(item.marker))}>
              <text {...TEXT} {...look} position='absolute' left={0} top={0}>
                <Ansi text={item.marker} />
              </text>
              {rows(
                item.blocks.map((inner, at) => (
                  <SoftBlock key={at} block={inner} {...(look && { look })} />
                )),
              )}
            </box>
          )),
        )}
      </box>
    );
  }

  if (block.kind === 'code') {
    return (
      <box
        border
        borderStyle='single'
        borderColor={DIM_BORDER}
        // OpenTUI sets a title one cell past the corner; chord takes it there.
        {...(block.label !== '' && {
          title: ` ${block.label} `,
          titleAlignment: 'left',
          titleColor: DIM_BORDER,
        })}
        paddingLeft={1}
        paddingRight={1}
        width={block.width}
      >
        <text {...TEXT} {...selectable} {...look} wrapMode='char'>
          <Ansi text={block.code} />
        </text>
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
