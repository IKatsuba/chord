/**
 * The glyphs an agent's wait is drawn with, in the agents list, the
 * background, the status line and teams (CHD-471).
 */

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
