import { describe, expect, test } from 'bun:test';
import assert from 'node:assert/strict';
import { execFile } from 'node:child_process';
import { promisify } from 'node:util';
import type { CliRenderer, ProgramStatus } from '@opentui/core';
import { useRenderer } from '@opentui/react';
import { createElement } from 'react';
import { closeOnForcedExit } from '../../../src/session/leaving.ts';
import {
  dieBySignal,
  leave,
  useApp,
  useProgramStatus,
} from '../../../src/ui/app/renderer.tsx';
import { draw } from '../harness.tsx';
import { statusReports, until } from './render.tsx';

describe('CHD-561 tester: terminal stdout thread policy', () => {
  test('a CLI value named --delay-start cannot enable the writer during delayed creation', async () => {
    const rendererModule = new URL(
      '../../../src/ui/app/renderer.tsx',
      import.meta.url,
    ).href;
    const cliModule = new URL('../../../src/cli.ts', import.meta.url).href;
    const code = `
      import { chordCommand } from ${JSON.stringify(cliModule)};
      import { openTerminal, leave } from ${JSON.stringify(rendererModule)};
      await chordCommand().noExit().throwErrors().action(() => {}).parse(['fake', '--model', '--delay-start']);
      const before = performance.now();
      const { renderer } = await openTerminal({ mouse: false });
      try {
        process.stderr.write('DELAY_POLICY ' + JSON.stringify({
          delayed: performance.now() - before >= 4900,
          writer: renderer.nativeSession.stdoutWriter,
          setting: process.env.OTUI_STDOUT_THREAD,
        }) + '\\n');
      } finally { await leave(renderer); }
    `;
    const ran = await promisify(execFile)(
      process.execPath,
      ['-e', code, '--', 'fake', '--model', '--delay-start'],
      {
        env: { ...process.env, OTUI_STDOUT_THREAD: '1' },
        timeout: 15_000,
      },
    );
    const line = ran.stderr
      .split('\n')
      .find((row) => row.startsWith('DELAY_POLICY '));

    assert(line !== undefined, ran.stderr);
    expect(JSON.parse(line.slice('DELAY_POLICY '.length))).toEqual({
      delayed: true,
      writer: false,
      setting: '1',
    });
  });

  test('opening chord disables the native writer even when the environment enables it', async () => {
    const rendererModule = new URL(
      '../../../src/ui/app/renderer.tsx',
      import.meta.url,
    ).href;
    const code = `
      import { NativeSession } from '@opentui/core';
      import { openTerminal, leave } from ${JSON.stringify(rendererModule)};
      const baseline = new NativeSession(process.stdout);
      const defaultWriter = baseline.stdoutWriter;
      await baseline.close();
      const { renderer } = await openTerminal({ mouse: false });
      try {
        process.stderr.write('THREAD_POLICY ' + JSON.stringify({
          defaultWriter,
          writer: renderer.nativeSession.stdoutWriter,
          setting: process.env.OTUI_STDOUT_THREAD,
        }) + '\\n');
      } finally {
        await leave(renderer);
      }
    `;
    const ran = await promisify(execFile)(process.execPath, ['-e', code], {
      env: { ...process.env, OTUI_STDOUT_THREAD: '1' },
      timeout: 15_000,
    });
    const line = ran.stderr
      .split('\n')
      .find((row) => row.startsWith('THREAD_POLICY '));

    assert(line !== undefined, ran.stderr);
    expect(JSON.parse(line.slice('THREAD_POLICY '.length))).toEqual({
      defaultWriter: true,
      writer: false,
      setting: '1',
    });
  });
});

describe('CHD-382 U2 tester: status while the editor owns the terminal', () => {
  for (const rejects of [false, true]) {
    test(`only the latest status returns after an editor that ${rejects ? 'rejects' : 'resolves'}`, async () => {
      const log: string[] = [];
      let report!: (status: ProgramStatus) => void;
      let suspend!: ReturnType<typeof useApp>['suspendTerminal'];

      const Grab = () => {
        report = useProgramStatus();
        suspend = useApp().suspendTerminal;

        return createElement('text', null, 'editor lifecycle');
      };

      const drawn = await draw(createElement(Grab), {}, { log });
      const release = Promise.withResolvers<void>();
      const entered = Promise.withResolvers<void>();

      try {
        report({ state: 'working', app: 'chord' });

        const away = suspend(async () => {
          entered.resolve();
          await release.promise;
        });

        // Attach the rejection handler before letting the editor fail.
        const settled = away.then(
          () => 'resolved',
          () => 'rejected',
        );

        await entered.promise;

        const before = statusReports(log);

        expect(before.at(-1)).toStrictEqual({ state: 'clear' });
        report({ state: 'done', app: 'chord', message: 'old reply' });
        report({ state: 'error', app: 'chord', message: 'latest failure' });
        expect(statusReports(log)).toStrictEqual(before);

        if (rejects) {
          release.reject(new Error('editor failed'));
        } else {
          release.resolve();
        }

        expect(await settled).toBe(rejects ? 'rejected' : 'resolved');
        await until(
          'the latest status to return',
          () => statusReports(log).at(-1)?.state === 'error',
        );
        expect(statusReports(log).slice(before.length)).toStrictEqual([
          { state: 'error', app: 'chord', msg: 'latest failure' },
        ]);
        report({ state: 'error', app: 'chord', message: 'latest failure' });
        expect(statusReports(log).length).toBe(before.length + 1);
      } finally {
        release.resolve();
        await drawn.unmount();
      }
    });
  }
});

test('a forced exit waits for every close still asked for, a failed one too, and forgets them (CHD-331)', async () => {
  const closed: string[] = [];
  const slow = Promise.withResolvers<void>();

  closeOnForcedExit(async () => {
    await slow.promise;
    closed.push('slow');
  });

  closeOnForcedExit(() => Promise.reject(new Error('did not exit')));
  closeOnForcedExit(() => {
    closed.push('forgotten');

    return Promise.resolve();
  })();

  let left = false;
  const leaving = leave(undefined).then(() => (left = true));

  await Promise.resolve();
  expect(left).toBe(false);

  slow.resolve();
  await leaving;

  expect(closed).toEqual(['slow']);

  await leave(undefined);
  expect(closed).toEqual(['slow']);
});

test('a second forced exit waits for the closes the first one started (CHD-331)', async () => {
  const slow = Promise.withResolvers<void>();
  let closes = 0;

  closeOnForcedExit(async () => {
    closes += 1;

    await slow.promise;
  });

  const left: string[] = [];
  const first = leave(undefined).then(() => left.push('first'));
  const second = leave(undefined).then(() => left.push('second'));

  await new Promise((resolve) => setTimeout(resolve, 0));
  expect(left).toEqual([]);

  slow.resolve();
  await Promise.all([first, second]);

  expect(left.sort()).toEqual(['first', 'second']);
  expect(closes).toBe(1);
});

test('a signal during a forced exit is held until the closes settle, then the first is raised (CHD-331)', async () => {
  const slow = Promise.withResolvers<void>();
  const raised: NodeJS.Signals[] = [];
  const hup = process.listenerCount('SIGHUP');

  closeOnForcedExit(() => slow.promise);

  const off = dieBySignal((signal) => raised.push(signal));

  try {
    process.emit('SIGTERM');
    await new Promise((resolve) => setTimeout(resolve, 0));
    process.emit('SIGHUP');
    await new Promise((resolve) => setTimeout(resolve, 0));

    expect(raised).toEqual([]);
    expect(process.listenerCount('SIGHUP')).toBe(hup + 1);

    slow.resolve();
    await until('the first signal raised', () => raised.length > 0);

    expect(raised).toEqual(['SIGTERM']);
    expect(process.listenerCount('SIGHUP')).toBe(hup);
  } finally {
    slow.resolve();
    off();
  }
});

test("a forced exit clears chord's status before it gives the terminal back (CHD-382)", async () => {
  const log: string[] = [];
  let renderer: CliRenderer | undefined;
  const Grab = () => {
    renderer = useRenderer();

    return createElement('text', null, 'hi');
  };

  const drawn = await draw(createElement(Grab), {}, { log });

  renderer!.setProgramStatus({ state: 'working', app: 'chord' });
  await renderer!.idle();
  await leave(renderer);

  const written = log.join('');
  const clear = written.lastIndexOf('\x1b]7501;state=clear');

  expect(statusReports(log).at(-1)).toStrictEqual({ state: 'clear' });
  // Ahead of the alternate screen's end, which gives the terminal back.
  expect(clear).toBeGreaterThan(-1);
  expect(clear).toBeLessThan(written.lastIndexOf('\x1b[?1049l'));
  // Once destroyed, the renderer takes no report.
  expect(renderer!.setProgramStatus({ state: 'idle' })).toBe(false);
  await drawn.unmount();
});

/** The mouse modes a terminal was told to turn on, in the order told. */
async function mouseModes(mouse: boolean): Promise<string[]> {
  const log: string[] = [];
  const drawn = await draw(
    createElement('text', null, 'hi'),
    {},
    {
      log,
      mouse,
    },
  );

  await drawn.unmount();

  return log
    .join('')
    .split('\x1b[?')
    .slice(1)
    .flatMap((mode) => /^(100[0-6])h/.exec(mode)?.[1] ?? []);
}

test('the mouse is asked for with 1000, 1002 and 1006, no hover motion (CHD-172)', async () => {
  expect(new Set(await mouseModes(true))).toStrictEqual(
    new Set(['1000', '1002', '1006']),
  );
});

test('"mouse": false asks for no mouse mode (CHD-172)', async () => {
  expect(await mouseModes(false)).toStrictEqual([]);
});

describe('tester: mouse mode restoration', () => {
  test('destroy disables each requested mouse mode', async () => {
    const log: string[] = [];
    const drawn = await draw(createElement('text', null, 'inert'), {}, { log });

    await drawn.unmount();

    const written = log.join('');

    for (const mode of ['1000', '1002', '1006']) {
      expect(written).toContain(`\x1b[?${mode}h`);
      expect(written.lastIndexOf(`\x1b[?${mode}l`)).toBeGreaterThan(
        written.lastIndexOf(`\x1b[?${mode}h`),
      );
    }

    expect(written).not.toContain('\x1b[?1003h');
  });
});

describe('what the processes chord starts inherit of the stdout thread setting', () => {
  test.each([
    [{}, 'OTUI_STDOUT_THREAD', undefined],
    [{ OTUI_STDOUT_THREAD: '1' }, 'OTUI_STDOUT_THREAD', '1'],
  ])('under %j, %s stays %s, with the thread off', async (env, name, kept) => {
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
    const line = ran.stderr.split('\n').find((row) => row.startsWith('CHILD '));

    assert(line !== undefined, ran.stderr);

    const { child, writer } = JSON.parse(line.slice('CHILD '.length)) as {
      child: Record<string, string>;
      writer: boolean;
    };

    expect(child[name]).toBe(kept as never);
    expect(writer).toBe(false);
  });
});

describe('CHD-624 U1b tester: native width settings stay with OpenTUI', () => {
  const cases = [
    [{}, undefined],
    [{ OPENTUI_FORCE_WCWIDTH: '1' }, 'wcwidth'],
    [{ OPENTUI_FORCE_UNICODE: '1' }, 'unicode'],
    [{ OPENTUI_FORCE_WCWIDTH: '' }, 'wcwidth'],
    [{ OPENTUI_FORCE_UNICODE: '' }, 'unicode'],
  ] as const;

  for (const [settings, method] of cases) {
    test(`native ${JSON.stringify(settings)} selects ${method ?? 'the library default'} and reaches shell and fake unchanged`, async () => {
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

      if (method !== undefined) {
        expect(result.method).toBe(method);
      }

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
