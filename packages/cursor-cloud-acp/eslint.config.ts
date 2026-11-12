import { defineConfig } from 'eslint/config';
import { forbid, shared, TOOLING } from '../../eslint.config.ts';

const basePath = import.meta.dirname;
const NODE = 'The package runs on Node, not Bun.';

// Its source runs on Node under npx, not on Bun: it reaches no Bun global,
// no `bun:` module and none of the repository's tooling (CHD-622). Its
// tests, fixture and tooling run on Bun.
export default defineConfig(
  { basePath, ignores: ['dist/'] },
  shared,
  {
    basePath,
    ...forbid(['src/**'], [TOOLING, { source: '^bun(:|$)', message: NODE }]),
  },
  {
    basePath,
    files: ['src/**'],
    rules: {
      'no-restricted-globals': [
        'error',
        { name: 'window', message: 'Use globalThis.' },
        { name: 'Bun', message: NODE },
      ],
    },
  },
);
