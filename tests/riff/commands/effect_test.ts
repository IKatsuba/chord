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
