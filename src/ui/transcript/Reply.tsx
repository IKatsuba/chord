import { Fragment, type ReactNode, useContext, useMemo, useRef } from 'react';
import type { MouseEvent, Renderable, RGBA } from '@opentui/core';
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import { CodeBlockActions, useColours, useSelectable } from '../app/context.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { DIM_BORDER, FILL, TEXT } from '../theme/text.ts';
import {
  type Button,
  type Code,
  QUOTE_INSET,
  type Soft,
  softMarkdown,
} from './markdown.ts';

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
 * text at all (Q186, until OpenTUI PR #1403 copies an empty row). The row
 * before the node at `index` starts `inset(index)` cells in, at its text.
 */
function spaced(
  nodes: readonly ReactNode[],
  inset: (index: number) => number = () => 0,
): ReactNode[] {
  return nodes.map((node, index) => (
    <Fragment key={index}>
      {index > 0 && <Blank inset={inset(index)} />}
      {node}
    </Fragment>
  ));
}

function Blank({ inset }: { inset: number }) {
  return (
    <text {...TEXT} {...useSelectable()} marginLeft={inset}>
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
    const rows = (nodes: ReactNode[], inset?: (index: number) => number) =>
      block.loose ? spaced(nodes, inset) : nodes;
    const indent = (index: number) =>
      stringWidth(stripAnsi(block.items[index]?.marker ?? ''));

    return (
      <box>
        {rows(
          block.items.map((item, index) => (
            // The item's blocks one box level under the list, the marker laid
            // over its indent: OpenTUI widens a selection by one box level per
            // drag event, so a drag down to the next item reaches it at once.
            <box key={index} paddingLeft={indent(index)}>
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
          // Between two items, at the text of the item below it.
          indent,
        )}
      </box>
    );
  }

  if (block.kind === 'code') {
    return (
      <box width={block.width}>
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
        >
          <text {...TEXT} {...selectable} {...look} wrapMode='char'>
            <Ansi text={block.code} />
          </text>
        </box>
        {block.buttons.length > 0 && <Buttons code={block} />}
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

/**
 * A code box's buttons over the right end of its top border, each a text of
 * its own, the owner's choice where OpenTUI's box has one title
 * (docs/decisions.md, CHD-394): the border's `─` between them and after
 * the last, then its corner, as OpenTUI draws a blank over a border with
 * the border through it. They are in the text's own colour, which reads as
 * something to press on the dim border, and no drag starts on them. A press
 * and a release on the same one is a click on it; the wheel is never one.
 */
function Buttons({ code }: { code: Code }) {
  const actions = useContext(CodeBlockActions);
  // The button the left button went down on, until it comes up.
  const pressed = useRef<Button | undefined>(undefined);
  const act = (button: Button) =>
    button === 'copy'
      ? actions?.copy(code.copy)
      : code.run !== undefined && actions?.prompt(code.run);

  return (
    <box position='absolute' top={0} right={2} flexDirection='row' gap={1}>
      {code.buttons.map((button) => (
        <text
          key={button}
          {...TEXT}
          onMouseDown={(event: MouseEvent) => {
            pressed.current = event.button === 0 ? button : undefined;
          }}
          onMouseUp={(event: MouseEvent) => {
            // A drag's end is a selection's, though it ends on a button,
            // and a release OpenTUI hands the pressed button away from it
            // is none of its (CHD-394 §1).
            const clicked =
              pressed.current === button &&
              event.button === 0 &&
              event.isDragging !== true &&
              event.currentTarget !== null &&
              over(event, event.currentTarget);

            pressed.current = undefined;

            if (clicked) {
              act(button);
            }
          }}
        >
          {`[${button}]`}
        </text>
      ))}
    </box>
  );
}

/** Whether `event` came at a cell of `at`, as it is drawn now. */
function over(event: MouseEvent, at: Renderable): boolean {
  return (
    event.x >= at.screenX &&
    event.x < at.screenX + at.width &&
    event.y >= at.screenY &&
    event.y < at.screenY + at.height
  );
}
