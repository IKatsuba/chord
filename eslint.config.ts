import eslintComments from '@eslint-community/eslint-plugin-eslint-comments';
import js from '@eslint/js';
import react from 'eslint-plugin-react';
import reactHooks from 'eslint-plugin-react-hooks';
import type { ESLint } from 'eslint';
import { defineConfig } from 'eslint/config';
import tseslint from 'typescript-eslint';
import style from './lint/style.ts';

export default defineConfig(
  {
    ignores: ['dist/', 'npm/', 'docs/', '.claude/worktrees/'],
  },
  js.configs.recommended,
  tseslint.configs.recommended,
  {
    linterOptions: { reportUnusedDisableDirectives: 'error' },
    // react-hooks gives deno lint's react-rules-of-hooks alone: its
    // recommended set adds exhaustive-deps and the React Compiler's rules,
    // which the tree was never held to, so only its rules are taken: its
    // configs are typed in a way ESLint 10's Plugin does not accept.
    // eslint-plugin-react gives the rest of deno lint's jsx and react tags,
    // rule for rule.
    plugins: {
      'eslint-comments': eslintComments,
      react,
      'react-hooks': { rules: reactHooks.rules },
      // typescript-eslint 8 types a rule's nodes more narrowly than ESLint
      // 10's RuleModule does (docs/decisions.md, "The style plugin's cast").
      style: style as unknown as ESLint.Plugin,
    },
    settings: { react: { version: 'detect' } },
    rules: {
      'react-hooks/rules-of-hooks': 'error',
      'react/button-has-type': 'error',
      'react/jsx-boolean-value': 'error',
      'react/jsx-curly-brace-presence': 'error',
      'react/jsx-key': 'error',
      'react/jsx-no-comment-textnodes': 'error',
      'react/jsx-no-duplicate-props': 'error',
      'react/jsx-no-useless-fragment': 'error',
      'react/jsx-props-no-spread-multi': 'error',
      'react/no-children-prop': 'error',
      'react/no-danger': 'error',
      'react/no-danger-with-children': 'error',
      'react/no-unescaped-entities': 'error',
      'react/void-dom-elements-no-children': 'error',
      // deno lint's recommended rules that neither preset turns on, and that
      // tsc does not already report under this tsconfig.
      '@typescript-eslint/adjacent-overload-signatures': 'error',
      'eslint-comments/no-unlimited-disable': 'error',
      'no-inner-declarations': [
        'error',
        'functions',
        { blockScopedFunctions: 'disallow' },
      ],
      'no-restricted-globals': [
        'error',
        { name: 'window', message: 'Use globalThis.' },
      ],
      'no-restricted-syntax': [
        'error',
        {
          selector: 'TSEnumDeclaration[body.members.length=0]',
          message: 'An empty enum is `{}`: give it members or remove it.',
        },
        // deno lint's no-sloppy-imports: a relative import names its file.
        ...[
          'ImportDeclaration',
          'ExportNamedDeclaration',
          'ExportAllDeclaration',
          'ImportExpression',
        ].map((node) => ({
          selector: `${node} > Literal.source[value=/^\\.\\.?(\\/|$)/]:not([value=/\\.(tsx?|json)$/])`,
          message: 'A relative import names its file, extension included.',
        })),
      ],
      'no-unreachable': 'error',
      'require-await': 'error',
      // deno lint's rules beyond its recommended set, as the 2026-10-10
      // "Moving to Bun" entry in docs/decisions.md maps them.
      // deno lint's camelcase leaves property names and destructured names
      // alone: they are often the wire's own (`session_id`, `stop_reason`).
      camelcase: ['error', { properties: 'never', ignoreDestructuring: true }],
      curly: ['error', 'all'],
      eqeqeq: 'error',
      // Not in deno lint, and an AggregateError already carries the error it
      // gathers.
      'preserve-caught-error': 'off',
      'no-case-declarations': 'error',
      'no-eval': 'error',
      'no-throw-literal': 'error',
      'one-var': ['error', 'never'],
      '@typescript-eslint/no-inferrable-types': 'error',
      // deno lint's no-unused-vars lets a name that starts with `_` go unused.
      '@typescript-eslint/no-unused-vars': [
        'error',
        {
          argsIgnorePattern: '^_',
          varsIgnorePattern: '^_',
          caughtErrorsIgnorePattern: '^_',
          destructuredArrayIgnorePattern: '^_',
        },
      ],
      '@typescript-eslint/no-non-null-asserted-optional-chain': 'error',
      'style/imports-first': 'error',
      'style/blank-after-imports': 'error',
      'style/blank-before-exit': 'error',
      'style/blank-before-declaration': 'error',
      'style/blank-before-control-flow': 'error',
      'style/blank-after-declaration': 'error',
      'style/blank-after-block': 'error',
      'style/blank-around-assignment': 'error',
    },
  },
);
