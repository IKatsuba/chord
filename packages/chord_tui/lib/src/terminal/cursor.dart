/// The terminal's cursor shape and blink policy (DECSCUSR).
enum CursorStyle {
  /// A blinking block.
  blinkingBlock,

  /// A steady block.
  steadyBlock,

  /// A blinking underline.
  blinkingUnderline,

  /// A steady underline.
  steadyUnderline,

  /// A blinking vertical bar.
  blinkingBar,

  /// A steady vertical bar.
  steadyBar,
}
