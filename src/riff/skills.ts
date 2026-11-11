/**
 * riff's skills (CHD-485, "MCP, chord's own tools, skills and
 * instructions"): `SKILL.md` files from `.agents/skills/` in the session's
 * directory and in the home directory, their names and descriptions in the
 * instructions, each loaded on demand by the `skill` tool.
 *
 * Adapted from vercel-labs/fx v0.0.16, src/builtins/skills.zig (roots) and
 * src/core/skills/skill_contract.zig (metadata and name rules), Apache-2.0;
 * only the `.agents/skills` roots, as the owner chose.
 */
import { VFile } from 'vfile';
import { matter } from 'vfile-matter';
import { constants } from 'node:fs';
import { open, readdir, realpath, stat } from 'node:fs/promises';
import { basename, isAbsolute, join } from 'node:path';
import { notFound } from '../not_found.ts';

/** One discovered skill. */
export interface Skill {
  readonly name: string;
  readonly description: string;
  /** The skill's folder, as its real path: the only place it reads from. */
  readonly directory: string;
}

export interface SkillSources {
  /** The session's directory, as its real path. */
  readonly directory: string;
  /** The home directory; none reads no user skills. */
  readonly home: string | undefined;
}

const ROOT = join('.agents', 'skills');

/** The bytes of a `SKILL.md` the discovery reads for its frontmatter. */
const HEAD_BYTES = 64 * 1024;

/** fx's limit on a skill's name. */
const NAME_BYTES = 256;

/**
 * The skills in the project's root, then the home's; a name found twice
 * keeps the first, so the project wins. A skill whose `SKILL.md` is
 * missing or whose metadata is invalid is left out.
 */
export async function discoverSkills(sources: SkillSources): Promise<Skill[]> {
  const roots = [join(sources.directory, ROOT)];

  if (sources.home !== undefined) {
    roots.push(join(sources.home, ROOT));
  }

  const found = new Map<string, Skill>();

  for (const root of roots) {
    for (const skill of await skillsIn(root)) {
      if (!found.has(skill.name)) {
        found.set(skill.name, skill);
      }
    }
  }

  return [...found.values()];
}

/** The skills of one root, in folder-name order. */
async function skillsIn(root: string): Promise<Skill[]> {
  let names: string[];

  try {
    names = (await readdir(root)).sort();
  } catch (error) {
    if (absent(error)) {
      return [];
    }

    throw named(root, error);
  }

  const skills: Skill[] = [];

  for (const name of names) {
    const skill = await skillAt(join(root, name));

    if (skill !== undefined) {
      skills.push(skill);
    }
  }

  return skills;
}

/**
 * The skill in `folder`; none when it is no folder or has no `SKILL.md`.
 * One that cannot be read refuses the start, as an `AGENTS.md` does.
 */
async function skillAt(folder: string): Promise<Skill | undefined> {
  let directory: string;
  let head: string | undefined;

  try {
    directory = await realpath(folder);

    if (!(await stat(directory)).isDirectory()) {
      return undefined;
    }

    head = await readHead(join(directory, 'SKILL.md'));
  } catch (error) {
    if (absent(error)) {
      return undefined;
    }

    throw named(folder, error);
  }

  if (head === undefined) {
    return undefined;
  }

  const metadata = skillMetadata(head, basename(folder));

  return metadata === undefined ? undefined : { ...metadata, directory };
}

/** The start of a regular file, or undefined when there is none. */
async function readHead(file: string): Promise<string | undefined> {
  if (!(await stat(file)).isFile()) {
    return undefined;
  }

  const handle = await open(file, constants.O_RDONLY | constants.O_NONBLOCK);

  try {
    if (!(await handle.stat()).isFile()) {
      return undefined;
    }

    const buffer = new Uint8Array(HEAD_BYTES);
    const { bytesRead } = await handle.read(buffer, 0, buffer.length, 0);

    return new TextDecoder().decode(buffer.subarray(0, bytesRead));
  } finally {
    await handle.close();
  }
}

/**
 * A `SKILL.md`'s name and description, as fx resolves them: the
 * frontmatter's, or the folder's name with no description when it has no
 * frontmatter; undefined when the frontmatter or the name is invalid.
 */
export function skillMetadata(
  text: string,
  folder: string,
): { readonly name: string; readonly description: string } | undefined {
  const file = new VFile(new TextEncoder().encode(text));
  const read = file.value;

  try {
    matter(file, { strip: true });
  } catch {
    return undefined;
  }

  // vfile-matter reads a file with none as an empty mapping; only whether it
  // stripped anything tells the two apart.
  if (file.value === read) {
    return validName(folder) ? { name: folder, description: '' } : undefined;
  }

  const data = file.data.matter as Record<string, unknown> | undefined;
  const name = data?.['name'];
  const description = data?.['description'] ?? '';

  if (
    typeof name !== 'string' ||
    typeof description !== 'string' ||
    !validName(name)
  ) {
    return undefined;
  }

  return { name, description: description.trim() };
}

/** fx's rule: one path segment of printable text, at most 256 bytes. */
export function validName(name: string): boolean {
  return (
    name.length > 0 &&
    new TextEncoder().encode(name).length <= NAME_BYTES &&
    name !== '.' &&
    name !== '..' &&
    !isAbsolute(name) &&
    !name.includes('/') &&
    !name.includes('\\') &&
    // eslint-disable-next-line no-control-regex
    !/[\u0000-\u001f\u007f]/u.test(name)
  );
}

/**
 * What the instructions may take for the skills: with the 32 KiB of
 * `AGENTS.md` and a margin, inside libfx's 64 KiB.
 */
export const SKILLS_CAP = 30 * 1024;

/**
 * What the instructions say of the skills, names and descriptions only,
 * within `cap` bytes: skills past it are counted, not listed.
 */
export function skillsSection(
  skills: readonly Skill[],
  cap = SKILLS_CAP,
): string | undefined {
  if (skills.length === 0) {
    return undefined;
  }

  const encoder = new TextEncoder();
  const lines = [
    'Skills: when a task matches a skill below, load it with the skill tool by its name before you start, and load the resources it names the same way.',
  ];
  // Room kept for the line that counts what is left out.
  let used = encoder.encode(lines[0]).length + 64;
  let listed = 0;

  for (const skill of skills) {
    const line =
      skill.description === ''
        ? `- ${skill.name}`
        : `- ${skill.name}: ${skill.description.replaceAll(/\s+/gu, ' ')}`;
    const cost = encoder.encode(line).length + 1;

    if (used + cost > cap) {
      break;
    }

    lines.push(line);

    used += cost;

    listed++;
  }

  if (listed < skills.length) {
    lines.push(`(${skills.length - listed} more skills are not listed.)`);
  }

  return lines.join('\n');
}

/** Nothing there, or a file where a folder was looked for. */
function absent(error: unknown): boolean {
  return (
    notFound(error) ||
    (error instanceof Error && 'code' in error && error.code === 'ENOTDIR')
  );
}

function named(path: string, error: unknown): Error {
  return new Error(
    `${path}: ${error instanceof Error ? error.message : String(error)}`,
  );
}
