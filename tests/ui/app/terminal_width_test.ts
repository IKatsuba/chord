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

describe('CHD-561 tester: native width and inherited settings', () => {
  const cases = [
    [{}, 'unicode'],
    [{ OPENTUI_FORCE_WCWIDTH: '1' }, 'wcwidth'],
    [{ OPENTUI_FORCE_UNICODE: '1' }, 'unicode'],
    [{ OPENTUI_FORCE_WCWIDTH: '' }, 'wcwidth'],
    [{ OPENTUI_FORCE_UNICODE: '' }, 'unicode'],
  ] as const;

  for (const [settings, method] of cases) {
    test(`native ${JSON.stringify(settings)} selects ${method} and reaches shell and fake unchanged`, async () => {
      const rendererModule = new URL(
        '../../../src/ui/app/renderer.tsx',
        import.meta.url,
      ).href;
      const sessionModule = new URL(
        '../../../src/session/session.ts',
        import.meta.url,
      ).href;
      const shellModule = new URL('../../../src/shell.ts', import.meta.url)
        .href;
      const fakeModule = new URL(
        '../../fixtures/fake_agent/main.ts',
        import.meta.url,
      ).href;
      const code = `
        import { mkdtempSync, writeFileSync, readFileSync, rmSync } from 'node:fs';
        import { join } from 'node:path';
        import { tmpdir } from 'node:os';
        import { quote } from 'shell-quote';
        import { TextBuffer, TextBufferView } from '@opentui/core';
        import { openTerminal, leave } from ${JSON.stringify(rendererModule)};
        import { openSession } from ${JSON.stringify(sessionModule)};
        import { runShell } from ${JSON.stringify(shellModule)};
        const names = ['OPENTUI_FORCE_UNICODE', 'OPENTUI_FORCE_WCWIDTH', 'OTUI_STDOUT_THREAD'];
        const selected = () => Object.fromEntries(names.flatMap((name) => process.env[name] === undefined ? [] : [[name, process.env[name]]]));
        const dir = mkdtempSync(join(tmpdir(), 'chord-width-env-'));
        const { renderer } = await openTerminal({ mouse: false });
        try {
          const buffer = TextBuffer.create(renderer.widthMethod, renderer.nativeScene);
          const view = TextBufferView.create(buffer);
          const widths = [];
          try {
            for (const glyph of ['‼️', '☢️', '⚛️', '🖥️', '🗑️', '❤️']) {
              buffer.setText(glyph);
              widths.push(view.measureForDimensions(100, 1)?.widthColsMax);
            }
          } finally { view.destroy(); buffer.destroy(); }
          let shell = '';
          const emit = 'console.log(JSON.stringify(Object.fromEntries(' + JSON.stringify(names) + '.flatMap(n => process.env[n] === undefined ? [] : [[n,process.env[n]]]))))';
          const ran = runShell(quote([process.execPath, '-e', emit]), { cwd: dir, shell: ['/bin/sh', '-c'], onOutput: (stream, text) => { if (stream === 'stdout') shell += text; } });
          const ended = await ran.ended;
          const captured = join(dir, 'agent-env.json');
          const wrapper = join(dir, 'agent.ts');
          writeFileSync(wrapper, 'import {writeFileSync} from "node:fs"; writeFileSync(' + JSON.stringify(captured) + ', JSON.stringify(Object.fromEntries(' + JSON.stringify(names) + '.flatMap(n=>process.env[n]===undefined?[]:[[n,process.env[n]]])))); await import(' + JSON.stringify(${JSON.stringify(fakeModule)}) + ');');
          const session = await openSession({ agent: 'fake', cwd: dir, agentCommand: [process.execPath, wrapper] });
          try { await session.prompt('text').result; } finally { await session.close(); }
          process.stderr.write('WIDTH_NATIVE ' + JSON.stringify({
            method: renderer.widthMethod, widths, writer: renderer.nativeSession.stdoutWriter,
            parent: selected(), shell: JSON.parse(shell), ended,
            fake: JSON.parse(readFileSync(captured, 'utf8')),
          }) + '\\n');
        } finally { await leave(renderer); rmSync(dir, { recursive: true, force: true }); }
      `;
      const env = { ...process.env };

      for (const name of [
        'OPENTUI_FORCE_UNICODE',
        'OPENTUI_FORCE_WCWIDTH',
        'OTUI_STDOUT_THREAD',
        'ZELLIJ',
        'STY',
      ]) {
        delete env[name];
      }

      const ran = await promisify(execFile)(process.execPath, ['-e', code], {
        env: { ...env, TMUX: 'tester', OTUI_STDOUT_THREAD: '1', ...settings },
        timeout: 15_000,
      });
      const line = ran.stderr
        .split('\n')
        .find((row) => row.startsWith('WIDTH_NATIVE '));

      assert(line !== undefined, ran.stderr);

      const result = JSON.parse(line.slice('WIDTH_NATIVE '.length));
      const expected = { OTUI_STDOUT_THREAD: '1', ...settings };

      expect(result.method).toBe(method);
      expect(result.writer).toBe(false);
      expect(result.parent).toEqual(expected);
      expect(result.shell).toEqual(expected);
      expect(result.fake).toEqual(expected);
      expect(result.ended).toEqual({ code: 0 });

      if (method === 'unicode') {
        expect(result.widths).toEqual([2, 2, 2, 2, 2, 2]);
      }
    });
  }
});

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
