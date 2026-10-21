/**
 * The one test module that draws chord's interface in a test terminal: every
 * window and component test renders, types, pastes, resizes, reads the frame
 * and unmounts through it, so a move to another renderer changes this module
 * and not every test. It draws on OpenTUI's test renderer, as `testRender`
 * does (the trial is in docs/decisions.md, under "Moving to OpenTUI").
 */
import { Readable, Writable } from 'node:stream';
import { act, type ReactNode } from 'react';
import {
  type BaseRenderable,
  type CapturedSpan,
  NativeSession,
  RendererControlState,
  TextBufferRenderable,
  type RGBA,
  TextAttributes,
} from '@opentui/core';
import { createTestRenderer } from '@opentui/core/testing';
import { createRoot, type Root } from '@opentui/react';
import chalk from 'chalk';
import { Exits, Output, terminalOptions } from '../../src/ui/app/renderer.tsx';

/** The terminal's size in cells; a side left out stays as it was. */
export interface Size {
  readonly columns?: number | undefined;
  readonly rows?: number | undefined;
}

/**
 * A terminal that keeps a log of what it is told, in order: each write to
 * its stdout as text, and `raw on` and `raw off` as raw mode is turned on
 * and off. The window is on the alternate screen there, as on chord's own,
 * taken with chord's own options.
 */
export interface Logged {
  readonly log: string[];
  /** Whether the terminal is asked for the mouse, as `"mouse"` says; yes. */
  readonly mouse?: boolean;
}

/** What is drawn, and the terminal it is drawn in. */
export interface Drawn {
  /** The last frame, with its escapes; empty before the first. */
  frame(): string;
  /**
   * Every frame drawn and every write of the window's own bytes between
   * them, such as a notification's, in order.
   */
  written(): readonly string[];
  /** The text OpenTUI's own mouse selection holds; empty with none. */
  selected(): string;
  /**
   * Whether a text holding `text` is mounted, drawn on screen or not: what
   * the transcript keeps laid out, which the frame cannot tell.
   */
  mounted(text: string): boolean;
  /** Bytes as a terminal sends them for a press: `\x1b[A` is ↑. */
  write(bytes: string): Promise<void>;
  /** `text` pasted, as a terminal sends it with bracketed paste on. */
  paste(text: string): Promise<void>;
  /** The terminal resized. */
  resize(size: Size): Promise<void>;
  unmount(): Promise<void>;
}

/** The test terminal's size where a test gives none, as Ink's test one was wide. */
const COLUMNS = 100;
const ROWS = 24;
/** How long a graceful close may take, about 7× the slowest seen to finish. */
const CLOSE_TIMEOUT_MS = 10_000;

/**
 * Draws `node` in a terminal of `size`, the test terminal's own otherwise.
 * Its quit unmounts it, as the window's own renderer does.
 */
export async function draw(
  node: ReactNode,
  size: Size = {},
  logged?: Logged,
): Promise<Drawn> {
  let columns = size.columns ?? COLUMNS;
  let rows = size.rows ?? ROWS;
  let unmounted = false;
  const unmount = () => {
    if (!unmounted) {
      unmounted = true;

      setup.renderer.destroy();
    }

    return setup.renderer.closed;
  };

  const frames: string[] = [];
  const written: string[] = [];
  // testRender's own pieces, as it puts them together, but for the order:
  // it renders before the terminal is set up, so a first frame still out
  // under load made the setup fail with InvalidPhase (CHD-467). As
  // createCliRenderer does for the window's own, the terminal is set up
  // first: OpenTUI 0.6 suspends only a terminal it has set up, and ctrl+g's
  // editor suspends it.
  let root: Root | null = null;
  const terminal =
    logged === undefined
      ? quietTerminal(columns, rows)
      : {
          ...terminalOptions({ mouse: logged.mouse ?? true }),
          ...loggedTerminal(logged.log, columns, rows),
        };

  const setup = await createTestRenderer({
    width: columns,
    height: rows,
    // ctrl+c is a key, as chord's own renderer takes it, and the test's
    // process signals are the test runner's.
    exitOnCtrlC: false,
    exitSignals: [],
    // As chord's own renderer: a click gives no widget the keys.
    autoFocus: false,
    ...terminal,
    // OpenTUI's graceful close gives up after 1 s, and under load a close
    // took up to 1.5 s and still finished (p99.9 1.1 s, max 1.5 s of 6,909
    // timed for CHD-467), so a slow close failed the test it ended. The
    // session that takes a longer one needs its output on a stream, so the
    // plain terminal's goes to one that keeps nothing.
    nativeSession: new NativeSession(terminal.stdout, {
      closeTimeoutMs: CLOSE_TIMEOUT_MS,
    }),
    onDestroy() {
      act(() => {
        root?.unmount();

        root = null;
      });

      actEnvironment(false);
    },
  });

  await setup.renderer.setupTerminal();

  const mounted = createRoot(setup.renderer);

  root = mounted;

  // What the first render set off (an effect's promise, a session's first
  // answer) runs before the await below returns, so the mount and its
  // aftermath are enclosed. The flag is React's, for every tree: set only
  // around this act(), as another window drawn beside this one goes on
  // updating outside any (CHD-399).
  actEnvironment(true);
  await act(() => {
    mounted.render(
      <Exits exit={() => void unmount()}>
        <Output write={(bytes) => void written.push(bytes)}>{node}</Output>
      </Exits>,
    );

    return Promise.resolve();
  });

  // The window updates on its own as the agent replies and its timers run,
  // outside any act(), and the tests' own waits do the waiting.
  actEnvironment(false);

  // A destroyed renderer's buffers are freed, a suspended one's are not to
  // be read, and a frame on its way out is held by the native writer
  // (reading it throws OutputBusy), so what was last presented is kept: a
  // terminal shows it until the next is out.
  const frame = () =>
    unmounted ||
    setup.renderer.isDestroyed ||
    setup.renderer.controlState === RendererControlState.EXPLICIT_SUSPENDED ||
    setup.renderer.getSchedulerState().isRendering
      ? (frames.at(-1) ?? '')
      : painted(setup.captureSpans().lines);

  setup.renderer.on('frame', () => {
    const drawn = painted(setup.captureSpans().lines);

    frames.push(drawn);
    written.push(drawn);
  });

  // What a change sets off, a text measured and cut to its width among it,
  // is drawn before a test reads the frame; a window that animates never
  // goes idle, so the wait is bounded.
  const settled = (frames = 10) =>
    unmounted || setup.renderer.isDestroyed
      ? Promise.resolve()
      : setup.waitForVisualIdle({ maxFrames: frames }).catch(() => {});

  await setup.renderOnce();
  await settled();
  // A text is fitted to its width in a second pass, which React schedules
  // after the frame that measured it, out of the renderer's sight.
  await new Promise((resolve) => setTimeout(resolve, 20));
  await settled();

  const write = (bytes: string) => {
    setup.renderer.stdin.emit('data', Buffer.from(bytes));

    // Briefly: a test that catches a short-lived line counts from its key.
    return settled(2);
  };

  return {
    frame,
    written: () => written,
    selected: () => setup.renderer.getSelection()?.getSelectedText() ?? '',
    mounted: (text) => holds(setup.renderer.root, text),
    write,
    paste: (text) => write(`\x1b[200~${text}\x1b[201~`),
    resize: (to) => {
      columns = to.columns ?? columns;
      rows = to.rows ?? rows;

      setup.resize(columns, rows);

      return settled();
    },
    unmount,
  };
}

/** Whether React takes what runs now as a test's act() work, as `testRender` sets it. */
function actEnvironment(on: boolean): void {
  (
    globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }
  ).IS_REACT_ACT_ENVIRONMENT = on;
}

/** Whether `node` or a renderable under it is a text holding `text`. */
function holds(node: BaseRenderable, text: string): boolean {
  return (
    (node instanceof TextBufferRenderable && node.plainText.includes(text)) ||
    node.getChildren().some((child) => holds(child, text))
  );
}

/**
 * The streams and screen of a `Logged` terminal, with the renderer's bytes
 * written to its stdout rather than kept in OpenTUI's memory.
 */
function loggedTerminal(log: string[], columns: number, rows: number) {
  const stdin = Object.assign(new Readable({ read() {} }), {
    isTTY: true,
    setRawMode(on: boolean) {
      log.push(on ? 'raw on' : 'raw off');

      return stdin;
    },
  });
  const stdout = Object.assign(
    new Writable({
      write(chunk: Buffer | string, _encoding, done) {
        log.push(String(chunk));
        done();
      },
    }),
    { isTTY: true, columns, rows, getColorDepth: () => 24 },
  );

  return {
    stdin: stdin as unknown as NodeJS.ReadStream,
    stdout: stdout as unknown as NodeJS.WriteStream,
    screenMode: 'alternate-screen',
    bufferedOutput: 'stdout',
  } as const;
}

/**
 * The streams of a terminal that is only drawn in, as OpenTUI's test
 * renderer makes its own (which it does not export): what it is told is
 * dropped, never reaching the test's own stdout.
 */
function quietTerminal(columns: number, rows: number) {
  const stdin = new Readable({ read() {} });
  const stdout = Object.assign(
    new Writable({
      write(_chunk, _encoding, done) {
        done();
      },
    }),
    { isTTY: true, columns, rows, getColorDepth: () => 24 },
  );

  return {
    stdin: stdin as unknown as NodeJS.ReadStream,
    stdout: stdout as unknown as NodeJS.WriteStream,
    bufferedOutput: 'stdout',
  } as const;
}

/**
 * A frame as Ink's test terminal kept it: each run with its escapes, each
 * row's trailing blanks and the blank rows after the last drawn left out.
 */
function painted(lines: readonly { spans: readonly CapturedSpan[] }[]): string {
  const rows = lines.map(({ spans }) => {
    const kept = [...spans];

    while (kept.length > 0 && blank(kept.at(-1)!)) {
      kept.pop();
    }

    const last = kept.at(-1);

    if (last !== undefined && sgrOf(last.bg, 40, 48).length === 0) {
      kept[kept.length - 1] = { ...last, text: last.text.trimEnd() };
    }

    return kept.map(escaped).join('');
  });

  while (rows.length > 0 && rows.at(-1) === '') {
    rows.pop();
  }

  return rows.join('\n');
}

/** Spaces with nothing on them to see: a blank cell's colour is no colour. */
function blank(span: CapturedSpan): boolean {
  return (
    span.text.trim() === '' &&
    sgrOf(span.bg, 40, 48).length === 0 &&
    (span.attributes & SEEN_ON_SPACE) === 0
  );
}

const SEEN_ON_SPACE =
  TextAttributes.INVERSE |
  TextAttributes.UNDERLINE |
  TextAttributes.STRIKETHROUGH;

/**
 * A run with the SGR a terminal would be sent for it, one escape for each
 * as chalk writes them; plain where it has none, and everywhere while chalk
 * sees no colour, as under test unless a test turns it on, which is how Ink
 * drew its test frames.
 */
function escaped(span: CapturedSpan): string {
  if (chalk.level === 0 || blank(span)) {
    return span.text;
  }

  const codes = [
    ...ATTRIBUTES.filter(([bit]) => (span.attributes & bit) !== 0).map(
      ([, code]) => code,
    ),
    ...sgrOf(span.fg, 30, 38),
    ...sgrOf(span.bg, 40, 48),
  ];

  return codes.length === 0
    ? span.text
    : `${codes.map((code) => `\x1b[${code}m`).join('')}${span.text}\x1b[0m`;
}

/** OpenTUI's attribute bits, and the SGR for each. */
const ATTRIBUTES: readonly (readonly [number, string])[] = [
  [TextAttributes.BOLD, '1'],
  [TextAttributes.DIM, '2'],
  [TextAttributes.ITALIC, '3'],
  [TextAttributes.UNDERLINE, '4'],
  [TextAttributes.INVERSE, '7'],
  [TextAttributes.STRIKETHROUGH, '9'],
];

function sgrOf(colour: RGBA, base: number, extended: number): string[] {
  if (colour.intent === 'default') {
    return [];
  }

  if (colour.intent === 'indexed') {
    const index = colour.slot;

    return index < 8
      ? [String(base + index)]
      : index < 16
        ? [String(base + 60 + index - 8)]
        : [`${extended};5;${index}`];
  }

  const [r, g, b, a] = colour.toInts();

  return a === 0 ? [] : [`${extended};2;${r};${g};${b}`];
}
