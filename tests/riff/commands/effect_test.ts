import { describe, expect, test } from 'bun:test';
import {
  commandEffect,
  knownReversibleAutoCommand,
} from '../../../src/riff/commands/effect.ts';
import { all } from './corpus.ts';

describe('fx command admission corpus', () => {
  test('contains the evidence table of 218 cases', () => {
    expect(all).toHaveLength(218);
  });

  for (const c of all) {
    test(`${c.fn}: ${c.command} (${c.source})`, () => {
      const result = commandEffect(c.command);
      const admitted =
        c.fn === 'reversible'
          ? knownReversibleAutoCommand(c.command)
          : c.fn === 'direct'
            ? result.kind === 'direct'
            : result.kind !== 'review';

      expect(admitted).toBe(c.expected === 'admit');
    });
  }
});

test('canonical direct argv and marked git stages', () => {
  expect(commandEffect('ls -la . | wc -lw')).toEqual({
    kind: 'direct',
    stages: [
      {
        executable: '/bin/ls',
        argv: ['/bin/ls', '-q', '-n', '-a', '--', '.'],
        git: false,
      },
      {
        executable: '/usr/bin/wc',
        argv: ['/usr/bin/wc', '-l', '-w'],
        git: false,
      },
    ],
  });
  expect(commandEffect('git log -n 2 -- src')).toEqual({
    kind: 'direct',
    stages: [
      {
        executable: '/usr/bin/git',
        argv: [
          '/usr/bin/git',
          'log',
          '--color=never',
          '--max-count=100',
          '-n',
          '2',
          '--',
          'src',
        ],
        git: true,
      },
    ],
  });
});

test('background, size, platform and chord stricter syntax', () => {
  expect(commandEffect('ls', { background: true }).kind).toBe('review');
  expect(commandEffect('ls', { platform: 'win32' }).kind).toBe('review');

  for (const s of [
    'npm run build\\test',
    'npm run =ls',
    'ls ' + 'a'.repeat(8192),
    'ls \0',
    'ls \ud800',
  ]) {
    expect(commandEffect(s).kind).toBe('review');
  }
});

test('quoted literal newlines keep direct argv without shell expansion', () => {
  const result = commandEffect("printf '%s' 'a\nb'");

  expect(result).toEqual({
    kind: 'direct',
    stages: [
      {
        executable: '/usr/bin/printf',
        argv: ['/usr/bin/printf', '%s', 'a\nb'],
        git: false,
      },
    ],
  });
  expect(commandEffect('ls\nREADME.md').kind).toBe('review');
});

test('git preparation precedes reversible fallback only after direct shell shape', () => {
  expect(commandEffect('git status --ignored')).toEqual({
    kind: 'reversible',
    prepareGit: true,
  });

  for (const command of [
    'git status 2>&1',
    'git status && npm test',
    'git fetch',
  ]) {
    expect(commandEffect(command)).toEqual({
      kind: 'reversible',
      prepareGit: false,
    });
  }
});

test.each([
  'printf x |\n wc -c',
  'printf x | #comment\n wc -c',
  'git status | # hidden comment\n wc -c',
  'git status --ignored #comment',
])('raw source gaps retain fx review: %s', (command) => {
  expect(commandEffect(command).kind).toBe('review');
});

describe('tester: command admission boundaries and bypass variants', () => {
  test.each([
    'npm install "2">&1',
    'npm install 2> &1',
    'npm install 2>&"1"',
    'npm install 2>&1 2>&1',
    '2>&1 npm install',
    'git status && npm test # hidden tail',
    'git fetch origin "ext::sh"',
    'git fetch --multiple origin "probe://host/repo"',
    'git fetch origin -- "probe.v2+x::payload"',
    'git fetch "--upload-pack=payload" origin',
    'git fetch --up=payload origin',
    'npm install "--global"',
    'npm install --prefix="target"',
    'npm install --location="global"',
    'bun test "x##"',
    'npm run "react@^18"',
    'npm run "$(printf build)"',
    'npm run =node',
    'printf x |\t# hidden stage\nwc -c',
    'printf x |\r\nwc -c',
    'printf x || wc -c',
    'printf x |& wc -c',
    'printf x | wc -c &',
  ])('reviews a bypass variant: %s', (command) => {
    expect(commandEffect(command).kind).toBe('review');
    expect(knownReversibleAutoCommand(command)).toBe(false);
  });

  test('a quoted separator remains a fetch operand, never another stage', () => {
    expect(commandEffect('git fetch "&&" node -v')).toEqual({
      kind: 'reversible',
      prepareGit: false,
    });
    expect(knownReversibleAutoCommand('git fetch "&&" node -v')).toBe(true);
    expect(commandEffect('git fetch "&&" git status --prune').kind).toBe(
      'review',
    );
  });

  test('limits command bytes rather than Unicode characters', () => {
    const command = 'ls ' + 'é'.repeat(4094) + 'a';

    expect(new TextEncoder().encode(command)).toHaveLength(8192);
    expect(commandEffect(command).kind).toBe('direct');
    expect(commandEffect(command + 'b').kind).toBe('review');
  });

  test.each(['ls --', 'git diff --', 'git log --'])(
    'bounds literal operands independently of their spelling: %s',
    (prefix) => {
      const operands = Array.from({ length: 64 }, (_, i) => `-file${i}`);
      const command = `${prefix} ${operands.join(' ')}`;
      const result = commandEffect(command);

      expect(result.kind).toBe('direct');

      if (result.kind === 'direct') {
        expect(result.stages[0]!.argv.slice(-64)).toEqual(operands);
      }

      expect(commandEffect(command + ' extra').kind).toBe('review');
    },
  );

  test('keeps quoted shell operators as literal direct operands', () => {
    expect(commandEffect("printf '%s' '$(touch sentinel);|>&#'")).toEqual({
      kind: 'direct',
      stages: [
        {
          executable: '/usr/bin/printf',
          argv: ['/usr/bin/printf', '%s', '$(touch sentinel);|>&#'],
          git: false,
        },
      ],
    });
  });
});
