// Writes fzf_golden.json: what fzf-for-js 0.5.2, the matcher chord uses,
// answers for the cases below. The Dart port's tests compare against the
// file and never run this.
//
//   bun test/text/fzf_golden.mjs
//
// from packages/chord_tui, with chord's dependencies installed in the
// checkout CHORD_SOURCE names, otherwise in ../../../chord, the chord
// checkout beside the main one (a worktree sets CHORD_SOURCE).
import { execFileSync } from 'node:child_process';
import { existsSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';

const source = resolve(process.env.CHORD_SOURCE ?? '../../../chord');
const fzfModule = `${source}/node_modules/fzf/dist/fzf.es.js`;
if (!existsSync(fzfModule)) {
  console.error(
    `No chord checkout with its dependencies at ${source}: set CHORD_SOURCE ` +
      'to a chord checkout where bun install has run.',
  );
  process.exit(1);
}
const { Fzf, byLengthAsc } = await import(fzfModule);

const chordFiles = execFileSync('git', ['-C', source, 'ls-files', 'src', 'tests'], {
  encoding: 'utf8',
})
  .split('\n')
  .filter(Boolean)
  .sort()
  .slice(0, 400);

const commands = [
  'clear', 'config', 'context', 'cost', 'effort', 'fast', 'fork', 'help', 'mcp',
  'model', 'new', 'rename', 'resume', 'status', 'team', 'theme', 'vim', 'exit',
  'compact', 'review', 'init', 'pr-comments', 'security-review',
  'mcp__fs__read', 'AddDir', 'export',
];

const words = 'alpha beta gamma delta epsilon zeta theta iota kappa lambda'.split(' ');
const long = Array.from({ length: 300 }, (_, i) => words[i % words.length]).join('/');

const unicode = [
  'café.md', 'café nfd.md', 'Ångström.txt', 'naïve_parser.ts',
  'Ặng Việt.txt', 'Straße.md', 'ŁódźMap.ts', '日本語ファイル.md', 'Ελληνικά.txt',
  '🙂 smile.txt', 'emoji🙂in🙂name.ts', 'v2Release', 'file_123', 'getHTTPResponse',
  'snake_case_name', 'kebab-case-name', 'CamelCaseName', 'x', 'İstanbul.md',
  'ﬁle ligature', 'ＡＢＣ fullwidth', '½ half', 'Ⅻ roman', long,
];

const ties = Array.from({ length: 12 }, (_, i) => `t${'x'.repeat(i % 4)}/tie${i}`);

const cases = [
  {
    name: 'commands',
    items: commands,
    options: { casing: 'case-insensitive' },
    queries: ['', 'c', 'co', 'cmp', 'rev', 'MCP', 'pr', 'sr', 'x', 'mfr', 'ad', 'zz', 'contextual'],
  },
  {
    name: 'files',
    items: chordFiles,
    options: { casing: 'case-insensitive', limit: 100, byLength: true },
    queries: ['', 'ui', 'msg', 'Mention', 'src/ui', 'appts', 'test', 'acp', 'tsx', 'pmt', 'zzzq', 'a', 'srcuiprompt'],
  },
  {
    name: 'unicode, smart case',
    items: unicode,
    options: {},
    queries: ['cafe', 'café', 'café', 'angstrom', 'Ång', 'naive', 'ang viet', 'strase', 'lodz', 'Map',
      '日本', 'ファイル', 'ελλ', 'smile', '🙂', 'emojiin', 'v2', 'r2', '123', 'HTTP', 'http', 'gHR', 'sc',
      'kc', 'ccn', 'CCN', 'istanbul', 'İst', 'file', 'abc', 'half', 'alpha', 'alphazetalambda',
      'alpha/beta/gamma/delta/epsilon/zeta/theta/iota/kappa/lambda/al', 'q'],
  },
  {
    name: 'unicode, case-sensitive',
    items: unicode,
    options: { casing: 'case-sensitive' },
    queries: ['cafe', 'Map', 'map', 'HTTP', 'CCN', 'ccn'],
  },
  {
    name: 'special casing',
    items: ['İstanbul', 'istanbul', 'i\u0307stanbul', 'ΟΔΟΣ', 'οδος', 'οδοσ', 'ΟΔΟΣ ΔΥΟ', 'ΣΑ'],
    options: { casing: 'case-insensitive' },
    queries: ['İ', 'İst', 'i', 'ΟΔΟΣ', 'ΟΔΟΣ Δ', 'οδοσ', 'οδος', 'Σ', 'ΣΑ', 'ΑΣ.', "Σ'Σ"],
  },
  {
    name: 'special casing, smart case',
    items: ['İstanbul', 'istanbul', 'ΟΔΟΣ', 'οδος'],
    options: {},
    queries: ['İ', 'ΟΔΟΣ', 'οδος'],
  },
  {
    name: 'ties cut by score groups',
    items: ties,
    options: { casing: 'case-insensitive', limit: 3, byLength: true },
    queries: ['tie', 't', 'tx'],
  },
];

// Upstream reuses one scratch slab without clearing it, and a stale cell
// can move a reported start and positions (never a score or the order).
// Each result's start and positions are taken again from a fresh copy of
// the module, matching the port, which clears its arrays.
let copies = 0, stale = 0;
async function fresh(item, query, casing) {
  const { Fzf: FreshFzf } = await import(
    `${source}/node_modules/fzf/dist/fzf.es.js?copy=${copies++}`
  );
  const [r] = new FreshFzf([item], { casing }).find(query);
  return [r.start, [...r.positions].sort((a, b) => a - b)];
}

const out = [];
for (const { name, items, options, queries } of cases) {
  const fzf = new Fzf(items, {
    casing: options.casing ?? 'smart-case',
    ...(options.limit ? { limit: options.limit } : {}),
    ...(options.byLength ? { tiebreakers: [byLengthAsc] } : {}),
  });
  const results = {};
  for (const q of queries) {
    results[q] = [];
    for (const r of fzf.find(q)) {
      let start = r.start, positions = [...r.positions].sort((a, b) => a - b);
      if (q !== '') {
        const [freshStart, freshPositions] = await fresh(r.item, q, options.casing ?? 'smart-case');
        if (freshStart !== start || freshPositions.join() !== positions.join()) stale++;
        [start, positions] = [freshStart, freshPositions];
      }
      results[q].push([items.indexOf(r.item), r.score, start, r.end, positions]);
    }
  }
  out.push({ name, items, options, results });
}
console.log(`${stale} results had stale-slab positions`);

writeFileSync(new URL('./fzf_golden.json', import.meta.url), JSON.stringify(out));
