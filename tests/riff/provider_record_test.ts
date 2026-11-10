import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { mkdtemp, readFile, readdir, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  clearProvider,
  readProvider,
  writeProvider,
} from '../../src/riff/provider_record.ts';

let root: string;

beforeEach(async () => {
  root = await mkdtemp(join(tmpdir(), 'chord-provider-'));
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

describe('riff provider record', () => {
  test('missing or invalid records do not select a provider', async () => {
    expect(await readProvider(root)).toBeUndefined();
    await writeProvider(root, 'grok');
    await writeFile(join(root, 'riff', 'provider'), 'unknown\n');
    expect(await readProvider(root)).toBeUndefined();
  });

  test('the atomic record holds only the provider and clears only its own selection', async () => {
    await writeProvider(root, 'grok');
    expect(await readFile(join(root, 'riff', 'provider'), 'utf8')).toBe(
      'grok\n',
    );
    await clearProvider(root, 'codex');
    expect(await readProvider(root)).toBe('grok');
    await writeProvider(root, 'codex');
    await clearProvider(root, 'grok');
    expect(await readProvider(root)).toBe('codex');
    await clearProvider(root, 'codex');
    expect(await readProvider(root)).toBeUndefined();
    expect(await readdir(join(root, 'riff', 'credentials'))).toEqual([]);
  });
});
