/**
 * Take the README's screenshots from chord itself.
 *
 *   bun run screenshots [name…]   rewrite docs/images/*.png, or those named
 *
 * Each shot runs chord from source in a tmux session of its own, 120×40, on
 * the fake agent in tests/fixtures/, as `bun run chord:fake` does, types
 * what a person would, waits for the state the shot shows, and reads the
 * screen back with its colours (`capture-pane -e`). The frame is then drawn
 * in a terminal window in Chrome (puppeteer-core) through ansi_up and
 * captured at twice its size. Runs of blank rows above the transcript are
 * folded to one, so a shot is as tall as what it shows.
 *
 * chord runs in a home of its own under a temporary directory, so nothing
 * of the person's settings, records or teams reaches a shot. There the
 * settings name the fake agent `claude` and `codex`, on the two real models
 * its `--tokens-only` offers, and the scenario each shot plays comes from
 * `CHORD_FAKE_SCENARIO`, so the prompt typed can be a person's words.
 *
 * Chrome is the system's: `CHROME` names its binary where it is not at
 * macOS's usual place.
 */
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, readFile, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { AnsiUp } from 'ansi_up';
import puppeteer from 'puppeteer-core';
import { quote } from 'shell-quote';
import stripAnsi from 'strip-ansi';

/** What a shot does to the window before it is taken. */
type Step =
  | { readonly type: string }
  | { readonly keys: readonly string[] }
  | { readonly until: string }
  | { readonly wait: number };

interface Shot {
  /** The file under docs/images, without `.png`. */
  readonly name: string;
  /** The fake agent's scenario for every prompt that names none. */
  readonly scenario: string;
  readonly steps: readonly Step[];
  /** Whether the project has the `bugfix` team saved; it has by default. */
  readonly team?: boolean;
}

/** A prompt typed and sent. */
function prompt(text: string): Step[] {
  return [{ type: text }, { keys: ['Enter'] }];
}

const SHOTS: readonly Shot[] = [
  {
    name: 'team',
    scenario: 'team',
    steps: [
      ...prompt('Hand issue 214 to the bugfix team'),
      { until: '● permission' },
    ],
  },
  {
    name: 'proposal',
    scenario: 'text',
    team: false,
    steps: [
      ...prompt(
        '/team new fix bugs the way we do by hand: a failing test first, then the fix on codex, then a review',
      ),
      { until: 'Save team bugfix?' },
    ],
  },
  {
    name: 'edit',
    scenario: 'edit',
    steps: [
      ...prompt('Greet people by name with a template literal'),
      { until: 'Edited.' },
    ],
  },
  {
    name: 'permission',
    scenario: 'permission',
    steps: [
      ...prompt('Write the release notes into notes.txt'),
      { until: 'Do you want to proceed?' },
    ],
  },
  {
    name: 'subagents',
    scenario: 'subagent',
    steps: [
      ...prompt(
        'Find where session updates are routed and where tool calls are drawn, in parallel',
      ),
      { until: 'Running 2 agents' },
      { wait: 1500 },
    ],
  },
  {
    name: 'tabs',
    scenario: 'edit',
    steps: [
      ...prompt('/new codex'),
      { until: '2 codex' },
      // The tab behind waits on a permission: the scenario's own name, as
      // the shot never shows that tab's prompt.
      { keys: ['C-x', '1'] },
      ...prompt('permission'),
      { until: 'Do you want to proceed?' },
      { keys: ['C-x', '2'] },
      { wait: 500 },
      ...prompt('Greet people by name with a template literal'),
      { until: 'Edited.' },
    ],
  },
  {
    name: 'resume',
    scenario: 'text',
    steps: [
      ...[
        'Explain src/ui/state.ts',
        'Add a --json flag to the agents command',
        "Tidy the README's install section",
      ].flatMap((text): Step[] => [
        ...prompt(text),
        { wait: 3000 },
        ...prompt('/clear'),
        { wait: 3000 },
      ]),
      ...prompt('/resume'),
      { until: 'Resume a session' },
    ],
  },
];

const ROOT = new URL('..', import.meta.url).pathname;
const IMAGES = join(ROOT, 'docs', 'images');
const CHROME =
  process.env['CHROME'] ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
const SOCKET = `chord-screenshots-${String(process.pid)}`;

/** The terminal's own colours behind and in front of chord. */
const BACKGROUND = '#16171b';
const FOREGROUND = '#e4e4e4';

function tmux(...argv: string[]): string {
  const run = spawnSync('tmux', ['-L', SOCKET, '-f', '/dev/null', ...argv], {
    encoding: 'utf8',
  });

  if (run.status !== 0) {
    throw new Error(`tmux ${argv[0] ?? ''}: ${run.stderr}`);
  }

  return run.stdout;
}

function screen(): string {
  return tmux('capture-pane', '-p', '-t', 'shot');
}

async function until(text: string, shot: string): Promise<void> {
  const end = Date.now() + 30_000;

  while (!screen().includes(text)) {
    if (Date.now() > end) {
      throw new Error(`${shot}: "${text}" never came.\n${screen()}`);
    }

    await sleep(100);
  }
}

/** A home of chord's own, where the settings and the project are the shot's. */
async function world(dir: string, team: boolean): Promise<string> {
  const home = join(dir, 'home');
  const project = join(home, 'src', 'app');
  const fake = quote([
    process.execPath,
    join(ROOT, 'tests', 'fixtures', 'fake_agent', 'main.ts'),
    '--tokens-only',
  ]);

  await mkdir(join(home, '.config', 'chord'), { recursive: true });
  await mkdir(join(project, '.chord', 'teams'), { recursive: true });
  await writeFile(
    join(home, '.config', 'chord', 'settings.json'),
    JSON.stringify({
      theme: 'dark',
      agent: 'claude',
      agents: {
        claude: { command: fake, model: 'claude-haiku-4-5' },
        codex: { command: fake, model: 'gpt-5.3-codex' },
      },
    }),
  );

  if (team) {
    // The fixture's team, on the two names the settings give the fake.
    const file = await readFile(
      join(ROOT, 'tests', 'fixtures', 'teams', 'fake', 'bugfix.md'),
      'utf8',
    );

    await writeFile(
      join(project, '.chord', 'teams', 'bugfix.md'),
      file
        .replace(
          /(name: coder\n[^\n]*\n)\s+agent: fake\n\s+model: fake-large/u,
          '$1    agent: codex\n    model: gpt-5.3-codex',
        )
        .replaceAll('agent: fake', 'agent: claude')
        .replaceAll(/model: fake-(large|small)/gu, 'model: claude-haiku-4-5'),
    );
  }

  return home;
}

/** The shot's screen as chord drew it, with its colours. */
async function capture(shot: Shot): Promise<string> {
  const dir = await mkdtemp(join(tmpdir(), 'chord-shot-'));

  try {
    const home = await world(dir, shot.team ?? true);
    const env = [
      `HOME=${home}`,
      `XDG_CONFIG_HOME=${join(home, '.config')}`,
      `XDG_STATE_HOME=${join(dir, 'state')}`,
      'COLORTERM=truecolor',
      `CHORD_FAKE_SCENARIO=${shot.scenario}`,
      'CHORD_FAKE_STEP_MS=40',
    ];
    const chord = [
      process.execPath,
      '--define',
      'process.env.NODE_ENV:"production"',
      join(ROOT, 'src', 'main.tsx'),
      '-C',
      join(home, 'src', 'app'),
    ];

    tmux(
      'new-session',
      '-d',
      '-s',
      'shot',
      '-x',
      '120',
      '-y',
      '40',
      `exec env ${quote([...env, ...chord])}`,
    );
    tmux('set', '-g', 'default-terminal', 'tmux-256color');
    tmux('set', '-as', 'terminal-overrides', ',*:RGB');
    await until('for shortcuts', shot.name);

    for (const step of shot.steps) {
      if ('type' in step) {
        tmux('send-keys', '-t', 'shot', '-l', step.type);
        await sleep(300);
      } else if ('keys' in step) {
        tmux('send-keys', '-t', 'shot', ...step.keys);
        await sleep(300);
      } else if ('until' in step) {
        await until(step.until, shot.name);
      } else {
        await sleep(step.wait);
      }
    }

    // What the last keys set off drawn, and the spinner's frame with it.
    await sleep(400);

    return tmux('capture-pane', '-p', '-e', '-t', 'shot');
  } finally {
    spawnSync('tmux', ['-L', SOCKET, 'kill-server']);
    await rm(dir, { recursive: true, force: true });
  }
}

/** Runs of two blank rows or more folded to one, and the ends trimmed. */
function fold(lines: readonly string[]): string[] {
  const blank = (line: string): boolean => stripAnsi(line).trim() === '';
  const kept: string[] = [];
  let run = 0;

  for (const line of lines) {
    run = blank(line) ? run + 1 : 0;

    if (run < 2) {
      kept.push(line);
    }
  }

  while (kept.length > 0 && blank(kept.at(-1) ?? '')) {
    kept.pop();
  }

  return kept;
}

function page(frame: string): string {
  const ansi = new AnsiUp();

  ansi.use_classes = false;

  const rows = fold(frame.replace(/\n$/u, '').split('\n'))
    .map((line) => `<div class="row">${ansi.ansi_to_html(line) || ' '}</div>`)
    .join('');

  return `<!doctype html>
<meta charset="utf-8">
<style>
  @font-face { font-family: Term; src: local('JetBrains Mono'), local('JetBrainsMono-Regular'); }
  @font-face { font-family: Term; font-weight: bold; src: local('JetBrains Mono Bold'), local('JetBrainsMono-Bold'); }
  html, body { margin: 0; background: transparent; }
  .page { padding: 28px; display: inline-block; }
  .window {
    background: ${BACKGROUND};
    border-radius: 12px;
    box-shadow: 0 0 0 1px #2a2c33, 0 18px 50px rgba(0, 0, 0, 0.35);
    overflow: hidden;
  }
  .bar {
    height: 34px; display: flex; align-items: center; position: relative;
    background: #22242a; border-bottom: 1px solid #2a2c33;
  }
  .lights { display: flex; gap: 8px; padding-left: 14px; }
  .lights i { width: 12px; height: 12px; border-radius: 50%; display: block; }
  .title {
    position: absolute; left: 0; right: 0; text-align: center;
    font: 500 12.5px -apple-system, 'Helvetica Neue', sans-serif; color: #8b9099;
  }
  .screen {
    padding: 14px 16px 18px; color: ${FOREGROUND};
    font: 13.5px/1.3 Term, Menlo, monospace; white-space: pre;
    font-variant-ligatures: none;
  }
  .row { height: 1.3em; }
</style>
<div class="page"><div class="window">
  <div class="bar">
    <div class="lights"><i style="background:#ff5f57"></i><i style="background:#febc2e"></i><i style="background:#28c840"></i></div>
    <div class="title">chord — ~/src/app</div>
  </div>
  <div class="screen">${rows}</div>
</div></div>`;
}

const only = new Set(process.argv.slice(2));
const browser = await puppeteer.launch({ executablePath: CHROME });

try {
  await mkdir(IMAGES, { recursive: true });

  const tab = await browser.newPage();

  await tab.setViewport({ width: 1400, height: 900, deviceScaleFactor: 2 });

  for (const shot of SHOTS) {
    if (only.size > 0 && !only.has(shot.name)) {
      continue;
    }

    await tab.setContent(page(await capture(shot)), { waitUntil: 'load' });
    await tab.evaluate(() => document.fonts.ready);

    const element = await tab.$('.page');

    if (element === null) {
      throw new Error(`${shot.name}: nothing was drawn.`);
    }

    await element.screenshot({
      path: join(IMAGES, `${shot.name}.png`),
      omitBackground: true,
    });
    console.log(`docs/images/${shot.name}.png`);
  }
} finally {
  await browser.close();
}
