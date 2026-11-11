import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  mkdir,
  mkdtemp,
  realpath,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import type { Skill } from '../../../src/riff/skills.ts';
import { LIMITS } from '../../../src/riff/tools/limits.ts';
import { loadSkill } from '../../../src/riff/tools/skill.ts';

const live = () => new AbortController().signal;

let root: string;
let skills: Skill[];

beforeEach(async () => {
  root = await realpath(await mkdtemp(join(tmpdir(), 'chord-skill-')));

  const directory = join(root, 'notes');

  await mkdir(join(directory, 'references'), { recursive: true });
  await mkdir(join(directory, '.hidden'));
  await writeFile(
    join(directory, 'SKILL.md'),
    '---\nname: notes\ndescription: d\n---\n\nStep one\n',
  );
  await writeFile(join(directory, 'references', 'rules.md'), 'a\nb\nc\n');
  await writeFile(join(directory, '.hidden', 'x'), 'x');
  await writeFile(join(root, 'secret.txt'), 'secret');

  skills = [{ name: 'notes', description: 'd', directory }];
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

describe("riff's skill tool", () => {
  test('loads SKILL.md by name with its resources and a one-line row', async () => {
    const loaded = await loadSkill(skills, { name: 'notes' }, live());

    expect(loaded.text).toContain(
      '<skill_content name="notes" resource="SKILL.md" lines="1-6" of="6">',
    );
    expect(loaded.text).toContain('Step one');
    expect(loaded.text).toContain(
      'Resources of this skill, loaded with `resource`:\nreferences/rules.md',
    );
    expect(loaded.text).not.toContain('.hidden');
    expect(loaded.shown).toBe('Loaded skill notes (6 lines)');
  });

  test('loads a resource', async () => {
    const loaded = await loadSkill(
      skills,
      { name: 'notes', resource: 'references/rules.md' },
      live(),
    );

    expect(loaded.text).toContain('a\nb\nc\n</skill_content>');
    expect(loaded.text).not.toContain('Resources of this skill');
    expect(loaded.shown).toBe(
      'Loaded skill notes, references/rules.md (3 lines)',
    );
  });

  test('pages by offset and says where to read on', async () => {
    const lines = Array.from(
      { length: LIMITS.readLines + 10 },
      (_, at) => `line ${at + 1}`,
    );

    await writeFile(join(skills[0]!.directory, 'long.md'), lines.join('\n'));

    const first = await loadSkill(
      skills,
      { name: 'notes', resource: 'long.md' },
      live(),
    );

    expect(first.text).toContain(
      `More from line ${LIMITS.readLines + 1}; call skill again with offset ${LIMITS.readLines + 1}.`,
    );
    expect(first.shown).toBe(
      `Loaded skill notes, long.md, lines 1–${LIMITS.readLines} of ${LIMITS.readLines + 10}`,
    );

    const next = await loadSkill(
      skills,
      { name: 'notes', resource: 'long.md', offset: LIMITS.readLines + 1 },
      live(),
    );

    expect(next.text).toContain(`line ${LIMITS.readLines + 10}`);
    expect(next.text).not.toContain('More from line');
  });

  test('an unknown name fails', async () => {
    await expect(
      loadSkill(skills, { name: 'relase-notes' }, live()),
    ).rejects.toThrow('no skill named relase-notes');
  });

  test('paths outside the skill are refused, by .., absolute path or link', async () => {
    const directory = skills[0]!.directory;

    await symlink(join(root, 'secret.txt'), join(directory, 'link.md'));

    for (const resource of [
      '../secret.txt',
      join(root, 'secret.txt'),
      'link.md',
    ]) {
      await expect(
        loadSkill(skills, { name: 'notes', resource }, live()),
      ).rejects.toThrow("outside the skill's folder; not read");
    }
  });

  test('a line past the end and a binary file are refused', async () => {
    await expect(
      loadSkill(skills, { name: 'notes', offset: 99 }, live()),
    ).rejects.toThrow('has 6 lines; nothing at line 99');

    await writeFile(
      join(skills[0]!.directory, 'x.gz'),
      new Uint8Array([0x1f, 0x8b, 0x08, 0, 0, 0, 0, 0, 0, 0x03, 0, 0]),
    );

    await expect(
      loadSkill(skills, { name: 'notes', resource: 'x.gz' }, live()),
    ).rejects.toThrow('a binary file');
  });

  test('an aborted call does not read', async () => {
    const controller = new AbortController();

    controller.abort();

    await expect(
      loadSkill(skills, { name: 'notes' }, controller.signal),
    ).rejects.toThrow();
  });
});
