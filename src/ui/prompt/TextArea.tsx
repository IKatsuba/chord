/**
 * The prompt's box: OpenTUI's `<textarea>`, its text and cursor in the
 * terminal's own foreground, and what each of its events sets off drawn at
 * once.
 */
import {
  type CliRenderer,
  CliRenderEvents,
  type KeyBinding,
  normalizeTerminalPalette,
  RGBA,
  type TerminalColors,
  type TextareaRenderable,
} from '@opentui/core';
import { type TextareaProps, useRenderer } from '@opentui/react';
import { useEffect, useLayoutEffect, useMemo, useRef, useState } from 'react';
import { drawn } from '../app/input.ts';

export type { KeyBinding as TextAreaKey, TextareaRenderable };

/** The terminal's own foreground and background. */
export interface Ink {
  readonly foreground: RGBA;
  readonly background: RGBA;
}

/**
 * The terminal's foreground and background as it answers OSC 10 and 11,
 * through OpenTUI's palette query, which asks once and keeps the answer:
 * what the textarea's cursor is drawn in, as OpenTUI sends a colour for it
 * whatever it is told (CHD-306). The query asks nothing of a terminal that does
 * not answer OSC 4, tmux among them; there, and until it answers, OpenTUI's
 * guess, white on black, the other way round on a terminal that said it is
 * light, whether it says so before the query is answered or after. A theme
 * changed after it answered is not followed.
 */
export function useInk(): Ink {
  const renderer = useRenderer();
  const [colours, setColours] = useState<TerminalColors | null>(null);
  const [mode, setMode] = useState(() => renderer.themeMode);

  useEffect(() => {
    let current = true;
    const moved = () => setMode(renderer.themeMode);

    renderer
      .getPalette({ size: 0, timeout: 1000 })
      .then((answer) => current && setColours(answer))
      // A suspended renderer asks nothing; the guess stands.
      .catch(() => {});

    renderer.on(CliRenderEvents.THEME_MODE, moved);

    return () => {
      current = false;

      renderer.off(CliRenderEvents.THEME_MODE, moved);
    };
  }, [renderer]);

  return useMemo(() => inkOf(colours, mode), [colours, mode]);
}

function inkOf(
  colours: TerminalColors | null,
  mode: CliRenderer['themeMode'],
): Ink {
  const { defaultForeground, defaultBackground } =
    normalizeTerminalPalette(colours);
  const guessed =
    mode === 'light' && (colours?.defaultForeground ?? null) === null;

  return guessed
    ? { foreground: defaultBackground, background: defaultForeground }
    : { foreground: defaultForeground, background: defaultBackground };
}

/**
 * OpenTUI's `<textarea>`, with its renderable reached through `ref`, its
 * text and cursor in the terminal's own foreground where OpenTUI's are
 * white, and what each of its events sets off drawn at once. It lets go of
 * the keys as it goes: React takes a renderable out of the tree without
 * destroying it, and one that had the keys would go on hearing them, an
 * Enter sending the draft it held. `focused` gives it the keys.
 */
export function TextArea({
  ref,
  focused = false,
  onSubmit,
  onContentChange,
  onCursorChange,
  ...rest
}: TextareaProps) {
  const own = useRef<TextareaRenderable | null>(null);
  const ink = useInk();

  // A box given the keys by a key's own work takes the next key, not that
  // one: OpenTUI asks the focused widget after every listener, and the
  // window draws a key's work before that, so the Enter that answered a
  // permission would also send the draft. Losing the keys is at once.
  useLayoutEffect(() => {
    if (!focused) {
      own.current?.blur();

      return;
    }

    let current = true;

    queueMicrotask(() => current && own.current?.focus());

    return () => {
      current = false;
    };
  }, [focused]);

  useLayoutEffect(() => () => own.current?.blur(), []);

  return (
    <textarea
      textColor={RGBA.defaultForeground()}
      focusedTextColor={RGBA.defaultForeground()}
      // OpenTUI sends its cursor colour whatever it is told, a default one as
      // its white, which a light terminal's background all but hides.
      cursorColor={ink.foreground}
      // As a text's: a drag over the draft is the terminal's to select.
      selectable={false}
      {...rest}
      {...(onSubmit && { onSubmit: () => void drawn(onSubmit) })}
      {...(onContentChange && {
        onContentChange: (event) => void drawn(() => onContentChange(event)),
      })}
      {...(onCursorChange && {
        onCursorChange: (event) => void drawn(() => onCursorChange(event)),
      })}
      ref={(textarea: TextareaRenderable | null) => {
        own.current = textarea;

        if (typeof ref === 'function') {
          ref(textarea);
        } else if (ref) {
          ref.current = textarea;
        }
      }}
    />
  );
}
