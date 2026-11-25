/// The glyphs an agent's wait is drawn with, in the agents list, the
/// background, the status line and teams. From the original's
/// `ui/agents/glyphs.ts`.
library;

/// What an agent's wait shows: its state, then what is not yet seen, each
/// with the glyph it is marked by.
enum WaitGlyph {
  /// A permission or form open.
  asking('●'),

  /// Gone, or a turn that failed.
  failed('✗'),

  /// A reply not yet seen.
  replied('✓'),

  /// A turn running; it stands still, as a spinner here would not.
  working('✻'),

  /// A message from another agent not yet seen.
  message('←');

  const WaitGlyph(this.glyph);

  /// The glyph drawn for it.
  final String glyph;
}
