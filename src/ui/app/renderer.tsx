/**
 * The terminal chord draws on, through OpenTUI's renderer and its React
 * root: taken once, the window drawn on it, and given back on every way
 * out. What the window asks of it besides drawing, quitting, giving the
 * terminal up for a while and bytes of chord's own, are hooks here.
 */
import {
  type CliRenderer,
  type CliRendererConfig,
  createCliRenderer,
} from '@opentui/core';
import { createRoot, useRenderer } from '@opentui/react';
import {
  createContext,
  type ReactNode,
  useContext,
  useSyncExternalStore,
} from 'react';

const Exit = createContext<() => void>(() => {});

/** The window's quit, which `render` or a test's harness gives it. */
export function Exits({
  exit,
  children,
}: {
  exit: () => void;
  children?: ReactNode;
}) {
  return <Exit.Provider value={exit}>{children}</Exit.Provider>;
}

/** Quitting, and giving the terminal up for a while. */
export function useApp(): {
  exit(): void;
  suspendTerminal(during: () => Promise<void>): Promise<void>;
} {
  const renderer = useRenderer();
  const exit = useContext(Exit);

  return {
    exit,
    async suspendTerminal(during) {
      await renderer.suspend();

      try {
        await during();
      } finally {
        await renderer.resume();
      }
    },
  };
}

const Written = createContext<(bytes: string) => void>(
  (bytes) => void process.stdout.write(bytes),
);

/**
 * Where the window's bytes for the terminal itself go: the renderer's own
 * stdout, unless a test's harness keeps them.
 */
export function Output({
  write,
  children,
}: {
  write: (bytes: string) => void;
  children?: ReactNode;
}) {
  return <Written.Provider value={write}>{children}</Written.Provider>;
}

/**
 * Bytes for the terminal itself, between frames. OpenTUI has no way to send
 * the terminal bytes of chord's own, and its notification picks the escape
 * itself where chord's settings name one, so they go to the stream it draws
 * on once it is idle: a frame part written is never cut by them.
 */
export function useStdout(): { write(bytes: string): void } {
  const renderer = useRenderer();
  const write = useContext(Written);

  return {
    write: (bytes) =>
      void renderer.idle().then(
        () => !renderer.isDestroyed && write(bytes),
        () => {},
      ),
  };
}

/** The terminal chord draws on, set up once before anything is drawn. */
export interface Terminal {
  readonly renderer: CliRenderer;
  /** Whether its background is dark, as it answered; none if it did not in time. */
  readonly dark: boolean | null;
}

/**
 * The signals OpenTUI would answer by destroying the renderer and going on
 * running: chord destroys it and then dies by the signal, as it would have
 * without one.
 */
const SIGNALS: readonly NodeJS.Signals[] = [
  'SIGINT',
  'SIGTERM',
  'SIGQUIT',
  'SIGABRT',
  'SIGHUP',
  'SIGPIPE',
  'SIGBUS',
];

/**
 * How chord's renderer takes the terminal, apart from the terminal itself,
 * so a test terminal is taken the same way.
 */
export function terminalOptions({
  mouse,
}: {
  mouse: boolean;
}): CliRendererConfig {
  return {
    exitOnCtrlC: false,
    exitSignals: [],
    useMouse: mouse,
    // Nothing reads hover motion: a drag reports its motion under 1002, so
    // 1000, 1002 and 1006 are all a selection needs (CHD-172).
    enableMouseMovement: false,
    // A click gives no widget the keys: chord's own state does, so a click on
    // the box while a permission, a picker or the agents list has them leaks
    // no key into the draft (CHD-429).
    autoFocus: false,
    consoleMode: 'disabled',
    openConsoleOnError: false,
  };
}

/**
 * Takes the terminal: the alternate screen, raw keys, the mouse unless
 * `mouse` is off, the kitty keyboard protocol where the terminal speaks it.
 * The terminal is given back on every way out: a quit through `render`, a
 * signal, and an uncaught exception or unhandled rejection, which is written
 * with its stack to stderr after it, chord exiting 1. OpenTUI's console
 * overlay stays off, so nothing is kept from stderr.
 */
export async function openTerminal({
  mouse,
}: {
  mouse: boolean;
}): Promise<Terminal> {
  const renderer = await createCliRenderer(terminalOptions({ mouse }));

  if (taken === undefined) {
    giveBackOnEveryExit();
  }

  taken = renderer;

  const mode = await renderer.waitForThemeMode(100);

  return { renderer, dark: mode === null ? null : mode === 'dark' };
}

/** The renderer that has the terminal, the last one opened. */
let taken: CliRenderer | undefined;

/**
 * Destroys the renderer and waits until the terminal is given back, which
 * OpenTUI's native writer finishes after `destroy` returns: an exit before
 * it would leave the terminal raw on the alternate screen. It rejects where
 * the output failed or did not finish within OpenTUI's second.
 */
async function giveBack(renderer: CliRenderer | undefined): Promise<void> {
  renderer?.destroy();
  await renderer?.closed;
}

/**
 * The terminal given back on the way out of a crash or a signal, which
 * exits whether or not it could be: a failure here, an unhandled rejection
 * itself, would only come back to the crash.
 */
const giveBackDying = (renderer: CliRenderer | undefined) =>
  giveBack(renderer).catch(() => {});

/** What chord owns that a crash or a signal waits to close, as a quit does. */
const owned = new Set<() => Promise<void>>();

/**
 * Has a crash or a signal wait for `close` before chord exits, until the
 * returned function is called: the agents a quit closes and reaps would
 * otherwise outlive chord, a hung one never getting its SIGKILL. `close`
 * must settle within its own bounds, as the exit waits for nothing else.
 */
export function closeOnForcedExit(close: () => Promise<void>): () => void {
  const entry = () => close();

  owned.add(entry);

  return () => void owned.delete(entry);
}

/**
 * The leave under way, which a second crash or signal waits for in place of
 * its own: the closes it started are no longer owned, so its own would find
 * nothing to wait for and let chord die before a hung agent's SIGKILL.
 */
let leaving: Promise<void> | undefined;

/**
 * Closes all that is owned while the terminal is given back, and settles
 * once both are done, however they went: a failure here would only come
 * back to the crash. The closes start before the renderer is destroyed, as
 * the window taken down with it forgets what it had asked to be closed.
 */
export function leave(renderer: CliRenderer | undefined): Promise<void> {
  leaving ??= (async () => {
    const closing = [...owned].map(async (close) => await close());

    owned.clear();
    await Promise.allSettled([giveBackDying(renderer), ...closing]);
  })().finally(() => (leaving = undefined));

  return leaving;
}

/**
 * Has every signal leave, then `raise` the first one with the handlers off,
 * so chord dies by it as it would have without them. A signal that comes
 * while the leave is under way is held until it settles: let through, its
 * default action would kill chord before a hung agent's SIGKILL. Returns
 * the function that takes the handlers off.
 */
export function dieBySignal(
  raise: (signal: NodeJS.Signals) => void,
): () => void {
  let first: NodeJS.Signals | undefined;
  const handlers = SIGNALS.map((signal) => {
    const handler = async () => {
      if (first !== undefined) {
        return;
      }

      first = signal;

      await leave(taken);
      off();
      raise(signal);
    };

    return [signal, handler] as const;
  });

  const off = () => {
    for (const [signal, handler] of handlers) {
      process.off(signal, handler);
    }
  };

  for (const [signal, handler] of handlers) {
    process.on(signal, handler);
  }

  return off;
}

function giveBackOnEveryExit(): void {
  const crash = async (error: unknown) => {
    await leave(taken);
    process.stderr.write(
      `${error instanceof Error ? (error.stack ?? String(error)) : String(error)}\n`,
    );
    process.exit(1);
  };

  dieBySignal((signal) => process.kill(process.pid, signal));

  // Ahead of OpenTUI's own, which would log and go on running.
  process.prependListener('uncaughtException', crash);
  process.prependListener('unhandledRejection', crash);
}

/** A tree drawn on the terminal. */
export interface Instance {
  rerender(node: ReactNode): void;
  /** Settles once the terminal is given back. */
  waitUntilExit(): Promise<void>;
  /** Takes the tree down and gives the terminal back. */
  unmount(): Promise<void>;
}

/**
 * Draws `node` on `terminal` until it quits, or `unmount` is called. OpenTUI's
 * root makes a new tree on each `render`, so the tree is made once and a
 * node handed to `rerender` takes the place of the last within it.
 */
export function render(node: ReactNode, { renderer }: Terminal): Instance {
  const root = createRoot(renderer);
  const { promise, resolve, reject } = Promise.withResolvers<void>();
  const listeners = new Set<() => void>();
  let current = node;
  let done = false;
  const exit = () => {
    if (!done) {
      done = true;

      root.unmount();
      giveBack(renderer).then(resolve, reject);
    }

    return promise;
  };

  const Current = () =>
    useSyncExternalStore(
      (listener) => {
        listeners.add(listener);

        return () => void listeners.delete(listener);
      },
      () => current,
    );

  root.render(
    <Exits exit={exit}>
      <Current />
    </Exits>,
  );

  return {
    rerender(next) {
      current = next;

      for (const listener of listeners) {
        listener();
      }
    },
    waitUntilExit: () => promise,
    unmount: exit,
  };
}
