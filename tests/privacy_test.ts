import { execFile } from 'node:child_process';
import { expect, test } from 'bun:test';
import { mkdtemp, readFile, rm } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import process from 'node:process';
import { basename } from 'node:path';

/** One place a file names something private: where, and what it says. */
type Finding = { line: number; text: string };

/**
 * Paths that name a person's machine: a home directory on macOS, Linux or
 * Windows, and Claude Code's own directory in a home. Its settings and
 * keybindings files are documented public names, but only as themselves:
 * what may follow them is listed, not what may not, so any suffix (a backup,
 * a path inside) makes them private again, while the punctuation of a
 * sentence or a Markdown table around them does not. The rest of it
 * (projects, memory, sessions) is named after a person's paths.
 *
 * The macOS prefix alone is private too: a capture cut off after it still
 * says whose machine it came from, and nothing public needs to write it.
 */
const privatePatterns = [
  /\/Users\/[^/\s]*/g,
  /\/home\/[^/\s]+/g,
  /\b[A-Za-z]:\\Users\\[^\\\s]+/g,
  /~\/\.claude\/(?!(?:settings|keybindings)\.json(?:$|[\s)\]}'"`,;:!?*>|]|\.(?:$|[\s)\]}'"`*>|])))\S*/g,
  /\.claude\/projects\/\S*/g,
];

/** Account names too common to mean anyone, such as CI's. */
const sharedAccounts = new Set(['runner', 'root', 'user', 'admin', 'ubuntu']);

/**
 * The patterns for whoever runs the check: their home directory anywhere, and
 * its name as a word, which catches it written without the directory around it.
 */
function homePatterns(home: string | undefined): RegExp[] {
  if (!home || home === '/') {
    return [];
  }

  const name = basename(home);
  const escape = (text: string) => text.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const patterns = [new RegExp(escape(home), 'g')];

  if (name.length >= 3 && !sharedAccounts.has(name.toLowerCase())) {
    patterns.push(new RegExp(`\\b${escape(name)}\\b`, 'gi'));
  }

  return patterns;
}

/** Every line of `text` that names a private path, with what it names. */
function privatePaths(text: string, home: string | undefined): Finding[] {
  const patterns = [...privatePatterns, ...homePatterns(home)];

  return text.split('\n').flatMap((content, index) => {
    // The same path can match a general pattern and the home one.
    const named = new Set(
      patterns.flatMap((pattern) =>
        [...content.matchAll(pattern)].map((match) => match[0]),
      ),
    );

    return [...named].map((text) => ({ line: index + 1, text }));
  });
}

const decoder = new TextDecoder();

/**
 * The files git tracks under `cwd`. Throws when git cannot list them, so a
 * check run outside the repository fails instead of passing on nothing.
 */
async function trackedFiles(cwd = '.'): Promise<string[]> {
  const listed = await new Promise<string>((resolve, reject) => {
    execFile(
      'git',
      ['ls-files', '-z'],
      { cwd, maxBuffer: 64 * 1024 * 1024 },
      (error, stdout, stderr) =>
        error === null
          ? resolve(stdout)
          : reject(new Error(`git ls-files failed: ${stderr.trim()}`)),
    );
  });

  const files = listed.split('\0').filter(Boolean);

  if (files.length === 0) {
    throw new Error('git ls-files listed no files');
  }

  return files;
}

// Built from parts so that this file passes its own check.
const someone = ['', 'Users', 'someone', 'work'].join('/');
const linux = ['', 'home', 'someone', 'work'].join('/');
const memory = ['~', '.claude', 'projects', 'x', 'memory'].join('/');

test('a home directory on any system is a private path', () => {
  expect(privatePaths(`a\nfake · ${someone}\n`, undefined)).toStrictEqual([
    { line: 2, text: someone.split('/').slice(0, 3).join('/') },
  ]);
  expect(privatePaths(`cd ${linux}`, undefined).length).toStrictEqual(1);
  expect(
    privatePaths('C:\\Users\\someone\\work', undefined).length,
  ).toStrictEqual(1);
});

test('claude settings are public names, its other files are not', () => {
  expect(privatePaths('`~/.claude/settings.json`', undefined)).toStrictEqual(
    [],
  );
  expect(privatePaths('`~/.claude/keybindings.json`', undefined)).toStrictEqual(
    [],
  );
  expect(privatePaths('.claude/settings.local.json', undefined)).toStrictEqual(
    [],
  );
  expect(privatePaths(memory, undefined).length).toStrictEqual(2);
});

test('claude settings stay public only as the exact file names', () => {
  for (const sentence of [
    'see ~/.claude/settings.json.',
    '(~/.claude/keybindings.json), and',
    '~/.claude/settings.json: the file',
    '"~/.claude/settings.json"',
    '| `~/.claude/keybindings.json` |',
    '~/.claude/settings.json',
    'is ~/.claude/keybindings.json; then',
  ]) {
    expect(privatePaths(sentence, undefined), sentence).toStrictEqual([]);
  }

  // Built from parts, as above: written whole, they would fail this file.
  const home = ['~', '.claude', ''].join('/');

  for (const leak of [
    `${home}settings.json.bak`,
    `${home}keybindings.json/private-session`,
    `${home}settings.json-old`,
    `${home}settings.jsonl`,
    `${home}settings.json~`,
    `${home}keybindings.json~`,
    `${home}settings.json.~1~`,
    `${home}keybindings.json#`,
  ]) {
    expect(privatePaths(leak, undefined).length, leak).toStrictEqual(1);
  }
});

test('the macOS home prefix alone is a private path', () => {
  const prefix = ['', 'Users', ''].join('/');

  expect(privatePaths(`cut off at ${prefix}`, undefined)).toStrictEqual([
    { line: 1, text: prefix },
  ]);
});

test('listing tracked files outside a repository fails', async () => {
  const outside = await mkdtemp(join(tmpdir(), 'chord-'));

  try {
    const refused = trackedFiles(outside);

    await expect(refused).rejects.toThrow(Error);
    await expect(refused).rejects.toThrow('git ls-files failed');
  } finally {
    await rm(outside, { recursive: true });
  }
});

test('the home of whoever runs the check is private, and its name', () => {
  const home = ['', 'srv', 'people', 'someone'].join('/');

  expect(
    privatePaths(`in ${home}/chord`, home).map((f) => f.text),
  ).toStrictEqual([home, 'someone']);
  expect(privatePaths('signed Someone', home).length).toStrictEqual(1);
  expect(
    privatePaths('a GitHub runner', ['', 'srv', 'runner'].join('/')),
  ).toStrictEqual([]);
});

test('no file git tracks names a private path', async () => {
  const home = process.env.HOME;
  const found: string[] = [];

  for (const file of await trackedFiles()) {
    let bytes: Uint8Array;

    try {
      bytes = await readFile(file);
    } catch (error) {
      // Deleted in the working tree and not yet committed.
      if ((error as NodeJS.ErrnoException).code === 'ENOENT') {
        continue;
      }

      throw error;
    }

    if (bytes.includes(0)) {
      continue;
    }

    for (const { line, text } of privatePaths(decoder.decode(bytes), home)) {
      found.push(`${file}:${line}: ${text}`);
    }
  }

  expect(
    found,
    'a tracked file names a private path; retake captures with ' +
      '`-C $(mktemp -d /tmp/chord-qa.XXXX)` (the chord-tui skill)',
  ).toStrictEqual([]);
});
