/**
 * The one test module that draws chord's interface in a test terminal: every
 * window and component test renders, types, pastes, resizes, reads the frame
 * and unmounts through it, so a move to another renderer changes this module
 * and not every test. It draws on OpenTUI's `testRender` (the trial is in
 * docs/decisions.md, under "Moving to OpenTUI").
 */
import { Readable, Writable } from 'node:stream';
import { act, type ReactNode } from 'react';
import {
  type BaseRenderable,
  type CapturedSpan,
  RendererControlState,
  TextBufferRenderable,
  type RGBA,
  TextAttributes,
} from '@opentui/core';
import { testRender } from '@opentui/react/test-utils';
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
  // testRender marks the test an act() one, and what the first render set
  // off (an effect's promise, a session's first answer) runs before the
  // await below returns, so the mount and its aftermath are enclosed.
  const setup = await act(() =>
    testRender(
      <Exits exit={() => void unmount()}>
        <Output write={(bytes) => void written.push(bytes)}>{node}</Output>
      </Exits>,
      // ctrl+c is a key, as chord's own renderer takes it, and the test's
      // process signals are the test runner's.
      {
        width: columns,
        height: rows,
        exitOnCtrlC: false,
        exitSignals: [],
        ...(logged === undefined
          ? {}
          : {
              ...terminalOptions({ mouse: logged.mouse ?? true }),
              ...loggedTerminal(logged.log, columns, rows),
            }),
      },
    ),
  );

  // The window updates on its own as the agent replies and its timers run,
  // outside any act(), and the tests' own waits do the waiting.
  (
    globalThis as { IS_REACT_ACT_ENVIRONMENT?: boolean }
  ).IS_REACT_ACT_ENVIRONMENT = false;

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

  // As createCliRenderer does for the window's own: OpenTUI 0.6 suspends
  // only a terminal it has set up, and ctrl+g's editor suspends it.
  await setup.renderer.setupTerminal();
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
