import { describe, it } from 'bun:test';
import { type Rule, RuleTester } from 'eslint';
import tseslint from 'typescript-eslint';
import plugin from './style.ts';

// RuleTester finds bun:test's describe and it on its own only as globals.
RuleTester.describe = describe;
RuleTester.it = it;

const tester = new RuleTester({ languageOptions: { parser: tseslint.parser } });

function run(
  name: keyof typeof plugin.rules,
  tests: Parameters<RuleTester['run']>[2],
): void {
  // typescript-eslint types a rule's nodes more narrowly than ESLint does.
  tester.run(name, plugin.rules[name] as unknown as Rule.RuleModule, tests);
}

run('imports-first', {
  valid: ["import a from './a.ts';\nimport b from './b.ts';\n\nfoo();\n"],
  invalid: [
    {
      code: "import a from './a.ts';\n\nfoo();\nimport b from './b.ts';\n",
      errors: 1,
    },
  ],
});

run('blank-after-imports', {
  valid: ["import a from './a.ts';\n\nfoo(a);\n"],
  invalid: [
    {
      code: "import a from './a.ts';\nfoo(a);\n",
      output: "import a from './a.ts';\n\nfoo(a);\n",
      errors: 1,
    },
  ],
});

run('blank-before-exit', {
  valid: [
    'function f() {\n  return 1;\n}\n',
    'function f() {\n  throw new Error();\n}\n',
  ],
  invalid: [
    {
      code: 'function f() {\n  g();\n  // why\n  return 1;\n}\n',
      output: 'function f() {\n  g();\n\n  // why\n  return 1;\n}\n',
      errors: 1,
    },
    {
      code: 'function f(x: number) {\n  switch (x) {\n    case 1:\n      g();\n      return 1;\n  }\n}\n',
      output:
        'function f(x: number) {\n  switch (x) {\n    case 1:\n      g();\n\n      return 1;\n  }\n}\n',
      errors: 1,
    },
    {
      code: 'function f() {\n  g();\n  throw new Error();\n}\n',
      output: 'function f() {\n  g();\n\n  throw new Error();\n}\n',
      errors: 1,
    },
  ],
});

run('blank-before-declaration', {
  valid: [
    'const a = 1;\nlet b = 2;\n',
    'for (let i = 0; i < 1; i++) {\n  g(i);\n}\n',
  ],
  invalid: [
    {
      code: 'function f() {}\nconst a = 1;\nfunction g() {}\n',
      output: 'function f() {}\n\nconst a = 1;\n\nfunction g() {}\n',
      errors: 2,
    },
    {
      code: 'g();\nconst a = 1;\nconst b = 2;\n',
      output: 'g();\n\nconst a = 1;\nconst b = 2;\n',
      errors: 1,
    },
    {
      code: 'g();\nexport const a = 1;\n',
      output: 'g();\n\nexport const a = 1;\n',
      errors: 1,
    },
  ],
});

run('blank-before-control-flow', {
  valid: [
    'function f(x: number) {\n  if (x) {\n    g();\n  } else if (x > 1) {\n    h();\n  }\n}\n',
  ],
  invalid: [
    {
      code: 'g();\nfor (const x of y) {\n  h(x);\n}\n',
      output: 'g();\n\nfor (const x of y) {\n  h(x);\n}\n',
      errors: 1,
    },
    {
      code: 'g();\nswitch (x) {\n}\ng();\ntry {\n  h();\n} catch {\n  i();\n}\ng();\nif (x) {\n  h();\n}\n',
      output:
        'g();\n\nswitch (x) {\n}\ng();\n\ntry {\n  h();\n} catch {\n  i();\n}\ng();\n\nif (x) {\n  h();\n}\n',
      errors: 3,
    },
  ],
});

run('blank-after-declaration', {
  valid: ['function f() {\n  const a = 1;\n  const b = 2;\n}\n'],
  invalid: [
    {
      code: 'function f() {\n  const a = 1;\n  g(a);\n}\n',
      output: 'function f() {\n  const a = 1;\n\n  g(a);\n}\n',
      errors: 1,
    },
    {
      code: 'const f = () => {\n  g();\n};\nh();\n',
      output: 'const f = () => {\n  g();\n};\n\nh();\n',
      errors: 1,
    },
  ],
});

run('blank-after-block', {
  valid: [
    'g({\n  a: 1,\n});\nh();\n',
    // A block-bodied variable is blank-after-declaration's.
    'const f = () => {\n  g();\n};\nh();\n',
  ],
  invalid: [
    {
      code: 'function f(x: boolean) {\n  if (x) {\n    g();\n  }\n  h();\n}\n',
      output:
        'function f(x: boolean) {\n  if (x) {\n    g();\n  }\n\n  h();\n}\n',
      errors: 1,
    },
    {
      code: 'o.m = function () {\n  g();\n};\nh();\n',
      output: 'o.m = function () {\n  g();\n};\n\nh();\n',
      errors: 1,
    },
    {
      code: "test('a', () => {\n  g();\n});\ntest('b', () => {});\n",
      output: "test('a', () => {\n  g();\n});\n\ntest('b', () => {});\n",
      errors: 1,
    },
  ],
});

run('blank-around-assignment', {
  valid: ['function f() {\n  g();\n\n  a = 1;\n  b.c = 2;\n\n  h();\n}\n'],
  invalid: [
    {
      code: 'function f() {\n  g();\n  a = 1;\n  b.c = 2;\n  h();\n}\n',
      output: 'function f() {\n  g();\n\n  a = 1;\n  b.c = 2;\n\n  h();\n}\n',
      errors: 2,
    },
  ],
});
