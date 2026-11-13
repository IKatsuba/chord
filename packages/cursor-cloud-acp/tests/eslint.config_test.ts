import { expect, it } from 'bun:test';
import { fileURLToPath } from 'node:url';
import { ESLint } from 'eslint';

// The package's own rules over chord's shared ones: its source runs on
// Node and ships, so each snippet here is one its config must reject.
const here = fileURLToPath(new URL('..', import.meta.url));
const eslint = new ESLint({
  cwd: here,
  overrideConfigFile: `${here}/eslint.config.ts`,
});

const cases: [rule: string, code: string][] = [
  ['no-restricted-globals', 'export const v = Bun.version;\n'],
  ['no-restricted-syntax', "export { test } from 'bun:test';\n"],
  ['no-restricted-syntax', "export const b = await import('bun');\n"],
  ['no-restricted-syntax', "export { default } from '../steps.ts';\n"],
  [
    'no-restricted-syntax',
    "export const t = await import('../scripts/tools.ts');\n",
  ],
  // chord's shared rules hold here too.
  ['require-await', 'export async function f() {\n  return 1;\n}\n'],
];

for (const [rule, code] of cases) {
  it(`${rule}: ${code.split('\n')[0]}`, async () => {
    const [result] = await eslint.lintText(code, {
      filePath: `${here}/src/probe.ts`,
    });

    expect(result?.messages.map((message) => message.ruleId)).toContain(rule);
  });
}

it('its tests may use Bun', async () => {
  const [result] = await eslint.lintText(
    "import { test } from 'bun:test';\n\ntest('a', () => void Bun.version);\n",
    { filePath: `${here}/tests/probe_test.ts` },
  );

  expect(result?.messages).toEqual([]);
});
