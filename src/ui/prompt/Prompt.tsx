import { RGBA, TextAttributes } from '@opentui/core';
import { useContext, useLayoutEffect, useMemo, useRef, useState } from 'react';
import stringWidth from 'string-width';
import { bound, type Sequence, sequenceHint } from '../shortcuts/bindings.ts';
import { PANEL_PADDING } from '../shortcuts/keys.ts';
import type { CommandMenu, FileFinder } from './state.ts';
import { Keys, paint, useColours } from '../app/context.ts';
import { usePasted, usePress } from '../app/input.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { colour, CUT, DIM, DIM_BORDER, fg, TEXT } from '../theme/text.ts';
import type { Press } from '../shortcuts/state.ts';
import { Gutter } from '../transcript/tools/Tool.tsx';
import { itemLabel, visibleRange } from './commands.ts';
import {
  type Cursor,
  gutterMark,
  type Row,
  shownRows,
  textareaDoes,
  textareaKeys,
  textareaTakes,
  pressHint,
  UNDOES,
} from './prompt.ts';
import { type Queued, queueRows } from './queue.ts';
import { foundPieces, type Search, searchLabel } from './search.ts';
import {
  TextArea,
  type TextAreaKey,
  type TextareaRenderable,
} from './TextArea.tsx';

// The textarea's column counts the cells it lays its line out in: a wide
// character two, a tab to its stop, a control character's notation. chord's
// `Cursor` counts the line's string, so each crossing goes through the
// buffer's own measure.

/** `cursor`, a string index into its line, as the textarea's row and column. */
function boxCursor(
  textarea: TextareaRenderable,
  [line, column]: Cursor,
): [number, number] {
  const text = textarea.plainText.split('\n')[line] ?? '';

  return [line, textarea.editBuffer.measureText(text.slice(0, column))];
}

/** The textarea's cursor as chord's, its column a string index. */
function draftCursor(textarea: TextareaRenderable): Cursor {
  const { row, col } = textarea.logicalCursor;

  return [row, textarea.getTextRangeByCoords(row, 0, row, col).length];
}

/**
 * The prompt box, on OpenTUI's textarea, which grows with its rows, up to
 * `rows` here, and scrolls after, its gutter marking what is scrolled out.
 * Enter sends and shift+Enter breaks the line; ↑ on the first row and ↓ on
 * the last walk history, and while `walking` every ↑ and ↓ is history's.
 * The textarea hears only its own keys (`textareaTakes`); the key test
 * drives this component to hold that against the shortcuts panel.
 */
export function PromptInput({
  value,
  cursor,
  rows,
  walking,
  bash = false,
  highlight,
  normal = false,
  chords = [],
  focus,
  onChange,
  onCursorChange,
  onSubmit,
  onOlder,
  onNewer,
  onPaste,
  wordCut,
  agent,
  width,
  onPressed,
}: {
  value: string;
  cursor: Cursor;
  rows: number;
  walking: boolean;
  /** Bash mode: the border and the `›` turn to the bash colour's `!`. */
  bash?: boolean;
  /**
   * What a history search found in the text, marked inverse wherever it is.
   * The box's rows are drawn over the textarea meanwhile, as its highlight
   * takes no inverse and counts its range in units of its own (CHD-306).
   */
  highlight?: string;
  /**
   * Vim's normal mode, in which the textarea takes no keys and no pastes but
   * keeps the terminal's block cursor, on the character vim's cursor is on.
   * `focus` is false meanwhile, as the keys are the window's.
   */
  normal?: boolean;
  /** The chords that would run now, whose first keys the textarea leaves. */
  chords?: readonly Sequence[];
  focus: boolean;
  onChange: (value: string) => void;
  onCursorChange: (cursor: Cursor) => void;
  onSubmit: (value: string) => void;
  onOlder: () => void;
  onNewer: () => void;
  /** Each bracketed paste, the empty one included, while the box has the keys. */
  onPaste?: (text: string) => void;
  /**
   * How much of the cursor's line before it ctrl+w takes whole, ahead of the
   * textarea's own word cut; 0 leaves the key to that.
   */
  wordCut?: (before: string) => number;
  /**
   * The child the prompt goes to, with its colour, which the border takes
   * and whose name it carries on top; none while `main` is picked, and the
   * box is as it always was.
   */
  agent?: {
    readonly name: string;
    readonly colour: string | undefined;
    /** A member's run, by its lead's name, dim after its own. */
    readonly team?: string;
  };
  /** The box's width, which a named top border is laid out to. */
  width?: number;
  /**
   * A mouse press on the box, which OpenTUI follows by giving the textarea
   * the keys: the window takes them back from wherever else they were.
   */
  onPressed?: () => void;
}) {
  const colours = useColours();
  const area = useRef<TextareaRenderable | null>(null);
  // The rows the textarea shows now, which the gutter marks.
  const [shown, setShown] = useState<readonly Row[]>(() =>
    shownRows([], [], 0, 1),
  );
  const shownKey = useRef('');
  // How many of the text's rows are scrolled out above, which the rows drawn
  // over the textarea during a search are scrolled by too.
  const [top, setTop] = useState(0);
  // What the textarea last said, so a draft handed back is not set again.
  const said = useRef(value);
  // Only the person moves the cursor, and only in a box with the keys; what an
  // unfocused one reports is the window's own `setCursor`, as when ctrl+r
  // shows a match, which comes back after the call, from the native buffer.
  const focused = useRef(focus);

  focused.current = focus;

  // The textarea's own keys that a binding moved elsewhere are turned off,
  // and ↑ and ↓ walk history only while they are history's keys.
  const keymap = useContext(Keys);
  const upWalks =
    textareaDoes(UP, 'history:previous') &&
    bound(keymap, 'history:previous', UP);
  const downWalks =
    textareaDoes(DOWN, 'history:next') && bound(keymap, 'history:next', DOWN);
  const starts = chords.map(sequenceHint).join('\n');
  // `starts` stands for `chords`, a new array each draw.
  const off = useMemo(() => textareaKeys(keymap, chords), [keymap, starts]);

  // The cursor the window asks for, once the textarea is up; a draft that is
  // not the one the textarea last said came from elsewhere: history, a send,
  // the editor.
  useLayoutEffect(() => {
    const textarea = area.current;

    if (textarea === null) {
      return;
    }

    if (value !== said.current || textarea.plainText !== value) {
      said.current = value;

      textarea.setText(value);
    }

    textarea.setCursor(...boxCursor(textarea, cursor));
  }, [value]);

  // Normal mode's cursor is the window's alone, moved by vim's keys.
  useLayoutEffect(() => {
    const textarea = area.current;

    if (normal && textarea !== null) {
      textarea.setCursor(...boxCursor(textarea, cursor));
    }
  }, [normal, cursor[0], cursor[1]]);

  // Where the textarea is scrolled to it says only when asked, and it scrolls
  // as it is laid out as well as on a key, with no event either way: its
  // resize calls no `onSizeChange`, and its draw no `renderAfter`. So it is
  // read each time the box round it has drawn, its layout done; the marks
  // follow a frame on.
  const measure = () => {
    const textarea = area.current;

    if (textarea === null) {
      return;
    }

    const { lineSources, lineWraps } = textarea.lineInfo;
    const rows = shownRows(
      lineSources,
      lineWraps,
      textarea.scrollY,
      Math.max(1, textarea.height),
    );

    const key = JSON.stringify([textarea.scrollY, rows]);

    // Every frame draws the box, and a state set, even to the same rows,
    // would draw another.
    if (key !== shownKey.current) {
      shownKey.current = key;

      setShown(rows);
      setTop(textarea.scrollY);
    }
  };

  const tellCursor = () => {
    const textarea = area.current;

    if (textarea !== null && focused.current) {
      onCursorChange(draftCursor(textarea));
    }
  };

  // The window's draft and cursor as last drawn, which the box holds to: a
  // change the window did not take, a key of its own that typed, is undone
  // once it has drawn, as a controlled input's is.
  const held = useRef({ value, cursor });

  held.current = { value, cursor };

  const holdToDraft = () => {
    const textarea = area.current;
    const { value: draft, cursor: at } = held.current;

    if (textarea !== null && textarea.plainText !== draft) {
      said.current = draft;

      textarea.setText(draft);
      textarea.setCursor(...boxCursor(textarea, at));
    }
  };

  // The cursor is told again after a change, as the textarea may report it
  // before the text it moved past is in.
  const report = () => {
    const text = area.current?.plainText ?? '';

    if (text !== said.current) {
      said.current = text;

      onChange(text);
      tellCursor();
      queueMicrotask(holdToDraft);
    }

    return text;
  };

  // Cut in the textarea, not set into it from the draft, so its own undo
  // brings the cut back: `setText` would clear its history.
  const cutWhole = () => {
    const textarea = area.current;

    if (textarea === null || wordCut === undefined) {
      return false;
    }

    const { row, col } = textarea.logicalCursor;
    const before = textarea.getTextRangeByCoords(row, 0, row, col);
    const length = wordCut(before);

    if (length === 0) {
      return false;
    }

    textarea.deleteRange(
      row,
      textarea.editBuffer.measureText(before.slice(0, before.length - length)),
      row,
      col,
    );

    return true;
  };

  // A key the textarea takes may move its cursor, which its own event says
  // only once something else reaches the native buffer, and its undo and redo
  // change the text without a word: both are read once the textarea has
  // acted on the key.
  const claimed = (input: string, key: Press) => {
    if (!textareaTakes(input, key, off)) {
      return true;
    }

    const hint = pressHint(input, key);

    if (hint === 'ctrl+w' && cutWhole()) {
      return true;
    }

    queueMicrotask(() => {
      if (hint !== undefined && UNDOES.has(hint)) {
        report();
      }

      tellCursor();
    });

    return false;
  };

  usePress(
    (input, key) => {
      const textarea = area.current;

      if (textarea === null || key.shift) {
        return claimed(input, key);
      }

      // The cursor's row among all the text's rows as the textarea wraps it.
      const row = textarea.scrollY + textarea.visualCursor.visualRow;
      const first = row === 0;
      const end = row === textarea.editorView.getTotalVirtualLineCount() - 1;

      if (key.upArrow && (walking || first)) {
        if (upWalks) {
          onOlder();
        }

        return true;
      }

      if (key.downArrow && (walking || end)) {
        if (downWalks) {
          onNewer();
        }

        return true;
      }

      return claimed(input, key);
    },
    { isActive: focus },
  );

  usePasted((text) => onPaste?.(text), { isActive: focus });

  // In normal mode the textarea is focused for its cursor alone: every key
  // and paste is the window's, the empty paste of an image among them.
  usePress(() => true, { isActive: normal && !focus });
  usePasted(
    (text) => {
      onPaste?.(text);

      return true;
    },
    { isActive: normal && !focus },
  );

  // Bash mode's colour says what Enter does, so it outranks the agent's.
  const border: Edge =
    bash && colours.bash !== undefined
      ? { colour: colours.bash }
      : agent?.colour !== undefined
        ? { colour: agent.colour }
        : { dim: !bash };
  const box = (
    <box
      flexDirection='row'
      {...(onPressed && { onMouseDown: onPressed })}
      // With a name on top, the top is `NamedTop`'s row.
      border={agent === undefined ? true : ['bottom', 'left', 'right']}
      borderStyle='rounded'
      borderColor={
        border.colour !== undefined
          ? colour(border.colour)
          : border.dim === true
            ? DIM_BORDER
            : RGBA.defaultForeground()
      }
      paddingX={1}
      marginTop={agent === undefined ? 1 : 0}
      flexShrink={0}
    >
      <box flexShrink={0}>
        {shown.map((row) => {
          const mark = gutterMark(row, shown);

          return bash && mark === '›' ? (
            <Gutter key={`${row.line}:${row.piece}`} {...paint(colours.bash)}>
              !
            </Gutter>
          ) : (
            <Gutter key={`${row.line}:${row.piece}`} dimColor={mark !== '›'}>
              {mark}
            </Gutter>
          );
        })}
      </box>
      <box flexGrow={1} maxHeight={rows} renderAfter={measure}>
        <TextArea
          ref={area}
          initialValue={value}
          focused={focus || normal}
          flexGrow={1}
          wrapMode='char'
          cursorStyle={STEADY}
          keyBindings={PROMPT_KEYS}
          opacity={highlight === undefined ? 1 : 0}
          onContentChange={report}
          onCursorChange={tellCursor}
          // Said first, so the send that clears it is a change.
          onSubmit={() => onSubmit(report())}
        />
        {highlight !== undefined && (
          <box
            flexDirection='row'
            position='absolute'
            top={0}
            left={0}
            width='100%'
            height='100%'
            overflow='hidden'
          >
            <box
              flexDirection='row'
              marginTop={-top}
              flexShrink={0}
              width='100%'
            >
              {/* Broken at the cell as the textarea breaks its rows, so the
              text stands row for row where the textarea put it. */}
              <text {...TEXT} flexGrow={1} wrapMode='char'>
                {foundPieces(value, highlight).map((piece, index) => (
                  <span
                    key={index}
                    attributes={piece.found ? TextAttributes.INVERSE : 0}
                  >
                    {piece.text}
                  </span>
                ))}
              </text>
            </box>
          </box>
        )}
      </box>
    </box>
  );

  if (agent === undefined) {
    return box;
  }

  return (
    <box marginTop={1} flexShrink={0}>
      <NamedTop
        name={agent.name}
        {...(agent.team === undefined ? {} : { team: agent.team })}
        width={width ?? stringWidth(agent.name) + 8}
        edge={border}
      />
      {box}
    </box>
  );
}

/**
 * The textarea's keys beyond OpenTUI's defaults, as react-ink-textarea had
 * them: Enter sends, shift+, ctrl+ and alt+Enter and ctrl+J break the line,
 * ctrl+Z and ctrl+Y undo and redo.
 */
const PROMPT_KEYS: TextAreaKey[] = [
  { name: 'return', action: 'submit' },
  { name: 'kpenter', action: 'submit' },
  { name: 'return', shift: true, action: 'newline' },
  { name: 'return', ctrl: true, action: 'newline' },
  { name: 'return', meta: true, action: 'newline' },
  { name: 'linefeed', action: 'newline' },
  { name: 'j', ctrl: true, action: 'newline' },
  { name: 'z', ctrl: true, action: 'undo' },
  { name: 'y', ctrl: true, action: 'redo' },
];

/** A steady block; a blink redraws the window twice a second for nothing. */
const STEADY = { style: 'block', blinking: false } as const;

/** The prompt box's border: a palette colour, or dim, or neither. */
interface Edge {
  readonly colour?: string;
  readonly dim?: boolean;
}

/**
 * The box's top border with the agent's name on it, `╭─ parser ───╮`, drawn
 * as a row over a box that has none: OpenTUI's border title takes no colour
 * of its own. A member's run follows dim, `╭─ tester · bugfix ───╮`, as two
 * runs may each have a `tester`.
 */
function NamedTop({
  name,
  team,
  width,
  edge: { colour: tone, dim = false },
}: {
  name: string;
  team?: string;
  width: number;
  edge: Edge;
}) {
  const after = team === undefined ? '' : ` · ${team}`;
  const fill = Math.max(1, width - stringWidth(name + after) - 5);
  const edge = { ...fg(tone), attributes: dim ? DIM : 0 };

  return (
    <text {...CUT}>
      <span {...edge}>╭─</span>
      <span {...fg(tone)} attributes={TextAttributes.BOLD}>
        {` ${name}`}
      </span>
      {team !== undefined && <span attributes={DIM}>{after}</span>}
      <span {...edge}>{` ${'─'.repeat(fill)}╮`}</span>
    </text>
  );
}

/**
 * ctrl+r's line, in the status line's row: what is searched for, with a
 * cursor after it, since the box above is not taking typing.
 */
export function SearchLine({ search }: { search: Search }) {
  return (
    <box flexDirection='row' paddingX={2} height={1} flexShrink={0}>
      <text {...CUT}>
        <span attributes={DIM}>{searchLabel(search)}</span>
        {` ${search.query}`}
        <span attributes={TextAttributes.INVERSE}>{BLOCK}</span>
      </text>
    </box>
  );
}

/** The search line's cursor: an inverse cell, as the textarea draws its own. */
export const BLOCK = ' ';

/** ↑ and ↓ as bindings name them. */
const UP: Sequence = [
  { key: 'up', ctrl: false, alt: false, shift: false, cmd: false },
];
const DOWN: Sequence = [{ ...UP[0]!, key: 'down' }];

/**
 * The prompts waiting behind the turn, under the working line and its plan:
 * each as the transcript will show it once sent, but dim, as it is not sent
 * yet.
 */
export function Queue({
  queue,
  limit,
}: {
  queue: readonly Queued[];
  limit: number;
}) {
  return (
    <box paddingX={1} flexShrink={0}>
      {queueRows(queue, limit).map((row, index) => (
        // A header wider than the window is cut at its end, as any row is.
        <box key={index} flexDirection='row' overflow='hidden'>
          <Gutter dimColor>{row.kind === 'message' ? '←' : '›'}</Gutter>
          {row.kind !== 'more' && row.header !== undefined && (
            // Whole, so the cut lands in the text after it: a long name
            // would otherwise take why the message waits with it.
            <text {...TEXT} wrapMode='none' flexShrink={0} attributes={DIM}>
              <Ansi text={row.header} />
            </text>
          )}
          <text {...CUT} flexShrink={1} attributes={DIM}>
            {row.kind === 'more' ? (
              `… +${row.count} more`
            ) : (
              <Ansi text={row.text} />
            )}
          </text>
        </box>
      ))}
    </box>
  );
}

/**
 * The slash command list under the prompt, in place of the status line, as
 * Claude Code draws it: each command's name, then what it does, dim; the
 * highlighted one in the permission colour. A list longer than `rows` shows
 * the part around the highlight.
 */
export function CommandList({
  menu,
  rows,
  width,
}: {
  menu: CommandMenu;
  rows: number;
  width: number;
}) {
  const { items, highlighted } = menu;
  const { permission } = useColours();
  const { start, end } = visibleRange(
    items.length,
    highlighted,
    rows,
    menu.top,
  );
  // One name column for the whole list, so it holds still as the list scrolls,
  // and never more than a third of the line.
  const nameWidth = Math.min(
    Math.max(...items.map((item) => stringWidth(itemLabel(item)))) + 2,
    Math.floor((width - 2 * PANEL_PADDING) / 3),
  );

  return (
    <box paddingX={PANEL_PADDING} flexShrink={0}>
      {items.slice(start, end).map((item, index) => {
        const lit = start + index === highlighted;
        const tone = lit ? fg(permission) : { attributes: DIM };

        return (
          <box key={item.name} flexDirection='row'>
            <box width={nameWidth} flexShrink={0}>
              <text {...CUT} {...tone}>
                <Ansi text={itemLabel(item)} />
              </text>
            </box>
            <text {...CUT} {...tone}>
              <Ansi text={item.description ?? ''} />
            </text>
          </box>
        );
      })}
    </box>
  );
}

/**
 * The `@` file finder under the prompt, where the status line was, drawn as
 * the slash command list is: one path a row, the highlighted one in colour.
 */
export function FileList({
  finder,
  rows,
}: {
  finder: FileFinder;
  rows: number;
}) {
  const { files, highlighted, searching } = finder;
  const { permission } = useColours();
  // A match running long says so in the list's last row, not one more, and
  // the list scrolls a row so the highlighted file stays above it.
  const { start, end } = visibleRange(
    files.length,
    highlighted,
    searching ? Math.max(Math.min(files.length, rows) - 1, 1) : rows,
    finder.top,
  );
  const shown = files.slice(start, end);

  return (
    <box paddingX={PANEL_PADDING} flexShrink={0}>
      {shown.map((path, index) => (
        <text
          key={path}
          {...CUT}
          {...(start + index === highlighted
            ? fg(permission)
            : { attributes: DIM })}
        >
          {path}
        </text>
      ))}
      {searching && (
        <text {...CUT} attributes={DIM}>
          searching…
        </text>
      )}
    </box>
  );
}
