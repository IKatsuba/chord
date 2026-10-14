import { expect, it } from 'bun:test';
import { ESLint } from 'eslint';

// deno lint held the tree to these before ESLint took over from it; each
// snippet is one that deno lint rejected, so a rule that drops out of
// eslint.config.ts fails here rather than going quiet.
const eslint = new ESLint();

const cases: [rule: string, code: string, file?: string][] = [
  ['require-await', 'export async function f() {\n  return 1;\n}\n'],
  ['no-unreachable', 'export function f() {\n  return 1;\n  f();\n}\n'],
  [
    'no-inner-declarations',
    'export function f(c: boolean) {\n  if (c) {\n    function g() {}\n\n    g();\n  }\n}\n',
  ],
  ['no-restricted-globals', 'export const w = window;\n'],
  ['no-restricted-syntax', 'export enum E {}\n'],
  ['no-restricted-syntax', "export { a } from './a';\n"],
  ['no-restricted-syntax', "export const a = await import('./a.js');\n"],
  [
    '@typescript-eslint/adjacent-overload-signatures',
    'export function g(a: string): void;\nexport const b = 1;\nexport function g(a: number): void;\nexport function g(_a: unknown) {}\n',
  ],
  [
    'eslint-comments/no-unlimited-disable',
    '// eslint-disable-next-line\nexport const a = 1;\n',
  ],
  // ESLint reports an unused directive without a rule id.
  ['', '// eslint-disable-next-line no-eval\nexport const a = 1;\n'],
  [
    'react/jsx-key',
    'export const rows = [1, 2].map((value) => <span>{value}</span>);\n',
    'probe.tsx',
  ],
  [
    'react/jsx-boolean-value',
    'export const a = <input disabled={true} />;\n',
    'probe.tsx',
  ],
  [
    'react/jsx-curly-brace-presence',
    "export const a = <span>{'x'}</span>;\n",
    'probe.tsx',
  ],
  [
    'react/jsx-no-duplicate-props',
    "export const a = <span id='a' id='b' />;\n",
    'probe.tsx',
  ],
  [
    'react/jsx-props-no-spread-multi',
    'export const a = (p: object) => <span {...p} {...p} />;\n',
    'probe.tsx',
  ],
  [
    'react/no-unescaped-entities',
    "export const a = <span>it's</span>;\n",
    'probe.tsx',
  ],
  [
    'react/jsx-no-useless-fragment',
    'export const a = <>{1}</>;\n',
    'probe.tsx',
  ],
  [
    'react/no-children-prop',
    'export const a = <span children={1} />;\n',
    'probe.tsx',
  ],
  [
    'react/jsx-no-comment-textnodes',
    'export const a = <span>// no</span>;\n',
    'probe.tsx',
  ],
  ['react/button-has-type', 'export const a = <button />;\n', 'probe.tsx'],
  [
    'react/void-dom-elements-no-children',
    'export const a = <br>x</br>;\n',
    'probe.tsx',
  ],
  [
    'react/no-danger',
    "export const a = <span dangerouslySetInnerHTML={{ __html: '' }} />;\n",
    'probe.tsx',
  ],
  [
    'react/no-danger-with-children',
    "export const a = (\n  <span dangerouslySetInnerHTML={{ __html: '' }}>x</span>\n);\n",
    'probe.tsx',
  ],
  [
    'react-hooks/rules-of-hooks',
    "import { useState } from 'react';\n\nexport function f(c: boolean) {\n  if (c) {\n    useState(0);\n  }\n}\n",
  ],
];

for (const [rule, code, file = 'probe.ts'] of cases) {
  it(`${rule || 'unused directive'}: ${code.split('\n')[0]}`, async () => {
    const [result] = await eslint.lintText(code, { filePath: `src/${file}` });
    const rules = result?.messages.map((message) => message.ruleId ?? '');

    expect(rules).toContain(rule);
  });
}
