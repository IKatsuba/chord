/**
 * Adapted from vercel-labs/fx v0.0.16,
 * src/core/shell_command/command_effect.zig, Apache-2.0.
 * chord uses unbash, separates pure planning from safe_git preparation,
 * and reviews reversible backslashes and unquoted words starting with =.
 */
import { parseLine } from './parse.ts';
import type { Line, Stage, Word } from './parse.ts';

const MAX_COMMAND_BYTES = 8 * 1024;
const MAX_PIPE_STAGES = 8;

/** An argv plan, with git arguments awaiting safe_git preparation. */
export type DirectStage = { executable: string; argv: string[]; git: boolean };
export type CommandEffect =
  | { kind: 'direct'; stages: DirectStage[] }
  | { kind: 'reversible'; prepareGit: boolean }
  | { kind: 'review'; reason: string };

export function commandEffect(
  source: string,
  options: { background?: boolean; platform?: string } = {},
): CommandEffect {
  if (options.background) {
    return { kind: 'review', reason: 'Background command' };
  }

  if (!source.isWellFormed()) {
    return { kind: 'review', reason: 'Unsupported shell syntax' };
  }

  let line: Line | null;

  try {
    line = parseLine(source);
  } catch {
    line = null;
  }

  if (!line) {
    return { kind: 'review', reason: 'Unsupported shell syntax' };
  }

  const platform = options.platform ?? process.platform;

  if ((platform === 'darwin' || platform === 'linux') && direct(source, line)) {
    return { kind: 'direct', stages: line.stages.map(canonicalStage) };
  }

  if (reversible(source, line)) {
    // fx prepares a supported git family before validating its arguments.
    const stage = line.stages[0];
    const prepareGit =
      (platform === 'darwin' || platform === 'linux') &&
      sourceOk(source, true) &&
      line.join === null &&
      stage !== undefined &&
      directShape(stage) &&
      stage.words[0]?.value === 'git' &&
      ['status', 'diff', 'log'].includes(stage.words[1]?.value ?? '');

    return { kind: 'reversible', prepareGit };
  }

  return { kind: 'review', reason: 'Command requires review' };
}

export function knownReversibleAutoCommand(source: string): boolean {
  if (source.includes('\\') || !source.isWellFormed()) {
    return false;
  }

  try {
    return reversible(source, parseLine(source));
  } catch {
    return false;
  }
}

function sourceOk(source: string, allowTrailingNewline: boolean): boolean {
  const s = allowTrailingNewline
    ? source.replace(/^[ \t\n]+|[ \t\n]+$/g, '')
    : source.replace(/^[ \t]+|[ \t]+$/g, '');

  if (
    s.length === 0 ||
    new TextEncoder().encode(s).length > MAX_COMMAND_BYTES
  ) {
    return false;
  }

  return !(allowTrailingNewline ? /[\0\r]/ : /[\0\r\n]/).test(s);
}

// command_effect.zig:137-143, plus `\`: chord reviews every backslash.
const DYNAMIC = /[$`*?[~^#\n\r;(){}\\]/;
// command_effect.zig:554-608 (validateShellShape) on unquoted text, plus `^`
// (zsh extendedglob) and `\`.
const UNQUOTED_DIRECT = /[$`*?[~\\#;\n(){}&><]/;

/** zsh's EQUALS option expands an unquoted word starting with `=`; chord's
 * shell is `$SHELL -c`. Not in fx. */
const zshEquals = (w: Word) =>
  w.unquoted.startsWith('=') && w.raw.startsWith('=');

function reversible(source: string, line: Line | null): boolean {
  if (!line || !sourceOk(source, false)) {
    return false;
  }

  if (line.join === '|') {
    return false;
  }

  for (const stage of line.stages) {
    if (!reversibleStage(stage)) {
      return false;
    }
  }

  return true;
}

function reversibleStage(stage: Stage): boolean {
  if (stage.assigns > 0) {
    return false;
  }

  // Only a trailing bare `2>&1` (command_effect.zig:86-101).
  if (stage.redirects.length > 1) {
    return false;
  }

  if (stage.redirects.length === 1) {
    const r = stage.redirects[0]!;

    if (!(
      stage.redirectLast &&
      r.raw === '2>&1' &&
      r.fd === 2 &&
      r.op === '>&' &&
      r.target?.value === '1'
    )) {
      return false;
    }
  }

  const words = stage.words;

  if (words.length === 0) {
    return false;
  }

  for (const w of words) {
    if (
      !w.literal ||
      DYNAMIC.test(w.raw) ||
      w.raw.startsWith('#') ||
      zshEquals(w)
    ) {
      return false;
    }
  }

  const [exe, ...rest] = words.map((w) => w.value);
  const v = (x?: string) => x === '-v' || x === '--version';

  switch (exe) {
    case 'node':
      return rest.length === 1 && v(rest[0]);
    case 'which':
      return (
        rest.length > 0 && rest.every((x) => x.length > 0 && !x.startsWith('-'))
      );
    case 'git':
      return reversibleGit(rest);
    case 'npm':
      return reversibleNpm(rest);
    case 'bun':
    case 'pnpm':
    case 'yarn':
      return reversibleRunner(rest);
    case 'zig':
      return rest[0] === 'build';
    default:
      return false;
  }
}

function reversibleGit(w: string[]): boolean {
  const sub = w[0];

  if (sub === 'status') {
    return true;
  }

  if (sub === 'remote') {
    return w.length === 2 && w[1] === '-v';
  }

  if (sub === 'worktree') {
    return w.length >= 2 && w[1] === 'list';
  }

  if (sub === 'fetch') {
    return reversibleFetch(w.slice(1));
  }

  return false;
}

const FETCH_FLAGS = new Set([
  '--all',
  '--tags',
  '-t',
  '--no-tags',
  '-n',
  '--quiet',
  '-q',
  '--verbose',
  '-v',
  '--dry-run',
  '--force',
  '-f',
  '--unshallow',
  '--update-shallow',
  '--progress',
  '--multiple',
  '--atomic',
  '--append',
  '-a',
  '--porcelain',
  '--show-forced-updates',
  '--no-show-forced-updates',
  '--write-fetch-head',
  '--no-write-fetch-head',
  '--set-upstream',
  '--refetch',
  '--prefetch',
  '--ipv4',
  '-4',
  '--ipv6',
  '-6',
  '--recurse-submodules',
  '--no-recurse-submodules',
]);
const FETCH_VALUE = [
  '--depth=',
  '--deepen=',
  '--shallow-since=',
  '--shallow-exclude=',
  '--jobs=',
  '--recurse-submodules=',
];
const GIT_SCHEMES = [
  'file',
  'git',
  'ssh',
  'git+ssh',
  'ssh+git',
  'http',
  'https',
];

function reversibleFetch(words: string[]): boolean {
  let ended = false;

  for (const value of words) {
    if (!ended && value === '--') {
      ended = true;

      continue;
    }

    if (!ended && value.startsWith('-')) {
      if (!(
        FETCH_FLAGS.has(value) || FETCH_VALUE.some((p) => value.startsWith(p))
      )) {
        return false;
      }

      continue;
    }

    if (namesRemoteHelper(value)) {
      return false;
    }
  }

  return true;
}

function namesRemoteHelper(value: string): boolean {
  let end = 0;

  while (end < value.length) {
    const c = value[end]!;
    const special = c === '+' || c === '-' || c === '.';

    if (!/[A-Za-z0-9]/.test(c) && (end === 0 || !special)) {
      break;
    }

    end++;
  }

  if (end === 0) {
    return false;
  }

  const rest = value.slice(end);

  if (rest.startsWith('::')) {
    return true;
  }

  if (!rest.startsWith('://')) {
    return false;
  }

  return !GIT_SCHEMES.includes(value.slice(0, end).toLowerCase());
}

const globalFlag = (w: string[]) =>
  w.some(
    (x) =>
      [
        '-g',
        '--global',
        '--location',
        '--location=global',
        '--prefix',
      ].includes(x) || x.startsWith('--prefix='),
  );

function reversibleNpm(w: string[]): boolean {
  if (w.length === 1 && (w[0] === '-v' || w[0] === '--version')) {
    return true;
  }

  if (w.length === 0) {
    return false;
  }

  if (['install', 'i', 'ci', 'test'].includes(w[0]!)) {
    return !globalFlag(w.slice(1));
  }

  return w[0] === 'run' && w.length >= 2;
}

function reversibleRunner(w: string[]): boolean {
  if (w.length === 1 && (w[0] === '-v' || w[0] === '--version')) {
    return true;
  }

  if (w.length === 0) {
    return false;
  }

  if (['install', 'test'].includes(w[0]!)) {
    return !globalFlag(w.slice(1));
  }

  return w[0] === 'run' && w.length >= 2;
}

function direct(source: string, line: Line | null): boolean {
  if (!line || !sourceOk(source, true)) {
    return false;
  }

  if (line.join === '&&') {
    return false;
  }

  if (line.stages.length > MAX_PIPE_STAGES) {
    return false;
  }

  for (const stage of line.stages) {
    if (!directStage(stage)) {
      return false;
    }
  }

  return true;
}

const MUTATE = [
  'touch',
  'rm',
  'mkdir',
  'rmdir',
  'mv',
  'cp',
  'install',
  'chmod',
  'chown',
  'ln',
];
const NETWORK = ['curl', 'wget', 'ssh', 'scp', 'nc'];
const PROCESS = [
  'sh',
  'bash',
  'zsh',
  'dash',
  'env',
  'xargs',
  'sudo',
  'doas',
  'kill',
  'pkill',
  'nohup',
];

function directShape(stage: Stage): boolean {
  if (
    stage.assigns > 0 ||
    stage.redirects.length > 0 ||
    stage.words.length === 0
  ) {
    return false;
  }

  for (const w of stage.words) {
    if (
      !w.literal ||
      UNQUOTED_DIRECT.test(w.unquoted) ||
      /[$`\\\n]/.test(w.dquoted) ||
      zshEquals(w)
    ) {
      return false;
    }
  }

  return true;
}

function directStage(stage: Stage): boolean {
  if (!directShape(stage)) {
    return false;
  }

  const words = stage.words.map((w) => w.value);
  const cmd = words[0]!;

  if (cmd.includes('=')) {
    return false;
  }

  if (MUTATE.includes(cmd) || NETWORK.includes(cmd) || PROCESS.includes(cmd)) {
    return false;
  }

  switch (cmd) {
    case 'printf':
      return directPrintf(words);
    case 'pwd':
      return words.length === 1 || (words.length === 2 && words[1] === '-P');
    case 'ls':
      return directLs(words);
    case 'wc':
      return words
        .slice(1)
        .every(
          (w) =>
            w.length >= 2 &&
            w[0] === '-' &&
            [...w.slice(1)].every((f) => 'Lclmw'.includes(f)),
        );
    case 'cat':
      return words.length === 1;
    case 'head':
    case 'tail':
      return (
        words.length === 1 ||
        (words.length === 3 && words[1] === '-n' && bounded(words[2]!, 10_000))
      );
    case 'grep':
      return directGrep(words);
    case 'git':
      return directGit(words);
    default:
      return false;
  }
}

function directPrintf(words: string[]): boolean {
  if (words.length < 2) {
    return false;
  }

  const format = words[1]!;

  if (format.length === 0 || format[0] === '-') {
    return false;
  }

  let count = 0;

  for (let i = 0; i < format.length;) {
    const c = format.charCodeAt(i);

    if (c < 0x20 || c > 0x7e) {
      return false;
    }

    if (format[i] === '\\') {
      if (format[i + 1] !== 'n') {
        return false;
      }

      i += 2;

      continue;
    }

    if (format[i] === '%') {
      const n = format[i + 1];

      if (n === 's') {
        count++;
      } else if (n !== '%') {
        return false;
      }

      i += 2;

      continue;
    }

    i++;
  }

  return words.length - 2 === count;
}

function directLs(words: string[]): boolean {
  let options = true;
  let separator = false;
  let operands = 0;

  for (const w of words.slice(1)) {
    if (options && w === '--') {
      options = false;
      separator = true;

      continue;
    }

    if (options && w.length > 1 && w[0] === '-') {
      if (![...w.slice(1)].every((f) => '1aAdFlnp'.includes(f))) {
        return false;
      }

      continue;
    }

    options = false;

    if (!separator && w.length > 1 && w[0] === '-') {
      return false;
    }

    operands++;
  }

  return operands <= 64;
}

function directGrep(words: string[]): boolean {
  let i = 1;

  for (; i < words.length; i++) {
    const w = words[i]!;

    if (w === '--') {
      i++;
      break;
    }

    if (w.length <= 1 || w[0] !== '-') {
      break;
    }

    if (![...w.slice(1)].every((f) => 'EFinv'.includes(f))) {
      return false;
    }
  }

  return i < words.length && words.length - i === 1;
}

function bounded(v: string, max: number): boolean {
  return /^[0-9]+$/.test(v) && Number(v) <= max;
}

function directGit(words: string[]): boolean {
  const [, sub, ...args] = words;

  if (sub === 'status') {
    const ok = [
      '-s',
      '-b',
      '--short',
      '--branch',
      '--porcelain',
      '--porcelain=v1',
      '--untracked-files=no',
      '--untracked-files=normal',
      '--untracked-files=all',
    ];

    return args.every((a) => ok.includes(a));
  }

  if (sub === 'diff' || sub === 'log') {
    const diffOk = [
      '--cached',
      '--staged',
      '--stat',
      '--shortstat',
      '--numstat',
      '--name-only',
      '--name-status',
      '--check',
      '--no-renames',
    ];
    const logOk = [
      '--oneline',
      '--stat',
      '--shortstat',
      '--name-only',
      '--name-status',
      '--no-merges',
      '--decorate',
      '--decorate=short',
      '--decorate=no',
    ];
    let i = 0;

    for (; i < args.length && args[i] !== '--'; i++) {
      const a = args[i]!;

      if (sub === 'log' && a === '-n') {
        if (!bounded(args[i + 1] ?? '', 1000)) {
          return false;
        }

        i++;
        continue;
      }

      if (sub === 'log' && a.startsWith('--max-count=')) {
        if (!bounded(a.slice('--max-count='.length), 1000)) {
          return false;
        }

        continue;
      }

      if (!(sub === 'diff' ? diffOk : logOk).includes(a)) {
        return false;
      }
    }

    return (i < args.length ? args.length - i - 1 : 0) <= 64;
  }

  return false;
}

function canonicalStage(stage: Stage): DirectStage {
  const [command, ...args] = stage.words.map((w) => w.value);
  const executable =
    command === 'pwd' || command === 'ls' || command === 'cat'
      ? `/bin/${command}`
      : `/usr/bin/${command}`;
  let canonical = args;

  switch (command) {
    case 'pwd':
      canonical = ['-P'];

      break;
    case 'ls': {
      const flags: string[] = ['-q'];
      const operands: string[] = [];
      let options = true;

      for (const arg of args) {
        if (options && arg === '--') {
          options = false;

          continue;
        }

        if (options && arg.length > 1 && arg.startsWith('-')) {
          flags.push(
            ...[...arg.slice(1)].map((f) => `-${f === 'l' ? 'n' : f}`),
          );
        } else {
          options = false;

          operands.push(arg);
        }
      }

      canonical = [...flags, '--', ...operands];

      break;
    }
    case 'wc':
      canonical = args.flatMap((a) => [...a.slice(1)].map((f) => `-${f}`));

      break;
    case 'head':
    case 'tail':
      canonical = ['-n', args[1] ?? '10'];

      break;
    case 'grep': {
      const flags: string[] = [];

      for (const arg of args.slice(0, -1)) {
        if (arg !== '--') {
          flags.push(...[...arg.slice(1)].map((f) => `-${f}`));
        }
      }

      canonical = [...flags, '--', args.at(-1)!];

      break;
    }
    case 'git': {
      const [sub, ...rest] = args;

      if (sub === 'status') {
        canonical = [
          sub,
          ...rest.map((a) =>
            a === '-s' ? '--short' : a === '-b' ? '--branch' : a,
          ),
        ];
      } else {
        canonical = [
          sub!,
          '--color=never',
          ...(sub === 'log' ? ['--max-count=100'] : []),
          ...rest,
        ];

        if (!rest.includes('--')) {
          canonical.push('--');
        }
      }
    }
  }

  return {
    executable,
    argv: [executable, ...canonical],
    git: command === 'git',
  };
}
