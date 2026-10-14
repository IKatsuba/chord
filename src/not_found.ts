/** Whether a file call failed because nothing is at the path it was given. */
export function notFound(error: unknown): boolean {
  return error instanceof Error && 'code' in error && error.code === 'ENOENT';
}
