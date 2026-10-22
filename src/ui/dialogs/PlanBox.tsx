import { type BoxRenderable, TextAttributes } from '@opentui/core';
import { useTerminalDimensions } from '@opentui/react';
import cliTruncate from 'cli-truncate';
import wrapAnsi from 'wrap-ansi';
import {
  type RefObject,
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import type { PlanAnswer, PlanWait } from '../../session/transcript/types.ts';
import { paint, useColours, useHintKey } from '../app/context.ts';
import { BLOCK } from '../prompt/Prompt.tsx';
import type { ScrollStep } from '../transcript/scroll.ts';
import { usePasted, usePress } from '../app/input.ts';
import { borderOf } from '../pickers/Pickers.tsx';
import { BOLD, CUT, DIM, fg, TEXT } from '../theme/text.ts';
import { Gutter } from '../transcript/tools/Tool.tsx';
import type { RequestScroller } from './Permission.tsx';
import {
  countRoom,
  hiddenRows,
  requestCount,
  requestRule,
  requestStep,
  requestView,
} from './permission.ts';
import {
  noteLines,
  OPEN_PLAN_BOX,
  planChoices,
  planHint,
  planKey,
  planPaste,
  planQuestion,
} from './plan.ts';

/**
 * The box an agent's plan is put to the person in, above the prompt in the
 * permission box's place and look (docs/design/CHD-437.md): `Approve Plan`,
 * the agent's choices numbered, the question box's Note row sent with keep
 * planning, and the hint. The plan itself is in the transcript, under its
 * call. It takes the keys itself while `active`.
 */
export function PlanBox({
  wait,
  agent,
  width,
  active,
  hidden = false,
  scroller,
  onOverflow,
  onAnswer,
}: {
  wait: PlanWait;
  /** The agent as the agents list names it. */
  agent: string;
  /** The window's width; the box takes all of it. */
  width: number;
  active: boolean;
  /** Not drawn, its state kept, while the background view stands in its place. */
  hidden?: boolean;
  /** Where the window finds how to page the Note, while it overflows. */
  scroller?: RefObject<RequestScroller | undefined>;
  /**
   * Whether the page keys are the Note's: the `❯` on it, and it taller than
   * its room (docs/design/CHD-437.md).
   */
  onOverflow?: (overflows: boolean) => void;
  onAnswer: (answer: PlanAnswer) => void;
}) {
  const colours = useColours();
  const [state, setState] = useState(OPEN_PLAN_BOX);
  // Keys that land in one tick each see the one before.
  const latest = useRef(state);
  const choices = planChoices(wait.agent);
  const noteRow = choices.length;
  const { height: windowRows } = useTerminalDimensions();
  // The Note's room, as laid out, and where its view starts; following the
  // cursor, its tail, until the page keys move it (CHD-246).
  const area = useRef<BoxRenderable | null>(null);
  const [room, setRoom] = useState(Number.POSITIVE_INFINITY);
  const [top, setTop] = useState(Number.POSITIVE_INFINITY);
  // The `❯`, `Note  ` and the box's border and padding take twelve cells.
  const noteWidth = Math.max(width - 12, 1);
  const whole = noteLines(state.note, noteWidth);
  // A room of one row has none for a rule: what is hidden is said beside
  // the row, which wraps to the cells the count leaves (CHD-464).
  const counted = room <= 1 && whole.length > 1;
  const lines = counted
    ? noteLines(state.note, noteWidth - countRoom(whole.length) - 1)
    : whole;
  const total = lines.length;
  const onNote = state.row === noteRow;
  const overflows = total > room;
  const shown = requestView(total, room, top);
  const out = hiddenRows(total, shown.top, shown.shown);
  const pageUp = useHintKey('scroll:pageUp');
  const pageDown = useHintKey('scroll:pageDown');
  const set = (next: typeof state) => {
    // Typing brings the view back to the cursor.
    if (next.note !== latest.current.note) {
      setTop(Number.POSITIVE_INFINITY);
    }

    latest.current = next;

    setState(next);
  };

  const scroll = useCallback(
    (step: ScrollStep) =>
      setTop((at) => requestStep(step, total, room, Math.min(at, total))),
    [total, room],
  );

  // The room as laid out, after each draw too: a window that shrinks the box
  // leaves the area no size change to hear when its height was already at
  // its floor, and a stale room draws past the box (CHD-437).
  useLayoutEffect(() => {
    const height = area.current?.getLayout().height;

    if (height !== undefined && height !== room) {
      setRoom(height);
    }
  });

  useEffect(() => {
    onOverflow?.(onNote && overflows);
  }, [onOverflow, onNote, overflows]);

  useEffect(() => {
    if (scroller === undefined || !active) {
      return;
    }

    scroller.current = scroll;

    return () => {
      scroller.current = undefined;
    };
  }, [scroller, scroll, active]);

  usePasted(
    (text) => {
      set(planPaste(wait.agent, latest.current, text));

      return true;
    },
    { isActive: active },
  );

  usePress(
    (input, key) => {
      const step = planKey(wait.agent, latest.current, input, key);

      set(step.state);

      if (step.answer !== undefined) {
        onAnswer(step.answer);
      }
    },
    { isActive: active },
  );

  const marker = (row: number) => (
    <Gutter {...paint(colours.permission)}>
      {row === state.row ? '❯' : ' '}
    </Gutter>
  );

  // What never gives way: the border, title, question, choices, one line
  // of the Note, the gaps and the hint, as they wrap; the Note gives up the
  // rest of its lines to a short window (CHD-246, CHD-464).
  const inside = Math.max(width - 4, 1);
  const rowsOf = (text: string) =>
    wrapAnsi(text, inside, { hard: true }).split('\n').length;
  const question = planQuestion(agent, wait);
  const hint = planHint(wait.agent, state);
  const pinned =
    2 + 1 + 1 + rowsOf(question) + choices.length + 1 + 1 + 1 + rowsOf(hint);

  return (
    <box
      {...borderOf(colours.permission)}
      paddingX={1}
      flexShrink={1}
      minHeight={pinned}
      visible={!hidden}
    >
      <text
        {...TEXT}
        {...fg(colours.permission)}
        attributes={BOLD}
        flexShrink={0}
      >
        Approve Plan
      </text>
      <text {...TEXT} flexShrink={0}>
        {' '}
      </text>
      <text {...TEXT} flexShrink={0}>
        {question}
      </text>
      {choices.map((choice, index) => (
        <box key={index} flexDirection='row' flexShrink={0}>
          {marker(index)}
          <text
            {...CUT}
            {...(index === state.row ? fg(colours.permission) : {})}
          >
            {`${index + 1}. ${choice.label}`}
          </text>
        </box>
      ))}
      <text {...TEXT} flexShrink={0}>
        {' '}
      </text>
      {/* The Note: its lines up to half the window, as the permission
          box's request, giving way to the rest, at least one; wrapped under
          its own text, never cut, as a form's value is, the lines round the
          cursor shown under CHD-246's rules (docs/design/CHD-437.md). */}
      <box
        flexBasis={Math.min(total, Math.max(Math.floor(windowRows / 2), 1))}
        flexShrink={1}
        // Not 1: Yoga leaves an item at its basis rather than shrink it to
        // exactly its minimum, as the permission box's request finds; the
        // box's own floor keeps a line for it.
        minHeight={0}
        overflow='hidden'
        ref={area}
        onSizeChange={() => setRoom(area.current?.getLayout().height ?? total)}
      >
        {[
          ...(shown.above
            ? [
                <text key='above' {...CUT} attributes={DIM}>
                  {requestRule(
                    '↑',
                    out.above,
                    onNote ? pageUp : undefined,
                    noteWidth,
                  )}
                </text>,
              ]
            : []),
          ...(state.note === ''
            ? [
                <text key='empty' {...CUT}>
                  {onNote && active && (
                    <span attributes={TextAttributes.INVERSE}>{BLOCK}</span>
                  )}
                  <span attributes={DIM}>
                    {`${onNote && active ? ' ' : ''}${cliTruncate(
                      `Tell ${agent} what to change, sent with 2 (optional)`,
                      Math.max(noteWidth - 1, 1),
                    )}`}
                  </span>
                </text>,
              ]
            : lines
                .slice(shown.top, shown.top + shown.shown)
                .map((line, index) => (
                  <box key={shown.top + index} flexDirection='row' flexGrow={1}>
                    <text {...CUT} flexGrow={1}>
                      {line}
                      {onNote && active && shown.top + index === total - 1 && (
                        <span attributes={TextAttributes.INVERSE}>{BLOCK}</span>
                      )}
                    </text>
                    {counted && (
                      <text {...CUT} attributes={DIM} flexShrink={0}>
                        {requestCount(out)}
                      </text>
                    )}
                  </box>
                ))),
          ...(shown.below
            ? [
                <text key='below' {...CUT} attributes={DIM}>
                  {requestRule(
                    '↓',
                    out.below,
                    onNote ? pageDown : undefined,
                    noteWidth,
                  )}
                </text>,
              ]
            : []),
        ].map((row, index) => (
          // The `❯` and the label beside the first row; the rest under the
          // note's own text.
          <box key={index} flexDirection='row' flexShrink={0}>
            {index === 0 ? marker(noteRow) : <Gutter> </Gutter>}
            <text
              {...TEXT}
              flexShrink={0}
              {...(onNote && index === 0 ? fg(colours.permission) : {})}
              attributes={onNote && index === 0 ? BOLD : 0}
            >
              {index === 0 ? 'Note  ' : '      '}
            </text>
            {row}
          </box>
        ))}
      </box>
      <text {...TEXT} flexShrink={0}>
        {' '}
      </text>
      <text {...TEXT} attributes={DIM} flexShrink={0}>
        {hint}
      </text>
    </box>
  );
}
