/**
 * The glyphs an agent's wait is drawn with, in the agents list, the
 * background, the status line and teams: its state, then what of it is not
 * yet seen (CHD-471).
 */
import { failureOf, type TabWait } from '../../session/tabs.ts';

/** What an agent's wait shows: its state, then what is not yet seen. */
export type WaitGlyph = 'asking' | 'failed' | 'replied' | 'working' | 'message';

/** How each is marked; `✻` stands still, as a spinner here would not. */
export const GLYPHS: Record<WaitGlyph, string> = {
  asking: '●',
  failed: '✗',
  replied: '✓',
  working: '✻',
  message: '←',
};

/**
 * An agent's glyphs: its state, asking, gone or working, none while it is
 * idle; then what of it is not yet seen, a failed turn, a reply or a message.
 */
export interface WaitGlyphs {
  readonly state?: 'asking' | 'failed' | 'working';
  readonly mark?: 'failed' | 'replied' | 'message';
}

/** The glyphs a wait earns, as the agents list words its state and mark. */
export function waitGlyphs(wait: TabWait): WaitGlyphs {
  const failure = wait.exited ? 'exited' : failureOf(wait);
  const state = wait.asking
    ? 'asking'
    : failure === 'exited' || failure === 'start'
      ? 'failed'
      : wait.working === undefined
        ? undefined
        : 'working';
  const mark =
    wait.unseen === undefined
      ? undefined
      : wait.unseen.kind === 'failed'
        ? failure === 'turn'
          ? 'failed'
          : undefined
        : wait.unseen.kind;

  return {
    ...(state === undefined ? {} : { state }),
    ...(mark === undefined ? {} : { mark }),
  };
}

/** The glyphs drawn, in order, state first. */
export function glyphsOf(glyphs: WaitGlyphs | undefined): WaitGlyph[] {
  return [glyphs?.state, glyphs?.mark].filter(
    (glyph): glyph is WaitGlyph => glyph !== undefined,
  );
}
