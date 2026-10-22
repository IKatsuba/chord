import {
  type BoxRenderable,
  type ScrollBoxRenderable,
  TextAttributes,
} from '@opentui/core';
import stringWidth from 'string-width';
import {
  type RefObject,
  useCallback,
  useEffect,
  useLayoutEffect,
  useRef,
  useState,
} from 'react';
import type { Subagent, TurnState } from '../../session/transcript/types.ts';
import { AgentWork } from '../transcript/agents/Agents.tsx';
import {
  hintOf,
  useCloseHint,
  useColours,
  useHintKey,
} from '../app/context.ts';
import { useAgentsClock } from '../agents/Agents.tsx';
import type { RequestScroller } from '../dialogs/Permission.tsx';
import {
  countRoom,
  hiddenRows,
  requestCount,
  requestRule,
  requestStep,
  requestView,
} from '../dialogs/permission.ts';
import { borderOf } from '../pickers/Pickers.tsx';
import { Ansi } from '../theme/Ansi.tsx';
import { DIM, fg, FILL, TEXT } from '../theme/text.ts';
import { agentColour, type Palette } from '../theme/theme.ts';
import type { ScrollStep } from '../transcript/scroll.ts';
import type { BackgroundGroup, BackgroundItem } from './background.ts';
import {
  detailLines,
  edgeMarked,
  FOLLOWING,
  hintLines,
  logStep,
  pinnedName,
  workHead,
  type ItemRef,
  laidAt,
  type ViewAt,
  type ViewCell,
  viewRows,
  viewWindow,
} from './view.ts';

/** A state's colour: its group's role, or dim for those at work or stopped. */
function groupColour(
  group: BackgroundGroup | undefined,
  colours: Palette,
): string | undefined {
  switch (group) {
    case 'asking':
      return colours.warning;
    case 'failed':
      return colours.error;
    case 'done':
      return colours.success;
    default:
      return undefined;
  }
}

/**
 * The frame's lines besides its rows: the border, the title and the gap
 * under it, and the hint with the gap above it.
 */
const CHROME = 6;

/** The lines the frame's rows and its hint share: half the window less its other lines. */
function frameRoom(windowRows: number): number {
  return Math.floor(windowRows / 2) - (CHROME - 1);
}

/**
 * The lines the frame's rows take at most: half the window less its other
 * lines (CHD-462), a hint of `hintHeight` lines among them; the rows give
 * way to a hint that wraps, down to one line (CHD-473).
 */
export function backgroundRowLimit(windowRows: number, hintHeight = 1): number {
  return Math.max(1, frameRoom(windowRows) - hintHeight);
}

/**
 * Which keys the frame's hint names: on a row, enter to its details; in a
 * detail, its own (CHD-481, CHD-487).
 */
export type HintMode = 'details' | 'detail' | 'ended';

/** Whether `item` has ended, as an open detail keeps one until it is left. */
function ended(item: BackgroundItem | undefined): boolean {
  const group = item?.status.group;

  return group === 'done' || group === 'failed' || group === 'stopped';
}

/** The hint's mode for the view `view` over `items`. */
export function hintMode(
  items: readonly BackgroundItem[],
  view:
    | {
        readonly focus?: ItemRef | undefined;
        readonly detail?: ItemRef | undefined;
      }
    | undefined,
): HintMode {
  const { detail } = view ?? {};

  if (detail !== undefined) {
    // Its monitor ended: nothing is left to stop (Q126).
    return ended(
      items.find((item) => item.key === detail.key && item.id === detail.id),
    )
      ? 'ended'
      : 'detail';
  }

  return 'details';
}

/**
 * What the frame says under its rows: `hint`, an agent's stop error, in
 * place of its keys, or the keys `mode` names.
 */
export function useBackgroundHint(
  hint: string | undefined,
  mode: HintMode = 'details',
): string {
  const stop = useHintKey('agents:close');
  const close = useCloseHint();
  const back = useCloseHint('← to go back');
  const stopping = stop && `${stop} to stop`;

  return (
    hint ??
    (mode === 'detail' || mode === 'ended'
      ? hintOf(
          'Enter to go to its call',
          '↑ ↓ for the others',
          mode === 'detail' ? stopping : undefined,
          back,
        )
      : hintOf('Enter for details', stopping, close))
  );
}

/**
 * The background view: the pickers' frame above the prompt, full width, a
 * row per item of the tab, the `❯` on one, as tall as its rows up to half
 * the window (CHD-462). It takes no keys itself; the window routes them.
 */
export function BackgroundView({
  items,
  focus,
  detail,
  at,
  hint,
  columns,
  rows,
  scroller,
  work,
}: {
  items: readonly BackgroundItem[];
  focus: ItemRef | undefined;
  /** The item whose detail is drawn in place of the rows (CHD-481). */
  detail?: ItemRef | undefined;
  /** Where in a focused row taller than the frame it is (CHD-430). */
  at?: ViewAt | undefined;
  /** Said in place of the keys, of the focused item's stop. */
  hint?: string | undefined;
  /** The window's width; the frame takes all of it. */
  columns: number;
  /** The window's height, half of which the frame takes at most. */
  rows: number;
  /** Where the window finds how to scroll an error taller than its room. */
  scroller?: RefObject<RequestScroller | undefined>;
  /** The work of the agent or task whose detail is open (CHD-487). */
  work?: DetailWork | undefined;
}) {
  const colours = useColours();
  // Times count a second at a time while the view is drawn.
  const now = useAgentsClock(true);
  const width = columns - 4;
  const shownAt =
    detail === undefined
      ? -1
      : items.findIndex(
          (item) => item.key === detail.key && item.id === detail.id,
        );
  const detailed = shownAt === -1 ? undefined : items[shownAt];
  // The hint, or an error in its place, whole on as many lines as it takes.
  const said = hintLines(
    useBackgroundHint(hint, hintMode(items, { focus, detail })),
    width,
  );
  const height = backgroundRowLimit(rows, said.length);
  const lines =
    detailed === undefined
      ? edgeMarked(
          viewWindow(
            viewRows(items, { width, focus, now }),
            height,
            at,
            laidAt(width, height),
          ),
        )
      : [];
  // A detail taller than the frame's room scrolls in it by a page, as an
  // error does (CHD-481, CHD-473).
  const detailRows = detailed && detailLines(detailed, { width, now });
  const [detailTop, setDetailTop] = useState(0);
  const detailRoom = Math.max(1, height);
  // A stop's error taller than what a detail of one line leaves it: the
  // detail gives way to its first line, which says whose it is, and does
  // not page; the error takes the page keys alone (CHD-481 Q128, CHD-462).
  const errorTall =
    detailRows !== undefined &&
    hint !== undefined &&
    said.length > frameRoom(rows) - 1;
  const detailShown =
    detailRows === undefined
      ? undefined
      : errorTall
        ? { top: 0, shown: 1, above: false, below: false }
        : requestView(detailRows.length, detailRoom, detailTop);
  const detailHidden =
    detailRows === undefined || detailShown === undefined
      ? undefined
      : hiddenRows(detailRows.length, detailShown.top, detailShown.shown);
  // An error taller than what the rows leave it scrolls in that room, as a
  // request does in its box (CHD-246, CHD-462 f929ae37).
  const room = Math.max(
    1,
    frameRoom(rows) -
      (detailShown === undefined
        ? lines.length
        : detailShown.shown +
          (detailShown.above ? 1 : 0) +
          (detailShown.below ? 1 : 0)),
  );
  const [top, setTop] = useState(0);
  const shown = requestView(said.length, room, top);
  const hidden = hiddenRows(said.length, shown.top, shown.shown);
  const pageUp = useHintKey('scroll:pageUp');
  const pageDown = useHintKey('scroll:pageDown');
  // An agent's or a task's log pages itself (CHD-487).
  const workScroll = useRef<RequestScroller | undefined>(undefined);
  const logged =
    detailed !== undefined && detailed.kind !== 'monitor' && work !== undefined;
  const scroll = useCallback(
    (step: ScrollStep) =>
      logged && !errorTall && workScroll.current !== undefined
        ? workScroll.current(step)
        : detailRows === undefined || errorTall
          ? setTop((at) => requestStep(step, said.length, room, at))
          : setDetailTop((at) =>
              requestStep(step, detailRows.length, detailRoom, at),
            ),
    [said.length, room, detailRows, detailRoom, errorTall, logged],
  );

  // Another error, or none, starts from its first line.
  useEffect(() => {
    setTop(0);
  }, [hint]);

  // Another item's detail, or none, starts from its first line.
  useEffect(() => {
    setDetailTop(0);
  }, [detail?.key, detail?.id]);

  useEffect(() => {
    if (scroller === undefined) {
      return;
    }

    scroller.current = scroll;

    return () => {
      scroller.current = undefined;
    };
  }, [scroller, scroll]);

  const cell = (piece: ViewCell, item: BackgroundItem, focused: boolean) => {
    switch (piece.role) {
      case 'mark':
        return { ...fg(colours.permission), attributes: 0 };
      case 'edge':
        return { attributes: DIM };
      case 'name':
        return { attributes: focused ? TextAttributes.BOLD : 0 };
      case 'text':
        return { attributes: 0 };
      case 'state': {
        const colour = groupColour(piece.group, colours);

        return { ...fg(colour), attributes: colour === undefined ? DIM : 0 };
      }
      case 'owner': {
        const colour = agentColour(colours, item.owner?.colour);

        return { ...fg(colour), attributes: colour === undefined ? DIM : 0 };
      }
      default:
        return { attributes: DIM };
    }
  };

  return (
    <box
      {...borderOf(colours.permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
      <text {...TEXT}>
        <span {...fg(colours.permission)} attributes={TextAttributes.BOLD}>
          Background
        </span>
        <span attributes={DIM}>
          {detailed === undefined
            ? ` · ${items.length} in this tab`
            : ` · ${detailed.kind === 'monitor' ? `${detailed.id}, ` : ''}${
                shownAt + 1
              } of ${items.length}${ended(detailed) ? ' · ended' : ''}`}
        </span>
      </text>
      {logged && !errorTall && (
        <WorkDetail
          key={`${detailed.key}:${detailed.id}`}
          item={detailed}
          work={work}
          width={width}
          rows={detailRoom}
          now={now}
          scroller={workScroll}
          cell={(piece) => cell(piece, detailed, true)}
        />
      )}
      {detailed !== undefined &&
        !(logged && !errorTall) &&
        detailRows !== undefined &&
        detailShown !== undefined &&
        detailHidden !== undefined && (
          <box marginTop={1} flexShrink={0}>
            {detailShown.above && (
              <text {...TEXT} attributes={DIM}>
                {requestRule('↑', detailHidden.above, pageUp, width)}
              </text>
            )}
            {detailRows
              .slice(detailShown.top, detailShown.top + detailShown.shown)
              .map((cells, index) => (
                <text key={index} {...TEXT}>
                  {cells.map((piece, at) => (
                    <span key={at} {...cell(piece, detailed, true)}>
                      {piece.text}
                    </span>
                  ))}
                </text>
              ))}
            {detailShown.below && (
              <text {...TEXT} attributes={DIM}>
                {requestRule('↓', detailHidden.below, pageDown, width)}
              </text>
            )}
          </box>
        )}
      <box marginTop={1} flexShrink={0} visible={detailed === undefined}>
        {lines.map(({ row, cells }, index) => (
          <text key={index} {...TEXT}>
            {cells.map((piece, at) => (
              <span key={at} {...cell(piece, row.item, row.focused)}>
                {piece.text}
              </span>
            ))}
          </text>
        ))}
      </box>
      <box marginTop={1} flexShrink={0}>
        {shown.above && (
          <text {...TEXT} attributes={DIM}>
            {requestRule('↑', hidden.above, pageUp, columns - 4)}
          </text>
        )}
        {said.slice(shown.top, shown.top + shown.shown).map((line, at) => (
          <text key={at} {...TEXT} attributes={DIM}>
            <Ansi text={line} />
          </text>
        ))}
        {shown.below && (
          <text {...TEXT} attributes={DIM}>
            {requestRule('↓', hidden.below, pageDown, columns - 4)}
          </text>
        )}
      </box>
    </box>
  );
}

/** The work an agent's or a task's detail draws, found where its owner keeps it. */
export interface DetailWork {
  readonly subagent: Subagent;
  /** Its owner's turn, which its calls' waiting is read from. */
  readonly turn: TurnState;
  /** The agent its owner runs, as the transcript names it. */
  readonly agent: string;
}

/**
 * An agent's or a task's detail (CHD-487): its description and state line
 * pinned, then, in the room left, its whole task after `› ` and its work
 * as its open block draws it, read from the end and following it as it
 * comes while not paged up (Q139, Q140); a dim rule says what is out of
 * view, under CHD-246's rule.
 */
function WorkDetail({
  item,
  work,
  width,
  rows,
  now,
  scroller,
  cell,
}: {
  item: BackgroundItem;
  work: DetailWork;
  width: number;
  /** The frame's rows for the detail, the pinned lines among them. */
  rows: number;
  now: number;
  scroller: RefObject<RequestScroller | undefined>;
  cell: (piece: ViewCell) => { attributes: number };
}) {
  // The frame never passes its cap (docs/design/CHD-487.md, the short
  // room): the state line gives way to one line first, then the work to one
  // row, then to none, its count at the state line's end.
  const full = workHead(item, work.subagent, { width, now });
  const short = full.length + 1 > rows;
  const workRows = Math.max(0, rows - (short ? 2 : full.length));
  // With no row, it still pages, as a row of one would.
  const room = Math.max(1, workRows);
  const view = useRef<ScrollBoxRenderable | null>(null);
  const content = useRef<BoxRenderable | null>(null);
  // Its lines as laid out, none until they are; where OpenTUI's scrollbox
  // stands in them, which follows their end itself while it is at it.
  const [total, setTotal] = useState<number | undefined>(undefined);
  const [at, setAt] = useState(0);
  // Where it is paged to with no row to draw it in.
  const [parked, setParked] = useState(FOLLOWING);
  // Following its end, as it opens and once paged back to it (Q140): kept
  // so a room that changes, which the scrollbox's own following does not
  // always see through, still leaves it at its end.
  const following = useRef(true);
  const lines = total ?? 0;
  const shown = requestView(
    lines,
    room,
    following.current ? FOLLOWING : workRows === 0 ? parked : at,
  );
  // Where the scrollbox is to stand, which it is put at once laid out.
  const wanted = useRef(shown.top);

  wanted.current = shown.top;
  const hidden = hiddenRows(lines, shown.top, shown.shown);
  // A room of one row, or of none, has no row for a rule: what is hidden is
  // said beside the row, or at the state line's end (CHD-464).
  const count =
    workRows <= 1 && total !== undefined && lines > 1
      ? requestCount(hidden)
      : undefined;
  const workWidth =
    workRows === 1 && count !== undefined
      ? Math.max(1, width - countRoom(lines) - 1)
      : width;
  const lineCells = short
    ? workHead(item, work.subagent, {
        width,
        now,
        short,
        ...(workRows === 0 && count !== undefined
          ? { reserve: stringWidth(count) + 1 }
          : {}),
      })
    : full;
  // Not even its name and state: its state line alone.
  const head = rows < 2 ? lineCells.slice(-1) : lineCells;
  const pageUp = useHintKey('scroll:pageUp');
  const pageDown = useHintKey('scroll:pageDown');
  const whole = (work.subagent.prompt ?? work.subagent.description)?.trim();
  // Its task, unless the pinned name already says it whole, as when it
  // gave no short description of its own; a name cut to its line keeps it.
  const task =
    whole === undefined ||
    (!pinnedName(item, width).cut &&
      whole.replace(/\s+/g, ' ') === item.name.replace(/\s+/g, ' ').trim())
      ? undefined
      : whole;

  // Read once laid out, never at React's commit, where a scroll is clamped
  // to the layout before it (CHD-437, CHD-487): its lines, and where the
  // scrollbox stands now that it has followed them or not.
  const measure = () => {
    const height = content.current?.getLayout().height;
    const box = view.current;

    if (
      workRows > 0 &&
      height !== undefined &&
      Number.isFinite(height) &&
      height > 0
    ) {
      setTotal(height);
    }

    if (box !== null && workRows > 0) {
      // Following, at the end view as this frame lays it out. A scroll the
      // scrollbox clamps to limits it has yet to lay out lands a frame
      // later, which is asked for, as nothing else may draw one.
      if (following.current && box.scrollTop !== wanted.current) {
        box.scrollTo(wanted.current);

        if (box.scrollTop !== wanted.current) {
          box.requestRender();
        }
      }

      setAt(box.scrollTop);
    }
  };

  // The scrollbox moves by itself as it follows; its scrollbar says where.
  useLayoutEffect(() => {
    const bar = view.current?.verticalScrollBar;
    const moved = ({ position }: { position: number }) => setAt(position);

    bar?.on('change', moved);

    return () => {
      bar?.off('change', moved);
    };
  }, []);

  useEffect(() => {
    // On the key, when the frame is laid out: the page keys move the
    // scrollbox, and its end gives the following back to it.
    scroller.current = (step) => {
      const box = view.current;

      if (workRows === 0 || box === null) {
        setParked((top) => {
          const next = logStep(step, lines, 1, top);

          following.current = next === FOLLOWING;

          return next;
        });

        return;
      }

      const next =
        step === 'bottom'
          ? FOLLOWING
          : logStep(step, lines, room, box.scrollTop);

      following.current = next === FOLLOWING;
      box.scrollTo(next === FOLLOWING ? box.scrollHeight : next);
    };

    return () => {
      scroller.current = undefined;
    };
  }, [scroller, lines, room, workRows]);

  return (
    <box marginTop={1} flexShrink={0}>
      {head.map((cells, index) => (
        <box key={`head-${index}`} flexDirection='row' flexShrink={0}>
          <text {...TEXT} flexGrow={1}>
            {cells.map((piece, place) => (
              <span key={place} {...cell(piece)}>
                {piece.text}
              </span>
            ))}
          </text>
          {workRows === 0 &&
            count !== undefined &&
            index === head.length - 1 && (
              <text {...TEXT} attributes={DIM} flexShrink={0}>
                {count}
              </text>
            )}
        </box>
      ))}
      {shown.above && workRows > 0 && (
        <text {...TEXT} attributes={DIM}>
          {requestRule('↑', hidden.above, pageUp, width)}
        </text>
      )}
      <box flexDirection='row' flexShrink={0} visible={workRows > 0}>
        <scrollbox
          ref={view}
          height={Math.max(shown.shown, 1)}
          width={workWidth}
          flexShrink={0}
          focusable={false}
          stickyScroll
          stickyStart='bottom'
          verticalScrollbarOptions={{ visible: false }}
        >
          <box
            ref={content}
            flexShrink={0}
            onSizeChange={measure}
            renderAfter={measure}
          >
            {task !== undefined && task !== '' && (
              <box flexDirection='row' flexShrink={0}>
                <text {...TEXT} attributes={DIM} flexShrink={0}>
                  {'› '}
                </text>
                <text {...FILL}>
                  <Ansi text={task} />
                </text>
              </box>
            )}
            <AgentWork
              subagent={work.subagent}
              turn={work.turn}
              agent={work.agent}
              width={workWidth}
            />
          </box>
        </scrollbox>
        {workRows === 1 && count !== undefined && (
          <box flexGrow={1} flexDirection='row' justifyContent='flex-end'>
            <text {...TEXT} attributes={DIM} flexShrink={0}>
              {count}
            </text>
          </box>
        )}
      </box>
      {shown.below && workRows > 0 && (
        <text {...TEXT} attributes={DIM}>
          {requestRule('↓', hidden.below, pageDown, width)}
        </text>
      )}
    </box>
  );
}
