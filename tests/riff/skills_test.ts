import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import {
  chmod,
  mkdir,
  mkdtemp,
  realpath,
  rm,
  symlink,
  writeFile,
} from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import {
  discoverSkills,
  type Skill,
  skillMetadata,
  skillsSection,
  validName,
} from '../../src/riff/skills.ts';

let root: string;
let project: string;
let home: string;

async function skill(base: string, folder: string, text: string) {
  const directory = join(base, '.agents', 'skills', folder);

  await mkdir(directory, { recursive: true });
  await writeFile(join(directory, 'SKILL.md'), text);

  return directory;
}

const md = (name: string, description: string) =>
  `---\nname: ${name}\ndescription: ${description}\n---\n\n# ${name}\n`;

beforeEach(async () => {
  root = await realpath(await mkdtemp(join(tmpdir(), 'chord-skills-')));
  project = join(root, 'project');
  home = join(root, 'home');

  await mkdir(project);
  await mkdir(home);
});

afterEach(async () => {
  await rm(root, { recursive: true, force: true });
});

describe('riff skill discovery', () => {
  test('reads the project and home .agents/skills, the project winning a clash', async () => {
    await skill(project, 'notes', md('release-notes', 'Project notes'));
    await skill(home, 'notes', md('release-notes', 'Home notes'));
    await skill(home, 'deploy', md('deploy', 'Ship it'));
    // Other agents' folders are never read.
    await mkdir(join(project, '.claude', 'skills', 'x'), { recursive: true });
    await writeFile(
      join(project, '.claude', 'skills', 'x', 'SKILL.md'),
      md('claude-only', 'no'),
    );

    const found = await discoverSkills({ directory: project, home });

    expect(found.map(({ name, description }) => [name, description])).toEqual([
      ['release-notes', 'Project notes'],
      ['deploy', 'Ship it'],
    ]);
    expect(found[0]?.directory).toBe(
      join(project, '.agents', 'skills', 'notes'),
    );
  });

  test('no home reads only the project', async () => {
    await skill(home, 'deploy', md('deploy', 'Ship it'));

    expect(
      await discoverSkills({ directory: project, home: undefined }),
    ).toEqual([]);
  });

  test('a folder without SKILL.md, a file, and invalid metadata are left out', async () => {
    const skills = join(project, '.agents', 'skills');

    await mkdir(join(skills, 'empty'), { recursive: true });
    await writeFile(join(skills, 'loose.md'), 'not a skill');
    await skill(project, 'bad-yaml', '---\nname: [\n---\n');
    await skill(project, 'bad-name', md('a/b', 'slash'));
    await skill(project, 'plain', '# no frontmatter\n');

    const found = await discoverSkills({ directory: project, home: undefined });

    expect(found.map((each) => each.name)).toEqual(['plain']);
    expect(found[0]?.description).toBe('');
  });

  test('a linked skill folder is its real path', async () => {
    const elsewhere = join(root, 'elsewhere');

    await mkdir(elsewhere);
    await writeFile(join(elsewhere, 'SKILL.md'), md('linked', 'Via a link'));
    await mkdir(join(project, '.agents', 'skills'), { recursive: true });
    await symlink(elsewhere, join(project, '.agents', 'skills', 'linked'));

    const found = await discoverSkills({ directory: project, home: undefined });

    expect(found[0]?.directory).toBe(elsewhere);
  });

  test('an unreadable SKILL.md fails discovery, naming it', async () => {
    const directory = await skill(project, 'locked', md('locked', 'x'));

    await chmod(join(directory, 'SKILL.md'), 0o000);

    await expect(
      discoverSkills({ directory: project, home: undefined }),
    ).rejects.toThrow(
      `${join(project, '.agents', 'skills', 'locked')}: EACCES`,
    );
  });
});

describe('riff skill metadata', () => {
  test('frontmatter name and description, or the folder name without one', () => {
    expect(skillMetadata(md('x', 'Does x'), 'folder')).toEqual({
      name: 'x',
      description: 'Does x',
    });
    expect(skillMetadata('# body', 'folder')).toEqual({
      name: 'folder',
      description: '',
    });
    expect(skillMetadata('---\ndescription: d\n---\n', 'folder')).toBe(
      undefined,
    );
  });

  test("names follow fx's rule", () => {
    expect(validName('release-notes')).toBe(true);
    expect(validName('..')).toBe(false);
    expect(validName('a\\b')).toBe(false);
    expect(validName('a\nb')).toBe(false);
    expect(validName('x'.repeat(257))).toBe(false);
  });
});

describe('riff skills in the instructions', () => {
  const of = (name: string, description: string): Skill => ({
    name,
    description,
    directory: `/s/${name}`,
  });

  test('names and descriptions only, none for no skills', () => {
    expect(skillsSection([])).toBe(undefined);

    const text = skillsSection([of('a', 'Does\n  a'), of('b', '')]);

    expect(text).toContain('skill tool');
    expect(text).toContain('- a: Does a');
    expect(text).toContain('- b');
  });

  test('skills past the cap are counted, not listed', () => {
    const text = skillsSection(
      Array.from({ length: 50 }, (_, at) => of(`s${at}`, 'x'.repeat(40))),
      1024,
    );

    expect(new TextEncoder().encode(text).length).toBeLessThanOrEqual(1024);
    expect(text).toMatch(/\(\d+ more skills are not listed\.\)$/u);
  });
});
