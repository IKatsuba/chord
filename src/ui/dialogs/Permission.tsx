import {
  type BoxRenderable,
  LinearScrollAccel,
  type MouseEvent,
  type ScrollBoxRenderable,
} from '@opentui/core';
import { useTerminalDimensions } from '@opentui/react';
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
import { askerParts } from './asker.ts';
import { AskerRow } from './Asker.tsx';
import type { ScrollStep } from '../transcript/scroll.ts';
import {
  choicesFor,
  hiddenRows,
  countRoom,
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
    <SaveBox
      wait={wait}
      save={wait.save}
      active={active}
      onChoose={onChoose}
      hidden={props.hidden ?? false}
    />
  );
}

/**
 * The agent's question, drawn inline above the prompt as Claude Code does:
 * what the tool wants to do, then the agent's own options, numbered.
 * ink-select-input reads 1–9, ↑/↓, j/k and Enter; Esc is the window's. One
 * asked between turns says who asks and that it came between turns, and
 * until the person takes the keys into it, it is `held`: drawn without
 * them, its hint the key that takes them (CHD-158).
 */
function AgentPermission({
  hidden = false,
  wait,
  asker = [],
  child,
  between = false,
  held = false,
  width = 0,
  active,
  onChoose,
  scroller,
  onOverflow,
}: {
  /**
   * Not drawn, its state kept, while the background view stands in its
   * place (CHD-462).
   */
  hidden?: boolean;
  wait: PermissionWait;
  /** The way down to the subagent that asks; empty when the agent does. */
  asker?: readonly Subagent[];
  /**
   * The long-lived child that asks, picked, with its colour, and a member's
   * team, which its row names after it (the owner's Q45).
   */
  child?: {
    readonly name: string;
    readonly colour: string | undefined;
    readonly team?: string | undefined;
  };
  /** Asked with no turn running. */
  between?: boolean;
  /** Asked between turns, the keys not taken into it yet. */
  held?: boolean;
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
  // Who asks, by the rule every box that asks shares (CHD-389): main's own
  // request in a turn names nobody, as its missing row is how it differs.
  const parts = askerParts({
    entries: [],
    path: asker,
    subagentId: wait.subagentId,
    between,
    picked: child,
  });

  return (
    // It gives way only in its request's rows, every other row pinned.
    <box
      {...borderOf(colours.permission)}
      visible={!hidden}
      paddingX={1}
      marginTop={1}
      flexShrink={1}
    >
      <AskerRow asker={parts} between={between} />
      <Request
        wait={wait}
        width={Math.max(width, 1)}
        held={held}
        {...(scroller === undefined ? {} : { scroller })}
        {...(onOverflow === undefined ? {} : { onOverflow })}
      />
      <box marginTop={1} flexShrink={0}>
        <text {...TEXT}>Do you want to proceed?</text>
      </box>
      <box flexShrink={0}>
        <ChoiceList
          choices={choicesFor(wait)}
          active={active && !held}
          marked={!held}
          onSelect={onChoose}
        />
      </box>
      {held ? <AttendHint /> : <PermissionHint />}
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
  held = false,
  scroller,
  onOverflow,
}: {
  wait: PermissionWait;
  width: number;
  /**
   * Held between turns, the keys elsewhere: its rules name no key, as none
   * scrolls it until the person takes the keys into it (CHD-158 §8).
   */
  held?: boolean;
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
  // title then wraps to the cells the count leaves: as many as its widest
  // count leaves, so the rows stay put while the count changes as it
  // scrolls.
  const { pinned, rows } =
    room === 1 && whole.rows.length > 1
      ? requestRows(wait, width, width - countRoom(whole.rows.length) - 1)
      : whole;
  const total = rows.length;
  const overflows = total > room;
  const shown = requestView(total, room, top);
  const hidden = hiddenRows(total, shown.top, shown.shown);
  const count = room === 1 && overflows ? requestCount(hidden) : undefined;
  const pageUp = useHintKey('scroll:pageUp');
  const pageDown = useHintKey('scroll:pageDown');
  const upKey = held ? undefined : pageUp;
  const downKey = held ? undefined : pageDown;
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
  hidden = false,
  wait,
  save,
  active,
  onChoose,
}: {
  /**
   * Not drawn, its state kept, while the background view stands in its
   * place (CHD-462).
   */
  hidden?: boolean;
  wait: PermissionWait;
  save: SaveBoxQuestion;
  active: boolean;
  onChoose: (optionId: string) => void;
}) {
  const { permission } = useColours();
  const key = useHintKey('confirm:no');

  return (
    <box
      visible={!hidden}
      {...borderOf(permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
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

/**
 * A request between turns' last line until the person takes the keys into
 * it: the key that does.
 */
export function AttendHint() {
  const key = useHintKey('session:attention');

  return key === undefined ? null : (
    <box marginTop={1} flexShrink={0}>
      <text {...TEXT} attributes={DIM}>{`${key} to answer`}</text>
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
