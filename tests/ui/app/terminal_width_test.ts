import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import {
  rendererEnvironment,
  seesTmux,
} from '../../../src/ui/app/terminal_width.ts';

const of =
  (env: Record<string, string>) =>
  (name: string): string | undefined =>
    env[name];

describe('tmux as OpenTUI itself takes it', () => {
  test.each([
    [{ TMUX: '/tmp/tmux-1/default,1,0' }, true],
    [{ TMUX: '' }, true],
    [{ TMUX: 'x', ZELLIJ: '0' }, true],
    [{ TERM: 'tmux-256color' }, true],
    [{ TERM: 'tmux-256color', ZELLIJ: '0' }, false],
    [{ TERM: 'tmux-256color', ZELLIJ_SESSION_NAME: 'a' }, false],
    [{ TERM: 'tmux-256color', ZELLIJ_PANE_ID: '1' }, false],
    [{ TERM: 'tmux-256color', STY: '1.a' }, false],
    [{ TERM_PROGRAM: 'tmux' }, true],
    [{ TERM_PROGRAM: 'tmux', STY: '1.a' }, true],
    [{ TERM_PROGRAM: 'tmux', ZELLIJ: '0' }, false],
    [{ TERM: 'xterm-256color', TERM_PROGRAM: 'ghostty' }, false],
    [{ TERM: 'screen-256color' }, false],
    [{}, false],
  ] as const)('%j is %j', (env, seen) => {
    expect(seesTmux(of(env))).toBe(seen);
  });
});

describe('the width setting chord hands the renderer', () => {
  test('tmux seen sets it; not seen leaves it unset', () => {
    expect(rendererEnvironment(of({ TMUX: 'x' }))).toStrictEqual({
      OPENTUI_FORCE_UNICODE: '1',
    });
    expect(rendererEnvironment(of({ TERM: 'xterm' }))).toStrictEqual({});
  });

  test.each(['OPENTUI_FORCE_WCWIDTH', 'OPENTUI_FORCE_UNICODE'])(
    "a person's %s wins, whatever its value",
    (name) => {
      expect(rendererEnvironment(of({ TMUX: 'x', [name]: '' }))).toStrictEqual(
        {},
      );
    },
  );
});

describe('what the processes chord starts inherit', () => {
  test.each([
    [{ TMUX: 'x' }, 'OTUI_STDOUT_THREAD', undefined],
    [{ TMUX: 'x', OTUI_STDOUT_THREAD: '1' }, 'OTUI_STDOUT_THREAD', '1'],
    [{ TMUX: 'x' }, 'OPENTUI_FORCE_UNICODE', undefined],
  ])(
    'under %j, %s stays %s, with the thread off and the width told',
    async (env, name, kept) => {
      const rendererModule = new URL(
        '../../../src/ui/app/renderer.tsx',
        import.meta.url,
      ).href;
      const code = `
      import { spawnSync } from 'node:child_process';
      import { openTerminal, leave } from ${JSON.stringify(rendererModule)};
      const { renderer } = await openTerminal({ mouse: false });
      try {
        const child = spawnSync(process.execPath, ['-e', 'console.log(JSON.stringify(process.env))'], { encoding: 'utf8' });
        process.stderr.write('CHILD ' + JSON.stringify({
          child: JSON.parse(child.stdout),
          writer: renderer.nativeSession.stdoutWriter,
        }) + '\\n');
      } finally {
        await leave(renderer);
      }
    `;
      const {
        OPENTUI_FORCE_UNICODE: _,
        OPENTUI_FORCE_WCWIDTH: __,
        OTUI_STDOUT_THREAD: ___,
        ...parent
      } = process.env;
      const ran = await promisify(execFile)(process.execPath, ['-e', code], {
        env: { ...parent, ...env },
        timeout: 15_000,
      });
      const line = ran.stderr
        .split('\n')
        .find((row) => row.startsWith('CHILD '));

      assert(line !== undefined, ran.stderr);

      const { child, writer } = JSON.parse(line.slice('CHILD '.length)) as {
        child: Record<string, string>;
        writer: boolean;
      };

      expect(child[name]).toBe(kept as never);
      expect(writer).toBe(false);
    },
  );
});
