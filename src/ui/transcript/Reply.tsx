import {
  Fragment,
  type ReactNode,
  useContext,
  useEffect,
  useMemo,
  useState,
  useSyncExternalStore,
} from 'react';
import { useRenderer } from '@opentui/react';
import { type MouseEvent, type Renderable, RGBA } from '@opentui/core';
import stringWidth from 'string-width';
import stripAnsi from 'strip-ansi';
import {
  CodeBlockActions,
  CodeIds,
  useColours,
  useSelectable,
} from '../app/context.ts';
import { type BlockRef, drawnIds } from './code_pick.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { BOLD, colour, DIM_BORDER, fg, FILL, TEXT } from '../theme/text.ts';
import {
  type Button,
  type Code,
  codeBlocks,
  codePlaces,
  openFences,
  QUOTE_INSET,
  runCommand,
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
  // An agent's own escapes are text, not styling chord answers for.
  const plain = stripAnsi(text);
  const entry = useDrawing();
  const picked = pickedHere(usePicked(), entry);
  const blocks = useMemo(
    () => softMarkdown(plain, width, undefined, colours, picked),
    [plain, width, colours, picked],
  );
  const ids = useCodeBlocks(plain, blocks, entry);

  return (
    <CodeIds.Provider value={ids}>
      <box flexGrow={1}>
        {spaced(
          blocks.map((block, index) => <SoftBlock key={index} block={block} />),
        )}
      </box>
    </CodeIds.Provider>
  );
}

/** Each drawing of a text with code blocks, numbered as it mounts. */
let drawings = 0;

/** Nothing ever picked, where no window picks blocks, as in a test's draw. */
const NO_PICK = () => () => {};

/**
 * The code block picked through `ctrl+x b`: what draws it reads it from the
 * window, and draws again only when it changes (CHD-394).
 */
export function usePicked(): BlockRef | undefined {
  const actions = useContext(CodeBlockActions);

  return useSyncExternalStore(actions?.onPick ?? NO_PICK, () =>
    actions?.picked(),
  );
}

/** This drawing's number, the `entry` of its blocks' `BlockRef`s. */
export function useDrawing(): number {
  const [entry] = useState(() => (drawings += 1));

  return entry;
}

/** The index of the block picked, when it is one of drawing `entry`'s. */
export function pickedHere(
  picked: BlockRef | undefined,
  entry: number,
): number | undefined {
  return picked?.entry === entry ? picked.block : undefined;
}

/**
 * `text`'s code blocks, as `blocks` lays it out, told to the window while
 * they are drawn, for `ctrl+x b` to find (CHD-394): what each copies and
 * puts into the prompt, and where it is, its box or the quote it is in.
 * The ids those are drawn with, for `SoftBlock` to give them.
 */
export function useCodeBlocks(
  text: string,
  blocks: readonly Soft[],
  entry: number,
): ReadonlyMap<Soft, string> {
  const registry = useContext(CodeBlockActions);
  const renderer = useRenderer();
  // A block whose fence is still open is no key's yet (CHD-394 §1).
  const found = useMemo(() => {
    const open = openFences(text);

    return codeBlocks(text).filter((block) => !open.has(block.index));
  }, [text]);
  const { ids, nodes } = useMemo(
    () => drawnIds(blocks, codePlaces(text), entry),
    [blocks, text, entry],
  );

  useEffect(() => {
    if (registry === undefined) {
      return;
    }

    const gone = found.map((block) =>
      registry.add({
        ref: { entry, block: block.index },
        copy: block.text,
        ...(block.runnable ? { run: runCommand(block.text) } : {}),
        node: () => {
          const id = nodes[block.index];

          return id === undefined
            ? undefined
            : (renderer.root.findDescendantById(id) ?? undefined);
        },
      }),
    );

    return () => {
      for (const go of gone) {
        go();
      }
    };
  }, [registry, renderer, found, nodes, entry]);

  return ids;
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
  const id = useContext(CodeIds)?.get(block);
  const named = id === undefined ? {} : { id };
  const picked = usePicked();
  const colours = useColours();
  // The box picked through ctrl+x b: its border, label and buttons in the
  // accent colour (CHD-394 §3).
  const lit =
    picked !== undefined && id === `code-${picked.entry}-${picked.block}`;
  // With no colour, the terminal's own foreground, as a quoted block's.
  const border = lit
    ? (colour(colours.accent) ?? RGBA.defaultForeground())
    : DIM_BORDER;

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
      <box width={block.width} {...named}>
        <box
          border
          borderStyle='single'
          borderColor={border}
          // OpenTUI sets a title one cell past the corner; chord takes it there.
          {...(block.label !== '' && {
            title: ` ${block.label} `,
            titleAlignment: 'left',
            titleColor: border,
          })}
          paddingLeft={1}
          paddingRight={1}
        >
          <text {...TEXT} {...selectable} {...look} wrapMode='char'>
            <Ansi text={block.code} />
          </text>
        </box>
        {block.buttons.length > 0 && <Buttons code={block} lit={lit} />}
      </box>
    );
  }

  return block.kind === 'quote' ? (
    <box
      {...named}
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
    <text {...TEXT} {...selectable} {...look} {...named}>
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
function Buttons({ code, lit }: { code: Code; lit: boolean }) {
  const actions = useContext(CodeBlockActions);
  const colours = useColours();
  // Picked, they are the box's accent, and bold.
  const look = lit ? { ...fg(colours.accent), attributes: BOLD } : {};
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
          {...look}
          onMouseDown={(event: MouseEvent) => {
            if (event.button === 0) {
              actions?.pressed(event.currentTarget);
            }
          }}
          onMouseUp={(event: MouseEvent) => {
            // A click is the first release after a press on this very
            // button, and on it: a drag's end is a selection's, though it
            // ends on a button, and a release OpenTUI hands the pressed
            // button away from it is none of its (CHD-394 §1).
            const took = actions?.released(event.currentTarget) === true;

            if (
              took &&
              event.button === 0 &&
              event.isDragging !== true &&
              event.currentTarget !== null &&
              over(event, event.currentTarget)
            ) {
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
