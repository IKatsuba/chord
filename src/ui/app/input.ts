/**
 * What the person does to the window, as hooks on OpenTUI's: each press as
 * chord's own `Press` (`usePress`), each bracketed paste (`usePasted`), and a
 * wheel step or the left button's press anywhere over the window
 * (`useMouse`). What each sets off is drawn before the next is read.
 */
import type { MouseEvent, PasteEvent } from '@opentui/core';
import { flushSync, useKeyboard, usePaste } from '@opentui/react';
import { type RefObject, useLayoutEffect, useMemo, useRef } from 'react';
import { alone, pressOf } from '../shortcuts/press.ts';
import type { Press } from '../shortcuts/state.ts';

/**
 * Every press the window and its widgets answer, as chord's own `Press`,
 * while `isActive`. A listener that returns `true` keeps the press from the
 * focused widget, the prompt's textarea, which hears keys after every
 * listener here.
 */
export function usePress(
  onPress: (input: string, key: Press) => boolean | void,
  { isActive = true }: { isActive?: boolean } = {},
): void {
  const active = useActive(isActive);
  const latest = useRef(onPress);

  latest.current = onPress;

  useKeyboard((event) => {
    if (alone(event)) {
      return;
    }

    if (active.current && drawn(() => latest.current(...pressOf(event)))) {
      event.preventDefault();
    }
  });
}

const decoder = new TextDecoder();

/**
 * Each bracketed paste's text, while `isActive`. A listener that returns
 * `true` keeps the paste from the focused widget, as `usePress`' does a key.
 */
export function usePasted(
  onPaste: (text: string) => boolean | void,
  { isActive = true }: { isActive?: boolean } = {},
): void {
  const active = useActive(isActive);
  const latest = useRef(onPaste);

  latest.current = onPaste;

  usePaste((event: PasteEvent) => {
    if (
      active.current &&
      drawn(() => latest.current(decoder.decode(event.bytes)))
    ) {
      event.preventDefault();
    }
  });
}

/**
 * Whether a listener hears what comes now. One turned on takes the next
 * press, not the one whose work turned it on, which every listener hears
 * in turn after the window has drawn that work: the ↑ that hands the keys
 * from a list back to the box would also walk the box's history. One turned
 * off hears nothing more at once.
 */
function useActive(isActive: boolean): RefObject<boolean> {
  const active = useRef(isActive);

  useLayoutEffect(() => {
    if (!isActive) {
      active.current = false;

      return;
    }

    let current = true;

    queueMicrotask(() => {
      if (current) {
        active.current = true;
      }
    });

    return () => {
      current = false;
    };
  }, [isActive]);

  return active;
}

/**
 * Runs what a key, a paste, the mouse or the textarea set off and draws what
 * it left before anything else is read: OpenTUI's root renders concurrently,
 * so the next key of a burst, or a read of the window's state a moment
 * later, would otherwise meet the state from before.
 */
export function drawn(run: () => boolean | void): boolean {
  let claimed = false;

  flushSync(() => {
    claimed = run() === true;
  });

  return claimed;
}

/**
 * A `<box>`'s mouse props for a step of the wheel up or down anywhere over
 * it, which reaches the box under the pointer and bubbles up, and for the
 * left button going down over it, which OpenTUI has already read for a
 * selection. Either left out hears nothing.
 */
export function useMouse({
  onWheel,
  onPress,
}: {
  onWheel?: ((step: 'up' | 'down') => void) | undefined;
  /** The left button went down, on `event`'s target. */
  onPress?: ((event: MouseEvent) => void) | undefined;
}): {
  onMouseScroll?: (event: MouseEvent) => void;
  onMouse?: (event: MouseEvent) => void;
} {
  // The latest listeners, behind functions that stay the same.
  const wheel = useRef(onWheel);
  const press = useRef(onPress);

  wheel.current = onWheel;
  press.current = onPress;

  const onMouseScroll = useMemo(
    () => (event: MouseEvent) => {
      const step = event.scroll?.direction;

      if (step === 'up' || step === 'down') {
        drawn(() => wheel.current?.(step));
      }
    },
    [],
  );
  // Every press under the box bubbles up to it.
  const onMouse = useMemo(
    () => (event: MouseEvent) => {
      if (event.type === 'down' && event.button === 0) {
        drawn(() => press.current?.(event));
      }
    },
    [],
  );

  return {
    ...(onWheel === undefined ? {} : { onMouseScroll }),
    ...(onPress === undefined ? {} : { onMouse }),
  };
}
