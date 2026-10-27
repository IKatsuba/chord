/** Fixed uncertainty survives bounded advisory reports, including projections. */
export const RESOURCE_CLEANUP_FAILED =
  'Resource collector cleanup failed; owned process exit is unverified.';
export const RESOURCE_SHUTDOWN_UNVERIFIED =
  'Collector shutdown could not be verified within its cleanup bound.';
export const RESOURCE_CACHE_CLEANUP_FAILED =
  'Resource cache cleanup could not be completed.';
export const AGENT_CLEANUP_UNVERIFIED =
  'An attempted agent cleanup could not be verified; process exit is uncertain.';
export const WARNINGS_OMITTED = 'Additional resource warnings are omitted.';

const lifecycle = [
  RESOURCE_CLEANUP_FAILED,
  RESOURCE_SHUTDOWN_UNVERIFIED,
  RESOURCE_CACHE_CLEANUP_FAILED,
  AGENT_CLEANUP_UNVERIFIED,
];

/** Required fixed diagnostics and cleanup uncertainty cannot be truncated. */
export function boundedWarnings(
  warnings: readonly string[],
  required: readonly string[] = [],
): string[] {
  const unique = [...new Set([...warnings, ...required])];

  if (unique.length <= 256) {
    return unique;
  }

  const tail = [
    ...new Set([
      WARNINGS_OMITTED,
      ...lifecycle.filter((warning) => unique.includes(warning)),
      ...required,
    ]),
  ];

  return [
    ...unique
      .filter((warning) => !tail.includes(warning))
      .slice(0, 256 - tail.length),
    ...tail,
  ];
}
