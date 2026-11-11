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
  findSkills,
  type Skill,
  skillMetadata,
  skillsSection,
  skippedSkillNote,
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

  test('a skill folder linked inside the project is its real path', async () => {
    const kept = join(project, 'shared', 'linked');

    await mkdir(kept, { recursive: true });
    await writeFile(join(kept, 'SKILL.md'), md('linked', 'Via a link'));
    await mkdir(join(project, '.agents', 'skills'), { recursive: true });
    await symlink(kept, join(project, '.agents', 'skills', 'linked'));

    const found = await findSkills({ directory: project, home: undefined });

    expect(found.skills[0]?.directory).toBe(kept);
    expect(found.skipped).toEqual([]);
  });

  test('a project skill linking out of the project, or a home one out of home, is skipped with where it points', async () => {
    const elsewhere = join(root, 'elsewhere');

    await mkdir(elsewhere);
    await writeFile(join(elsewhere, 'SKILL.md'), md('outside', 'Via a link'));
    await mkdir(join(project, '.agents', 'skills'), { recursive: true });
    await mkdir(join(home, '.agents', 'skills'), { recursive: true });
    await symlink(elsewhere, join(project, '.agents', 'skills', 'away'));
    await symlink(elsewhere, join(home, '.agents', 'skills', 'roaming'));

    // A folder inside whose SKILL.md alone links out.
    const half = await skill(project, 'half', 'unused');

    await rm(join(half, 'SKILL.md'));
    await symlink(join(elsewhere, 'SKILL.md'), join(half, 'SKILL.md'));

    const found = await findSkills({ directory: project, home });

    expect(found.skills).toEqual([]);
    expect(found.skipped).toEqual([
      {
        name: 'away',
        reason: 'its folder links outside the project, to ../elsewhere',
      },
      {
        name: 'half',
        reason:
          'its SKILL.md links outside the project, to ../elsewhere/SKILL.md',
      },
      {
        name: 'roaming',
        reason: 'its folder links outside home, to ../elsewhere',
      },
    ]);
    expect(skippedSkillNote(found.skipped[0]!)).toBe(
      'Skill away was not loaded: its folder links outside the project, to ../elsewhere',
    );
  });

  test('a SKILL.md swapped for a link out after the check is refused, never read', async () => {
    const elsewhere = join(root, 'elsewhere');
    const directory = await skill(project, 'notes', md('notes', 'Inside'));
    const file = join(directory, 'SKILL.md');

    await mkdir(elsewhere);
    await writeFile(join(elsewhere, 'SKILL.md'), md('outside', 'Secret'));

    const found = findSkills({
      directory: project,
      home: undefined,
      beforeOpen: async () => {
        await rm(file);
        await symlink(join(elsewhere, 'SKILL.md'), file);
      },
    });

    await expect(found).rejects.toThrow(
      `${file}: the file changed while it was opened; read it again`,
    );
  });

  test('invalid metadata is skipped with its reason, by the folder name', async () => {
    await skill(project, 'bad-yaml', '---\nname: [\n---\n');
    await skill(project, 'bad-name', md('a/b', 'slash'));
    await skill(project, 'no-name', '---\ndescription: d\n---\n');
    await skill(project, 'list-text', '---\nname: x\ndescription: [1]\n---\n');

    const found = await findSkills({ directory: project, home: undefined });

    expect(found.skipped).toEqual([
      { name: 'bad-name', reason: 'its name "a/b" is not a valid skill name' },
      {
        name: 'bad-yaml',
        reason: 'its SKILL.md frontmatter is not valid YAML',
      },
      { name: 'list-text', reason: 'its description is not text' },
      { name: 'no-name', reason: 'its SKILL.md frontmatter has no name' },
    ]);
  });

  test('an unreadable SKILL.md fails discovery, naming it', async () => {
    const directory = await skill(project, 'locked', md('locked', 'x'));

    await chmod(join(directory, 'SKILL.md'), 0o000);

    await expect(
      discoverSkills({ directory: project, home: undefined }),
    ).rejects.toThrow(
      new Error(
        `${join(project, '.agents', 'skills', 'locked', 'SKILL.md')}: permission denied`,
      ),
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

describe('CHD-610 tester: skill discovery boundaries', () => {
  test('duplicate names within the project use folder order before user skills', async () => {
    await skill(project, 'z-last', md('shared', 'Later project'));
    await skill(project, 'a-first', md('shared', 'First project'));
    await skill(home, 'shared', md('shared', 'User copy'));

    const found = await discoverSkills({ directory: project, home });

    expect(found).toHaveLength(1);
    expect(found[0]?.description).toBe('First project');
    expect(found[0]?.directory).toEndWith('/a-first');
  });

  test('a nested session reads its own skills, with no ancestor fallback', async () => {
    const nested = join(project, 'nested');

    await mkdir(nested);
    await skill(project, 'parent', md('parent', 'Parent only'));
    await skill(nested, 'child', md('child', 'Child only'));

    expect(
      (await discoverSkills({ directory: nested, home: undefined })).map(
        (each) => each.name,
      ),
    ).toEqual(['child']);
  });

  test('discovery lists metadata without inlining the body', async () => {
    await skill(
      project,
      'notes',
      `${md('notes', 'A summary')}private-body-marker`,
    );

    const found = await discoverSkills({ directory: project, home: undefined });
    const listed = skillsSection(found);

    expect(listed).toContain('notes: A summary');
    expect(listed).not.toContain('private-body-marker');
  });

  test('the name limit counts UTF-8 bytes', () => {
    expect(validName('界'.repeat(85))).toBe(true);
    expect(validName('界'.repeat(86))).toBe(false);
    expect(validName('😀'.repeat(64))).toBe(true);
    expect(validName('😀'.repeat(65))).toBe(false);
  });
});

describe('CHD-610 tester: skipped skill containment', () => {
  test('a project path prefix does not admit a linked sibling skill', async () => {
    const sibling = `${project}-private`;

    await mkdir(sibling);
    await writeFile(join(sibling, 'SKILL.md'), md('outside', 'Secret rules'));
    await mkdir(join(project, '.agents', 'skills'), { recursive: true });
    await symlink(sibling, join(project, '.agents', 'skills', 'outside'));

    const found = await findSkills({ directory: project, home: undefined });

    expect(found.skills).toEqual([]);
    expect(found.skipped).toEqual([
      {
        name: 'outside',
        reason: 'its folder links outside the project, to ../project-private',
      },
    ]);
  });

  test('a skipped project link cannot hide a valid home skill with that name', async () => {
    const outside = join(root, 'outside');

    await mkdir(outside);
    await writeFile(join(outside, 'SKILL.md'), md('shared', 'Outside rules'));
    await mkdir(join(project, '.agents', 'skills'), { recursive: true });
    await symlink(outside, join(project, '.agents', 'skills', 'shared'));
    await skill(home, 'shared', md('shared', 'Allowed home rules'));

    const found = await findSkills({ directory: project, home });

    expect(found.skills).toHaveLength(1);
    expect(found.skills[0]?.description).toBe('Allowed home rules');
    expect(found.skipped).toHaveLength(1);
    expect(found.skipped[0]?.name).toBe('shared');
  });
});

describe('CHD-610 tester: portable unreadable skill errors', () => {
  test('an unreadable linked project skill names its logical SKILL.md once', async () => {
    const physical = join(project, 'shared', 'notes');
    const logical = join(project, '.agents', 'skills', 'notes');

    await mkdir(physical, { recursive: true });
    await mkdir(join(project, '.agents', 'skills'), { recursive: true });
    await writeFile(join(physical, 'SKILL.md'), md('notes', 'Rules'));
    await symlink(physical, logical);
    await chmod(join(physical, 'SKILL.md'), 0o000);

    await expect(
      discoverSkills({ directory: project, home: undefined }),
    ).rejects.toThrow(
      new Error(`${join(logical, 'SKILL.md')}: permission denied`),
    );
  });

  test('an unreadable home skill uses the same refusal as a project skill', async () => {
    const directory = await skill(home, 'locked', md('locked', 'Home rules'));
    const file = join(directory, 'SKILL.md');

    await chmod(file, 0o000);

    await expect(discoverSkills({ directory: project, home })).rejects.toThrow(
      new Error(`${file}: permission denied`),
    );
  });
});
