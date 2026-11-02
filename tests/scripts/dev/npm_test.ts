import { describe, expect, test } from 'bun:test';
import { execFile } from 'node:child_process';
import { existsSync } from 'node:fs';
import {
  copyFile,
  mkdir,
  mkdtemp,
  readFile,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { promisify } from 'node:util';
import { NATIVE_NOTICES } from '../../../scripts/dev/npm.ts';
import { loadedNative } from '../../../scripts/dev/compile.ts';
import { TARGETS } from '../../../scripts/targets.ts';

test('the native library a binary embeds carries every notice its npm package passes on', () => {
  const native = join(
    'node_modules',
    loadedNative(process.platform, process.arch, process.env['OPENTUI_LIBC']),
  );

  for (const notice of NATIVE_NOTICES) {
    expect(existsSync(join(native, notice))).toBe(true);
  }
});

describe('CHD-561 tester: native notices survive npm layout and packing', () => {
  test('each platform archive carries its own notices and explicitly includes them', async () => {
    const root = await mkdtemp(join(tmpdir(), 'chord-npm-notices-'));
    const run = promisify(execFile);
    const notices = ['LICENSE-FFMPEG', 'LICENSE-ZLIB', 'FFMPEG-SOURCE.md'];
    const env = {
      ...process.env,
      HOME: root,
      npm_config_cache: join(root, 'cache'),
      npm_config_userconfig: join(root, 'npmrc'),
      npm_config_update_notifier: 'false',
    };

    try {
      await mkdir(join(root, 'scripts', 'dev'), { recursive: true });
      await mkdir(join(root, 'archives'));
      await writeFile(
        join(root, 'package.json'),
        JSON.stringify({ version: '9.9.9' }),
      );
      await writeFile(join(root, 'LICENSE'), 'Fixture chord licence\n');
      await writeFile(join(root, 'README.md'), 'Fixture readme\n');
      await copyFile(
        new URL('../../../scripts/dev/npm.ts', import.meta.url),
        join(root, 'scripts', 'dev', 'npm.ts'),
      );
      await symlink(
        new URL('../../../scripts/dev/compile.ts', import.meta.url).pathname,
        join(root, 'scripts', 'dev', 'compile.ts'),
      );
      await symlink(
        new URL('../../../scripts/targets.ts', import.meta.url).pathname,
        join(root, 'scripts', 'targets.ts'),
      );
      await writeFile(
        join(root, 'scripts', 'dev', 'run.ts'),
        "import { npm } from './npm.ts';\nawait npm();\n",
      );

      for (const target of TARGETS) {
        const native = join(
          root,
          'node_modules',
          loadedNative(target.os, target.cpu, undefined),
        );

        await mkdir(native, { recursive: true });
        await mkdir(join(root, 'dist', target.bun), { recursive: true });
        await writeFile(
          join(root, 'dist', target.bun, 'chord'),
          `fixture ${target.bun}\n`,
        );

        for (const notice of notices) {
          await writeFile(join(native, notice), `${target.bun}: ${notice}\n`);
        }
      }

      await run(process.execPath, [join(root, 'scripts', 'dev', 'run.ts')], {
        cwd: root,
        env,
      });

      for (const target of TARGETS) {
        const name = `chord-${target.os}-${target.cpu}`;
        const dir = join(root, 'npm', name);
        const manifest = JSON.parse(
          await readFile(join(dir, 'package.json'), 'utf8'),
        ) as { files: string[] };

        for (const notice of notices) {
          expect(manifest.files).toContain(notice);
          expect(await readFile(join(dir, notice), 'utf8')).toBe(
            `${target.bun}: ${notice}\n`,
          );
        }

        const packed = await run(
          'npm',
          [
            'pack',
            '--offline',
            '--ignore-scripts',
            '--json',
            '--pack-destination',
            join(root, 'archives'),
          ],
          { cwd: dir, env },
        );
        const report = JSON.parse(packed.stdout) as { filename: string }[];
        const archive = report[0]?.filename;

        expect(archive).toBeDefined();

        const tarball = join(root, 'archives', archive ?? 'missing');
        const listed = await run('tar', ['-tzf', tarball]);

        expect(listed.stdout.split('\n')).toContain('package/bin/chord');
        expect(listed.stdout.split('\n')).toContain('package/LICENSE');

        for (const notice of notices) {
          const content = await run('tar', [
            '-xOf',
            tarball,
            `package/${notice}`,
          ]);

          expect(content.stdout).toBe(`${target.bun}: ${notice}\n`);
        }
      }
    } finally {
      await rm(root, { recursive: true, force: true });
    }
  });
});
