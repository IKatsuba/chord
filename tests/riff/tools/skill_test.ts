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

  test('an oversized first line is cut, the page stays within its bytes', async () => {
    // Four bytes a character, a whole MiB on one line.
    await writeFile(
      join(skills[0]!.directory, 'wide.md'),
      `${'😀'.repeat(256 * 1024)}\nnext\n`,
    );

    const loaded = await loadSkill(
      skills,
      { name: 'notes', resource: 'wide.md' },
      live(),
    );
    const body = loaded.text.slice(
      loaded.text.indexOf('>\n') + 2,
      loaded.text.indexOf('\n</skill_content>'),
    );

    expect(new TextEncoder().encode(body).length).toBeLessThanOrEqual(
      LIMITS.readBytes,
    );
    expect(body).toEndWith('…\nnext');
    expect(body).not.toContain('\uFFFD');
    expect(body.split('\n')[0]!.length).toBeLessThanOrEqual(
      LIMITS.readLineChars + 1,
    );
    expect(loaded.text).toContain(
      `Lines over ${LIMITS.readLineChars} characters were cut`,
    );
    expect(loaded.shown).toBe('Loaded skill notes, wide.md (2 lines)');
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

describe('CHD-610 tester: skill resource boundaries', () => {
  test('byte-limited pages resume without omitting or duplicating a line', async () => {
    const directory = skills[0]!.directory;
    const line = '界'.repeat(1000);
    const count = 120;

    await writeFile(
      join(directory, 'bytes.md'),
      Array(count).fill(line).join('\n'),
    );

    const first = await loadSkill(
      skills,
      { name: 'notes', resource: 'bytes.md' },
      live(),
    );
    const body = first.text.slice(
      first.text.indexOf('>\n') + 2,
      first.text.indexOf('\n</skill_content>'),
    );
    const returned = body.split('\n').length;

    expect(new TextEncoder().encode(body).length).toBeLessThanOrEqual(
      LIMITS.readBytes,
    );
    expect(returned).toBeLessThan(count);
    expect(first.text).toContain(
      `call skill again with offset ${returned + 1}`,
    );

    const next = await loadSkill(
      skills,
      { name: 'notes', resource: 'bytes.md', offset: returned + 1 },
      live(),
    );
    const remainder = next.text.slice(
      next.text.indexOf('>\n') + 2,
      next.text.indexOf('\n</skill_content>'),
    );

    expect(returned + remainder.split('\n').length).toBe(count);
    expect(next.text).not.toContain('More from line');
  });

  test('a cut at an odd surrogate boundary keeps a whole character', async () => {
    await writeFile(
      join(skills[0]!.directory, 'surrogate.md'),
      `x${'😀'.repeat(LIMITS.readLineChars)}\n`,
    );

    const loaded = await loadSkill(
      skills,
      { name: 'notes', resource: 'surrogate.md' },
      live(),
    );
    const body = loaded.text.slice(
      loaded.text.indexOf('>\n') + 2,
      loaded.text.indexOf('\n</skill_content>'),
    );

    expect(body).toBe(`x${'😀'.repeat(999)}…`);
    expect(body).not.toContain('�');
    expect(loaded.text).toContain('nothing reads past the cut');
  });

  test('directory links cannot reach a sibling with the same path prefix', async () => {
    const directory = skills[0]!.directory;
    const sibling = `${directory}-private`;

    await mkdir(sibling);
    await writeFile(join(sibling, 'secret.md'), 'outside marker');
    await symlink(sibling, join(directory, 'escape'));

    await expect(
      loadSkill(
        skills,
        { name: 'notes', resource: 'escape/secret.md' },
        live(),
      ),
    ).rejects.toThrow("outside the skill's folder; not read");
  });

  test('a linked SKILL.md outside the discovered folder is refused', async () => {
    const directory = join(root, 'linked-main');

    await mkdir(directory);
    await symlink(join(root, 'secret.txt'), join(directory, 'SKILL.md'));

    await expect(
      loadSkill(
        [{ name: 'linked', description: '', directory }],
        { name: 'linked' },
        live(),
      ),
    ).rejects.toThrow("outside the skill's folder; not read");
  });

  test('an over-limit resource refuses without poisoning the next load', async () => {
    await writeFile(
      join(skills[0]!.directory, 'large.md'),
      'x'.repeat(LIMITS.skillBytes + 1),
    );

    await expect(
      loadSkill(skills, { name: 'notes', resource: 'large.md' }, live()),
    ).rejects.toThrow('over 4 MiB; not read');

    expect((await loadSkill(skills, { name: 'notes' }, live())).shown).toBe(
      'Loaded skill notes (6 lines)',
    );
  });

  test('cancellation after dispatch leaves independent loads usable', async () => {
    const controller = new AbortController();
    const pending = loadSkill(skills, { name: 'notes' }, controller.signal);

    controller.abort();

    await expect(pending).rejects.toThrow();
    expect((await loadSkill(skills, { name: 'notes' }, live())).shown).toBe(
      'Loaded skill notes (6 lines)',
    );
  });
});
