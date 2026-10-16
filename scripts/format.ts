import { format, resolveConfig } from 'prettier';

/**
 * A generated module laid out by the tree's formatter, so what
 * `bun dev mark` and `bun dev registry` write is what the format check
 * accepts, and a test can compare the two.
 */
export async function formatModule(source: string): Promise<string> {
  const config = await resolveConfig(
    new URL('../src/main.tsx', import.meta.url),
  );

  return await format(source, { ...config, parser: 'typescript' });
}
