/**
 * The package's wiring: the command line's words to what serves them. Each
 * part lands with its unit (CHD-622); until then a word is refused.
 */

/** Runs the command `args` names and answers its exit status. */
export function main(args: readonly string[]): Promise<number> {
  process.stderr.write(
    `cursor-cloud-acp: ${args[0] ?? 'serving ACP'} is not built yet\n`,
  );

  return Promise.resolve(1);
}
