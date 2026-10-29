/**
 * How tall the layer over the transcript may be, its bottom edge on screen
 * row `edge`: every row from the window's top down to it (CHD-545).
 */
export function overlayRoom(edge: number): number {
  return Math.max(0, Math.trunc(edge));
}

/** The dim rule on top of a frameless list, across `width` cells. */
export function overlayRule(width: number): string {
  return '─'.repeat(Math.max(0, width));
}
