import { expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import {
  existsSync,
  mkdirSync,
  mkdtempSync,
  readFileSync,
  rmSync,
  writeFileSync,
} from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import { quote } from 'shell-quote';
import { until } from './ui/app/render.tsx';
import { fakeAgentCommand } from './fixtures/fake.ts';

for (const choose of [false, true]) {
  test(`CHD-532 actual handler keeps all startup factories behind choice, choose=${choose}`, () => {
    const place = mkdtempSync(join(tmpdir(), 'chord-start-boundary-'));
    const project = join(place, 'project');
    const settings = join(project, '.chord', 'settings.json');
    const content = JSON.stringify({
      agent: 'unknown-unselected-default',
      agents: { fixture: { command: fakeAgentCommand() } },
    });

    mkdirSync(join(project, '.chord'), { recursive: true });
    writeFileSync(settings, content);

    try {
      const ran = spawnSync(
        process.execPath,
        [
          fileURLToPath(
            new URL('./fixtures/startup_boundary.tsx', import.meta.url),
          ),
          ...(choose ? ['--choose'] : []),
        ],
        {
          env: {
            ...process.env,
            XDG_CONFIG_HOME: join(place, 'config'),
            XDG_STATE_HOME: join(place, 'state'),
            CHORD_RESOURCE_FIXTURE: 'true',
            CHORD_START_PROJECT: project,
          },
          encoding: 'utf8',
          timeout: 15_000,
        },
      );

      expect(ran.status, ran.stderr).toBe(0);
      expect(JSON.parse(ran.stdout.trim())).toEqual({
        session: 0,
        server: 0,
        resources: 0,
        copier: choose ? 1 : 0,
      });
      expect(readFileSync(settings, 'utf8')).toBe(content);
    } finally {
      rmSync(place, { recursive: true, force: true });
    }
  });
}

for (const mode of [
  'select',
  'cancel',
  'explicit',
  'model',
  'catalog',
  'refused',
  'missing',
] as const) {
  test(`CHD-532 actual fake CLI ${mode} uses the intended startup route`, async () => {
    const place = `/tmp/chord-qa.chd532-cli-${process.pid}-${mode}`;
    const socket = `chd532-${process.pid}-${mode}`;
    const project = join(place, 'project');
    const log = join(place, 'starts');
    const settings = join(project, '.chord', 'settings.json');
    const command = [
      process.execPath,
      fileURLToPath(new URL('./fixtures/startup_agent.ts', import.meta.url)),
    ];
    const preferred =
      mode === 'refused' || mode === 'catalog'
        ? 'claude'
        : mode === 'missing'
          ? 'fx'
          : 'fixture';
    const stopped = mode === 'refused' || mode === 'missing';
    const content = JSON.stringify({
      agent: mode === 'cancel' ? 'unknown-unselected-default' : preferred,
      mouse: false,
      agents: {
        fixture: { command, model: 'fake-small' },
        ...(mode === 'refused'
          ? { claude: { command: 7 } }
          : mode === 'catalog'
            ? { claude: { command, model: 'fake-small' } }
            : {}),
      },
    });

    rmSync(place, { recursive: true, force: true });
    mkdirSync(join(project, '.chord'), { recursive: true });
    writeFileSync(settings, content);

    const env = {
      ...process.env,
      XDG_CONFIG_HOME: join(place, 'config'),
      XDG_STATE_HOME: join(place, 'state'),
      CHORD_RESOURCE_FIXTURE: 'true',
      CHORD_START_LOG: log,
    };
    const tmux = (...args: string[]) =>
      spawnSync('tmux', ['-L', socket, ...args], { env, encoding: 'utf8' });
    const frame = () => tmux('capture-pane', '-t', 'picker', '-p').stdout;
    const starts = () =>
      existsSync(log)
        ? readFileSync(log, 'utf8')
            .trim()
            .split('\n')
            .filter(Boolean)
            .map(Number)
        : [];

    try {
      const opened = tmux(
        'new-session',
        '-d',
        '-s',
        'picker',
        '-x',
        '80',
        '-y',
        '24',
        quote([
          ...(mode === 'missing'
            ? ['/usr/bin/env', `PATH=${join(place, 'empty')}`]
            : []),
          ...(process.env['CHORD_START_BINARY']
            ? [process.env['CHORD_START_BINARY']!]
            : [
                process.execPath,
                fileURLToPath(new URL('../src/main.tsx', import.meta.url)),
              ]),
          ...(mode === 'explicit' ? ['fixture'] : []),
          ...(mode === 'model' ? ['--model', 'fake-large'] : []),
          '-C',
          project,
        ]),
      );

      expect(opened.status, opened.stderr).toBe(0);
      expect(
        tmux('set-option', '-t', 'picker', 'remain-on-exit', 'on').status,
      ).toBe(0);

      if (mode !== 'explicit') {
        await until('actual unnamed startup picker', () =>
          frame().includes('Select agent'),
        );
        expect(starts()).toEqual([]);
        expect(frame()).not.toContain('Fake Small');

        if (mode === 'cancel') {
          tmux('send-keys', '-t', 'picker', 'Escape');
          await until(
            'cancelled startup exits',
            () =>
              tmux(
                'display-message',
                '-p',
                '-t',
                'picker',
                '#{pane_dead}',
              ).stdout.trim() === '1',
          );
          expect(
            tmux(
              'display-message',
              '-p',
              '-t',
              'picker',
              '#{pane_dead_status}',
            ).stdout.trim(),
          ).toBe('0');
          expect(starts()).toEqual([]);
        } else {
          expect(
            frame()
              .split('\n')
              .find((line) => line.includes('❯')),
          ).toContain(preferred);
          tmux('send-keys', '-t', 'picker', 'Enter');
        }
      }

      if (stopped) {
        await until(
          'selected unavailable agent refuses',
          () =>
            tmux(
              'display-message',
              '-p',
              '-t',
              'picker',
              '#{pane_dead}',
            ).stdout.trim() === '1',
        );
        expect(
          tmux(
            'display-message',
            '-p',
            '-t',
            'picker',
            '#{pane_dead_status}',
          ).stdout.trim(),
        ).toBe('1');
        expect(frame()).toContain(
          mode === 'missing' ? 'which is not on PATH' : 'expected a string',
        );
        expect(starts()).toEqual([]);
      }

      if (mode !== 'cancel' && !stopped) {
        await until('selected fake agent is ready', () =>
          frame().includes(mode === 'model' ? 'Fake Large' : 'Fake Small'),
        );
        expect(starts()).toHaveLength(1);
        expect(frame()).not.toContain('Select agent');
        tmux('send-keys', '-t', 'picker', '-l', 'text');
        tmux('send-keys', '-t', 'picker', 'Enter');
        await until('selected fake agent answers', () =>
          frame().includes('Hello, world.'),
        );
        tmux('send-keys', '-t', 'picker', 'C-c', 'C-c');
        await until(
          'fake CLI quits',
          () =>
            tmux(
              'display-message',
              '-p',
              '-t',
              'picker',
              '#{pane_dead}',
            ).stdout.trim() === '1',
        );
      }

      expect(readFileSync(settings, 'utf8')).toBe(content);
    } finally {
      tmux('kill-server');

      for (const pid of starts()) {
        await until(`fake process ${pid} exited`, () => {
          try {
            process.kill(pid, 0);

            return false;
          } catch {
            return true;
          }
        });
      }

      rmSync(place, { recursive: true, force: true });
    }
  });
}
