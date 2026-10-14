/**
 * How long something took, in the words the spinner, the agent list and a
 * monitor's end use alike.
 */

/** `12s`, `1m 5s`, `1h 2m`: the spinner's elapsed time. */
export function formatElapsed(ms: number): string {
  const seconds = Math.max(0, Math.floor(ms / 1000));

  if (seconds < 60) {
    return `${seconds}s`;
  }

  const minutes = Math.floor(seconds / 60);

  if (minutes < 60) {
    return `${minutes}m ${seconds % 60}s`;
  }

  return `${Math.floor(minutes / 60)}h ${minutes % 60}m`;
}
