/**
 * cursor-cloud-acp's steps (CHD-622, CHD-623): its checks for
 * `bun dev quality cursor-cloud-acp`, ESLint's argv for
 * `bun dev lint cursor-cloud-acp`, and its release's stages. Each reaches
 * this folder alone; chord's own leave it out.
 */
import type { PackageSteps } from '../../scripts/dev/steps.ts';

const bun = process.execPath;
const here = 'packages/cursor-cloud-acp';
// Loaded only when a step runs, so parsing any `bun dev` command loads no tooling.
const tools = () => import('./scripts/tools.ts');
const eslint = [
  bun,
  'run',
  'eslint',
  '--config',
  `${here}/eslint.config.ts`,
  here,
];

export default {
  checks: [
    { name: 'types', static: true, run: [bun, 'check', '-p', here] },
    {
      name: 'tooling types',
      static: true,
      run: [bun, 'check', '-p', `${here}/tsconfig.tools.json`],
    },
    {
      name: 'covered',
      static: true,
      run: [bun, 'scripts/dev/covered.ts', here],
    },
    { name: 'eslint', static: true, run: eslint },
    { name: 'format', static: true, run: [bun, 'fmt', '--check', here] },
    { name: 'tests', run: [bun, 'test', `./${here}/tests/`] },
    { name: 'build', run: async (context) => (await tools()).build(context) },
  ],
  lint: eslint,
  release: [
    {
      name: 'publish',
      npm: ['@chorded/cursor-cloud-acp'],
      tag: 'cursor-cloud-acp-v{version}',
    },
  ],
} satisfies PackageSteps;
