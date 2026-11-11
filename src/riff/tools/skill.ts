/**
 * riff's `skill` (CHD-485, "MCP, chord's own tools, skills and
 * instructions"): loads a discovered skill's `SKILL.md`, or one of its
 * resources, by the skill's name, a page of lines at a time. It reads only
 * inside that skill's folder, by real path.
 *
 * Adapted from vercel-labs/fx v0.0.16, src/tools/skills/skill.zig and
 * src/core/skills/skill_invocation.zig (load by name, resources, paging by
 * offset), Apache-2.0.
 */
import { z } from '@zod/zod';
import { fileTypeFromBuffer } from 'file-type';
import { readdir } from 'node:fs/promises';
import { join, relative, resolve, sep } from 'node:path';
import type { Skill } from '../skills.ts';
import { LIMITS } from './limits.ts';
import { isInside, openReal, realOf } from './paths.ts';

export const SkillInput = z
  .object({
    name: z.string().min(1).describe('The skill, by its listed name.'),
    resource: z
      .string()
      .min(1)
      .optional()
      .describe(
        'A file of the skill, relative to its folder; SKILL.md when not given.',
      ),
    offset: z.int().min(1).optional().describe('The first line, from 1.'),
  })
  .strict();

export type SkillInput = z.infer<typeof SkillInput>;

export const SKILL_DESCRIPTION = [
  'Load a skill listed in the instructions by its name: its SKILL.md, then',
  'any of the files it names with `resource`, relative to the skill. At',
  `most ${LIMITS.readLines} lines or ${LIMITS.readBytes / 1024} KiB come at`,
  'once; when more is left, the answer says which `offset` reads on. Only',
  "files inside the skill's own folder are read.",
].join(' ');

const MAIN = 'SKILL.md';

/** What a load gives the model, and the line the window shows of it. */
export interface Loaded {
  readonly text: string;
  readonly shown: string;
}

/** Loads `input` from `skills`, the session's discovered skills. */
export async function loadSkill(
  skills: readonly Skill[],
  input: SkillInput,
  signal: AbortSignal,
): Promise<Loaded> {
  signal.throwIfAborted();

  const skill = skills.find((each) => each.name === input.name);

  if (skill === undefined) {
    throw new Error(`no skill named ${input.name}`);
  }

  const resource = input.resource ?? MAIN;
  const label = `${resource} of skill ${skill.name}`;
  const real = await realOf(resolve(skill.directory, resource), label);

  // A resource whose real path leaves the skill's folder, by `..`, an
  // absolute path or a link, is never read.
  if (!isInside(skill.directory, real) || real === skill.directory) {
    throw new Error(`${label}: outside the skill's folder; not read`);
  }

  const { handle, size } = await openReal(real, { label, exact: true });
  let bytes: Uint8Array;

  try {
    if (size > LIMITS.skillBytes) {
      throw new Error(
        `${label}: ${size} bytes, over ${LIMITS.skillBytes / 1024 / 1024} MiB; not read`,
      );
    }

    bytes = new Uint8Array(size);

    await handle.read(bytes, 0, size, 0);
  } finally {
    await handle.close();
  }

  signal.throwIfAborted();

  const type = await fileTypeFromBuffer(bytes.subarray(0, LIMITS.sniffBytes));

  if (type !== undefined && !type.mime.startsWith('text/')) {
    throw new Error(`${label}: a binary file (${type.mime}); not read`);
  }

  const lines = new TextDecoder().decode(bytes).split(/\r?\n/u);

  if (lines.at(-1) === '') {
    lines.pop();
  }

  const total = lines.length;
  const first = input.offset ?? 1;

  if (first > Math.max(total, 1)) {
    throw new Error(`${label} has ${total} lines; nothing at line ${first}`);
  }

  const page: string[] = [];
  let used = 0;

  for (const line of lines.slice(first - 1)) {
    const cost = new TextEncoder().encode(line).length + 1;

    if (
      page.length === LIMITS.readLines ||
      (page.length > 0 && used + cost > LIMITS.readBytes)
    ) {
      break;
    }

    page.push(line);

    used += cost;
  }

  const last = first + page.length - 1;
  const parts = [
    `<skill_content name="${skill.name}" resource="${resource}" lines="${first}-${last}" of="${total}">`,
    page.join('\n'),
    '</skill_content>',
  ];

  if (last < total) {
    parts.push(
      `More from line ${last + 1}; call skill again with offset ${last + 1}.`,
    );
  }

  if (resource === MAIN && first === 1) {
    const resources = await resourcesOf(skill.directory);

    if (resources.length > 0) {
      parts.push(
        `Resources of this skill, loaded with \`resource\`:\n${resources.join('\n')}`,
      );
    }
  }

  const of = resource === MAIN ? '' : `, ${resource}`;
  const shown =
    first === 1 && last === total
      ? `Loaded skill ${skill.name}${of} (${total} lines)`
      : `Loaded skill ${skill.name}${of}, lines ${first}–${last} of ${total}`;

  return { text: parts.join('\n'), shown };
}

/** The skill's other files, relative to its folder, dot paths left out. */
async function resourcesOf(directory: string): Promise<string[]> {
  const entries = await readdir(directory, {
    recursive: true,
    withFileTypes: true,
  });

  return entries
    .filter((entry) => entry.isFile() || entry.isSymbolicLink())
    .map((entry) => relative(directory, join(entry.parentPath, entry.name)))
    .filter(
      (path) =>
        path !== MAIN && !path.split(sep).some((part) => part.startsWith('.')),
    )
    .sort()
    .slice(0, LIMITS.skillResources);
}
