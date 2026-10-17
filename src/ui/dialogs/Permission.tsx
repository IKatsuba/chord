import {
  type BoxRenderable,
  LinearScrollAccel,
  type MouseEvent,
  type ScrollBoxRenderable,
} from '@opentui/core';
import { useTerminalDimensions } from '@opentui/react';
import stringWidth from 'string-width';
import {
  type RefObject,
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import type {
  PermissionWait,
  SaveBox as SaveBoxQuestion,
  Subagent,
} from '../../session/transcript/types.ts';
import { capital } from '../shortcuts/state.ts';
import { useColours, useHintKey } from '../app/context.ts';
import { borderOf, ChoiceList } from '../pickers/Pickers.tsx';
import { Ansi } from '../theme/Ansi.tsx';
import { BOLD, CUT, DIM, fg, TEXT } from '../theme/text.ts';
import { askerRow } from '../transcript/agents/subagents.ts';
import type { ScrollStep } from '../transcript/scroll.ts';
import {
  choicesFor,
  hiddenRows,
  requestCount,
  requestStep,
  requestView,
  INPUT_INDENT,
  requestRows,
  requestRule,
  saveChoices,
} from './permission.ts';

/** Moves the permission request on screen by a scroll key's step. */
export type RequestScroller = (step: ScrollStep) => void;

/** The question waiting: the agent's, or chord's own save box. */
export function PermissionPrompt(props: Parameters<typeof AgentPermission>[0]) {
  const { wait, active, onChoose } = props;

  return wait.save === undefined ? (
    <AgentPermission {...props} />
  ) : (
    <SaveBox wait={wait} save={wait.save} active={active} onChoose={onChoose} />
  );
}

/**
 * The agent's question, drawn inline above the prompt as Claude Code does:
 * what the tool wants to do, then the agent's own options, numbered.
 * ink-select-input reads 1–9, ↑/↓, j/k and Enter; Esc is the window's.
 */
function AgentPermission({
  wait,
  asker = [],
  child,
  width = 0,
  active,
  onChoose,
  scroller,
  onOverflow,
}: {
  wait: PermissionWait;
  /** The way down to the subagent that asks; empty when the agent does. */
  asker?: readonly Subagent[];
  /** The long-lived child that asks, picked, with its colour. */
  child?: { readonly name: string; readonly colour: string | undefined };
  /** Cells inside the box's border and padding, for the asker's row. */
  width?: number;
  active: boolean;
  onChoose: (optionId: string) => void;
  /** Where the window finds how to scroll the request, while it is up. */
  scroller?: RefObject<RequestScroller | undefined>;
  /** Called as the request comes to run past its room, or to fit again. */
  onOverflow?: (overflows: boolean) => void;
}) {
  const colours = useColours();
  const asks = askerRow(asker, width);

  return (
    // It gives way only in its request's rows, every other row pinned.
    <box
      {...borderOf(colours.permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={1}
    >
      {child !== undefined && asks.length === 0 && (
        <text {...CUT} flexShrink={0}>
          <span {...fg(child.colour)} attributes={BOLD}>
            {child.name}
          </span>
          {` asks`}
        </text>
      )}
      {asks.length > 0 && (
        <text {...CUT} {...fg(colours.accent)} flexShrink={0}>
          {asks.map((piece, index) => (
            <span key={index} attributes={piece.bold ? BOLD : 0}>
              <Ansi text={piece.text} />
            </span>
          ))}
        </text>
      )}
      <Request
        wait={wait}
        width={Math.max(width, 1)}
        {...(scroller === undefined ? {} : { scroller })}
        {...(onOverflow === undefined ? {} : { onOverflow })}
      />
      <box marginTop={1} flexShrink={0}>
        <text {...TEXT}>Do you want to proceed?</text>
      </box>
      <box flexShrink={0}>
        <ChoiceList
          choices={choicesFor(wait)}
          active={active}
          onSelect={onChoose}
        />
      </box>
      <PermissionHint />
    </box>
  );
}

/**
 * The title's first row, pinned, and the request under it, in at most half
 * the window's rows and fewer where the window has no more left once the
 * answers are drawn: the answers are never cut, and the transcript gives
 * way first. Taller than that, it scrolls in OpenTUI's scrollbox, by the
 * wheel over it and by the scroll keys the window hands it, a dim rule
 * saying how much is out of view above and below, in rows the request has;
 * a room of one row says it at the pinned row's end instead.
 */
function Request({
  wait,
  width,
  scroller,
  onOverflow,
}: {
  wait: PermissionWait;
  width: number;
  scroller?: RefObject<RequestScroller | undefined>;
  onOverflow?: (overflows: boolean) => void;
}) {
  const colours = useColours();
  const { height: windowRows } = useTerminalDimensions();
  const view = useRef<ScrollBoxRenderable | null>(null);
  const area = useRef<BoxRenderable | null>(null);
  const [room, setRoom] = useState(Number.POSITIVE_INFINITY);
  const [top, setTop] = useState(0);
  const whole = requestRows(wait, width);
  // A room of one row says what is hidden beside the pinned row, whose
  // title then wraps to the cells the count leaves.
  const counted =
    room === 1 && whole.rows.length > 1
      ? requestCount(
          hiddenRows(
            whole.rows.length,
            requestView(whole.rows.length, 1, top).top,
            1,
          ),
        )
      : undefined;
  const { pinned, rows } =
    counted === undefined
      ? whole
      : requestRows(wait, width, width - stringWidth(counted) - 1);
  const total = rows.length;
  const overflows = total > room;
  const shown = requestView(total, room, top);
  const hidden = hiddenRows(total, shown.top, shown.shown);
  const count = room === 1 && overflows ? requestCount(hidden) : undefined;
  const upKey = useHintKey('scroll:pageUp');
  const downKey = useHintKey('scroll:pageDown');
  const scroll = useCallback(
    (step: ScrollStep) => {
      const box = view.current;

      if (box === null) {
        return;
      }

      box.scrollTo(requestStep(step, total, room, box.scrollTop));
    },
    [total, room],
  );

  // The wheel can leave the scrollbox past a view there is, as at the end
  // it shows a row more than a view between the rules does.
  useEffect(() => {
    const box = view.current;

    if (box !== null && box.scrollTop !== shown.top) {
      box.scrollTo(shown.top);
    }
  }, [shown.top]);

  useEffect(() => {
    onOverflow?.(overflows);
  }, [onOverflow, overflows]);

  useEffect(() => {
    if (scroller === undefined) {
      return;
    }

    scroller.current = scroll;

    return () => {
      scroller.current = undefined;
    };
  }, [scroller, scroll]);

  // The scrollbox moves by itself under the wheel; its scrollbar says where.
  useLayoutEffect(() => {
    const bar = view.current?.verticalScrollBar;
    const moved = ({ position }: { position: number }) => setTop(position);

    bar?.on('change', moved);

    return () => {
      bar?.off('change', moved);
    };
  }, []);

  const title = (
    <box flexDirection='row' flexShrink={0}>
      <text {...CUT} {...fg(colours.permission)} attributes={BOLD} flexGrow={1}>
        <Ansi text={pinned} />
      </text>
      {count !== undefined && (
        <text {...CUT} attributes={DIM} flexShrink={0}>
          {count}
        </text>
      )}
    </box>
  );

  if (total === 0) {
    return title;
  }

  return (
    <>
      {title}
      <box
        flexBasis={Math.min(total, Math.max(Math.floor(windowRows / 2), 1))}
        // Not 1: Yoga leaves an item at its basis rather than shrink it to
        // exactly its minimum, which a window of 19 rows asks for.
        minHeight={0}
        flexShrink={1}
        overflow='hidden'
        ref={area}
        onSizeChange={() => setRoom(area.current?.getLayout().height ?? total)}
      >
        {shown.above && (
          <Rule text={requestRule('↑', hidden.above, upKey, width)} />
        )}
        <scrollbox
          ref={view}
          // With no row to show, laid out to nothing, the view would be
          // drawn a row tall over what follows it.
          visible={shown.shown > 0}
          flexGrow={1}
          flexShrink={1}
          minHeight={0}
          focusable={false}
          scrollAcceleration={WHEEL}
          verticalScrollbarOptions={{ visible: false }}
          // Over a request that scrolls, the wheel is its own, not the view's.
          onMouseScroll={(event: MouseEvent) => {
            if (overflows) {
              event.stopPropagation();
            }
          }}
        >
          {rows.map((row, index) => (
            <box
              key={index}
              flexShrink={0}
              paddingLeft={row.kind === 'input' ? INPUT_INDENT : 0}
            >
              <text
                {...CUT}
                {...(row.kind === 'title'
                  ? { ...fg(colours.permission), attributes: BOLD }
                  : row.kind === 'location'
                    ? { attributes: DIM }
                    : {})}
              >
                <Ansi text={row.text === '' ? ' ' : row.text} />
              </text>
            </box>
          ))}
        </scrollbox>
        {shown.below && (
          <Rule text={requestRule('↓', hidden.below, downKey, width)} />
        )}
      </box>
    </>
  );
}

/** A row a wheel report moves the request, as it moves the transcript. */
const WHEEL = new LinearScrollAccel();

function Rule({ text }: { text: string }) {
  return (
    <text {...CUT} attributes={DIM} flexShrink={0}>
      {text}
    </text>
  );
}

/**
 * chord's own question in the permission box's shape, as `propose_team`'s
 * save box: the question, the choices with the file each writes, and what
 * Esc does, which is the last choice.
 */
function SaveBox({
  wait,
  save,
  active,
  onChoose,
}: {
  wait: PermissionWait;
  save: SaveBoxQuestion;
  active: boolean;
  onChoose: (optionId: string) => void;
}) {
  const { permission } = useColours();
  const key = useHintKey('confirm:no');

  return (
    <box {...borderOf(permission)} paddingX={1} marginTop={1} flexShrink={0}>
      <text {...TEXT} {...fg(permission)} attributes={BOLD}>
        {save.question}
      </text>
      <box marginTop={1}>
        <ChoiceList
          choices={saveChoices(wait)}
          active={active}
          onSelect={onChoose}
        />
      </box>
      {key !== undefined && (
        <box marginTop={1}>
          <text {...TEXT} attributes={DIM}>
            {`${capital(key)} to ${save.escape}`}
          </text>
        </box>
      )}
    </box>
  );
}

/** The permission prompt's last line: the key that rejects, when one does. */
function PermissionHint() {
  const key = useHintKey('confirm:no');

  return key === undefined ? null : (
    <box marginTop={1} flexShrink={0}>
      <text {...TEXT} attributes={DIM}>{`${capital(key)} to reject`}</text>
    </box>
  );
}
