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
import { lstat, readdir, realpath, stat } from 'node:fs/promises';
import { basename, isAbsolute, join, relative } from 'node:path';
import { isInside, openReal, reason } from './tools/paths.ts';
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
  /** Before each `SKILL.md` is opened: where tests swap it. */
  readonly beforeOpen?: () => Promise<void>;
}

const ROOT = join('.agents', 'skills');

/** The bytes of a `SKILL.md` the discovery reads for its frontmatter. */
const HEAD_BYTES = 64 * 1024;

/** fx's limit on a skill's name. */
const NAME_BYTES = 256;

/** A skill riff did not load, by its folder's name or its own, and why. */
export interface SkippedSkill {
  readonly name: string;
  readonly reason: string;
}

/** The skills discovered, and those left out with a reason. */
export interface FoundSkills {
  readonly skills: Skill[];
  readonly skipped: SkippedSkill[];
}

/** The skills, without the reasons for those left out. */
export async function discoverSkills(sources: SkillSources): Promise<Skill[]> {
  return (await findSkills(sources)).skills;
}

/**
 * The skills in the project's root, then the home's; a name found twice
 * keeps the first, so the project wins. A folder without a `SKILL.md` is
 * no skill; one that links out of its place (main, CHD-610: a project
 * skill stays in the session's directory, a home skill in the home) or
 * whose metadata is invalid is skipped with its reason.
 */
export async function findSkills(sources: SkillSources): Promise<FoundSkills> {
  const places = [
    { base: sources.directory, where: 'the project' },
    ...(sources.home === undefined
      ? []
      : [{ base: sources.home, where: 'home' }]),
  ];
  const found = new Map<string, Skill>();
  const skipped: SkippedSkill[] = [];

  for (const place of places) {
    for (const each of await skillsIn(
      place.base,
      place.where,
      sources.beforeOpen,
    )) {
      if ('reason' in each) {
        skipped.push(each);
      } else if (!found.has(each.name)) {
        found.set(each.name, each);
      }
    }
  }

  return { skills: [...found.values()], skipped };
}

/** The skills of one place's root, in folder-name order. */
async function skillsIn(
  base: string,
  where: string,
  beforeOpen?: () => Promise<void>,
): Promise<(Skill | SkippedSkill)[]> {
  const root = join(base, ROOT);
  let names: string[];

  try {
    names = (await readdir(root)).sort();
  } catch (error) {
    if (absent(error)) {
      return [];
    }

    throw named(root, error);
  }

  // Inside is judged on real paths: the place itself may be reached by one.
  const inside = await realpath(base);
  const skills: (Skill | SkippedSkill)[] = [];

  for (const name of names) {
    const skill = await skillAt(join(root, name), inside, where, beforeOpen);

    if (skill !== undefined) {
      skills.push(skill);
    }
  }

  return skills;
}

/**
 * The skill in `folder`; none when it is no folder or has no `SKILL.md`,
 * skipped when it or its `SKILL.md` resolves outside `inside`. One that
 * cannot be read refuses the start, as an `AGENTS.md` does.
 */
async function skillAt(
  folder: string,
  inside: string,
  where: string,
  beforeOpen?: () => Promise<void>,
): Promise<Skill | SkippedSkill | undefined> {
  const name = basename(folder);
  const main = join(folder, 'SKILL.md');
  let directory: string;
  let file: string;
  let head: string | undefined;
  // The path a failure is about, named once in its reason.
  let at = folder;

  try {
    directory = await realpath(folder);

    if (!(await stat(directory)).isDirectory()) {
      return undefined;
    }

    if (!isInside(inside, directory)) {
      return {
        name,
        reason: `its folder links outside ${where}, to ${relative(inside, directory)}`,
      };
    }

    at = main;
    file = await realpath(join(directory, 'SKILL.md'));

    if (!isInside(inside, file)) {
      return {
        name,
        reason: `its SKILL.md links outside ${where}, to ${relative(inside, file)}`,
      };
    }

    head = await readHead(file, main, beforeOpen);
  } catch (error) {
    if (absent(error)) {
      return undefined;
    }

    throw named(at, error);
  }

  if (head === undefined) {
    return undefined;
  }

  const metadata = metadataOf(head, name);

  return 'reason' in metadata
    ? { name, reason: metadata.reason }
    : { ...metadata, directory };
}

/** The start of a regular file, or undefined when there is none. */
async function readHead(
  file: string,
  label: string,
  beforeOpen?: () => Promise<void>,
): Promise<string | undefined> {
  if (!(await lstat(file)).isFile()) {
    return undefined;
  }

  // `file` is the real path checked to be inside: opened as that very file,
  // so a link swapped in at its last name is refused, never followed.
  // openReal's refusals name `label` already, in its own platform-free words.
  const { handle } = await openReal(file, {
    label,
    exact: true,
    ...(beforeOpen === undefined ? {} : { beforeOpen }),
  });

  try {
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
  const metadata = metadataOf(text, folder);

  return 'reason' in metadata ? undefined : metadata;
}

/** As `skillMetadata`, with the reason when the metadata is invalid. */
export function metadataOf(
  text: string,
  folder: string,
):
  | { readonly name: string; readonly description: string }
  | { readonly reason: string } {
  const file = new VFile(new TextEncoder().encode(text));
  const read = file.value;

  try {
    matter(file, { strip: true });
  } catch {
    return { reason: 'its SKILL.md frontmatter is not valid YAML' };
  }

  // vfile-matter reads a file with none as an empty mapping; only whether it
  // stripped anything tells the two apart.
  if (file.value === read) {
    return validName(folder)
      ? { name: folder, description: '' }
      : { reason: 'its folder name is not a valid skill name' };
  }

  const data = file.data.matter as Record<string, unknown> | undefined;
  const name = data?.['name'];
  const description = data?.['description'] ?? '';

  if (typeof name !== 'string') {
    return { reason: 'its SKILL.md frontmatter has no name' };
  }

  if (!validName(name)) {
    return {
      reason: `its name ${JSON.stringify(name)} is not a valid skill name`,
    };
  }

  if (typeof description !== 'string') {
    return { reason: 'its description is not text' };
  }

  return { name, description: description.trim() };
}

/** chord's note in the window for a skill riff did not load. */
export function skippedSkillNote(skipped: SkippedSkill): string {
  return `Skill ${skipped.name} was not loaded: ${skipped.reason}`;
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

/**
 * `path`'s failure, worded from its code so every platform says the same:
 * macOS fails an unreadable file's realpath, Linux only its open, which
 * openReal has already worded and named.
 */
function named(path: string, error: unknown): Error {
  if (error instanceof Error && !('code' in error)) {
    return error;
  }

  return new Error(`${path}: ${reason(error)}`);
}
