/**
 * Take the README's screenshots from chord itself.
 *
 *   bun dev screenshots [name…]   rewrite docs/images/*.png, or those named
 *
 * Each shot runs chord from source in a tmux session of its own, `COLUMNS`
 * × `ROWS`, on
 * the fake agent in tests/fixtures/, as `bun dev chord --fake` does, types
 * what a person would, waits for the state the shot shows, and reads the
 * screen back with its colours (`capture-pane -e`). The frame is then drawn
 * in a Chorded terminal pane in Chrome (puppeteer-core) through ansi_up and
 * captured at twice its size. chord lays the screen out itself, so every
 * shot is the same size; `ROWS` is the fewest that hold the tallest whole.
 *
 * chord runs in a home of its own under a temporary directory, so nothing
 * of the person's settings, records or teams reaches a shot. There the
 * settings name the fake agent `claude` and `codex`, on Claude Opus 5.5 and
 * GPT-6.1 Sol, which its `--tokens-only` offers, the team the shots run is
 * `screenshots_team.md` beside this script, whose lead opens all three of
 * its members, `/team new` proposes the same team in short from
 * `screenshots_proposal.md`, so the whole proposal fits, and the scenario each shot
 * plays comes from `CHORD_FAKE_SCENARIO`, so the prompt typed can be a
 * person's words.
 *
 * Chrome is the system's: `CHROME` names its binary where it is not at
 * macOS's usual place.
 */
import { spawnSync } from 'node:child_process';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { AnsiUp } from 'ansi_up';
import puppeteer from 'puppeteer-core';
import { quote } from 'shell-quote';

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

const ROOT = new URL('../..', import.meta.url).pathname;
const IMAGES = join(ROOT, 'docs', 'images');
const CHROME =
  process.env['CHROME'] ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
/** The terminal's size; `proposal` is the tallest shot, and fits in this. */
const COLUMNS = 120;
const ROWS = 37;
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
  const teamFile = join(ROOT, 'scripts', 'dev', 'screenshots_team.md');
  // Its team's lead opens every member, reviewer too, and a proposal is
  // the same team in short, so the whole of it fits the frame.
  const fake = quote([
    process.execPath,
    join(ROOT, 'tests', 'fixtures', 'fake_agent', 'main.ts'),
    '--tokens-only',
    '--lead-opens',
    'tester,coder,reviewer',
    '--propose-team',
    join(ROOT, 'scripts', 'dev', 'screenshots_proposal.md'),
  ]);

  await mkdir(join(home, '.config', 'chord'), { recursive: true });
  await mkdir(join(project, '.chord', 'teams'), { recursive: true });
  await writeFile(
    join(home, '.config', 'chord', 'settings.json'),
    JSON.stringify({
      theme: 'dark',
      agent: 'claude',
      agents: {
        claude: { command: fake, model: 'claude-opus-5-5' },
        codex: { command: fake, model: 'gpt-6.1-sol' },
      },
    }),
  );

  if (team) {
    // The shots' own team, beside this script, on the two names the
    // settings give the fake.
    await writeFile(
      join(project, '.chord', 'teams', 'bugfix.md'),
      await readFile(teamFile, 'utf8'),
    );
  }

  return home;
}

/** The shot's screen as chord drew it, with its colours. */
async function capture(shot: Shot): Promise<string> {
  // A fixed, neutral place, never the system's per-user temp directory,
  // so no path of a person's machine can reach a shot, whatever chord
  // shows of its directory (CHD-427).
  const dir = `/tmp/chord-shot.${shot.name}`;

  await rm(dir, { recursive: true, force: true });
  await mkdir(dir, { recursive: true });

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
      String(COLUMNS),
      '-y',
      String(ROWS),
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

function page(frame: string): string {
  const ansi = new AnsiUp();

  ansi.use_classes = false;

  const rows = frame
    .replace(/\n$/u, '')
    .split('\n')
    .map((line) => `<div class="row">${ansi.ansi_to_html(line) || ' '}</div>`)
    .join('');

  return `<!doctype html>
<meta charset="utf-8">
<style>
  @font-face { font-family: Term; src: local('JetBrains Mono'), local('JetBrainsMono-Regular'); }
  @font-face { font-family: Term; font-weight: bold; src: local('JetBrains Mono Bold'), local('JetBrainsMono-Bold'); }
  html, body { margin: 0; background: transparent; }
  /* The window on a gradient, as Chorded's own pictures show it (CHD-407). */
  .page {
    padding: 64px 72px 88px; display: inline-block; position: relative;
    overflow: hidden; isolation: isolate;
    background: linear-gradient(135deg, #2b3a8c 0%, #6a4bc4 38%, #c46aa8 70%, #f2a17a 100%);
  }
  /* Chorded's window: a metal rim around a dark pane, its corners round; the
     rim lets the backdrop through a little, the pane does not. */
  .rim {
    padding: 7px; border-radius: 38px;
    background: linear-gradient(180deg, rgba(142, 144, 149, 0.55) 0%, rgba(93, 95, 100, 0.55) 45%, rgba(58, 59, 64, 0.55) 100%);
    backdrop-filter: blur(24px) saturate(1.6);
    box-shadow:
      0 0 0 1px rgba(0, 0, 0, 0.55),
      0 24px 48px rgba(0, 0, 0, 0.28),
      0 8px 16px rgba(0, 0, 0, 0.18);
  }
  .window {
    background: ${BACKGROUND};
    border-radius: 31px;
    box-shadow: inset 0 0 0 1px rgba(0, 0, 0, 0.6);
    overflow: hidden;
  }
  .bar {
    height: 50px; display: flex; align-items: center; gap: 14px;
    padding: 0 22px 0 24px;
    font-family: -apple-system, 'SF Pro Text', 'Helvetica Neue', sans-serif;
  }
  .bar svg { flex: none; }
  .lights { display: flex; gap: 8px; flex: none; margin-right: 4px; }
  .lights i { width: 12px; height: 12px; border-radius: 50%; box-shadow: inset 0 0 0 0.5px rgba(0, 0, 0, 0.25); }
  .title { font-size: 15px; font-weight: 500; color: #ececec; }
  .screen {
    padding: 2px 22px 22px; color: ${FOREGROUND};
    font: 13.5px/1.3 Term, Menlo, monospace; white-space: pre;
    font-variant-ligatures: none;
  }
  .row { height: 1.3em; }
</style>
<div class="page"><div class="rim"><div class="window">
  <div class="bar">
    <span class="lights"><i style="background: #ff5f57"></i><i style="background: #febc2e"></i><i style="background: #28c840"></i></span>
    <svg width="22" height="18" viewBox="0 0 22 18" fill="none" stroke="#c9cacd" stroke-width="1.5">
      <rect x="1" y="1" width="20" height="16" rx="3.5"/><line x1="8" y1="1" x2="8" y2="17"/>
      <line x1="3.5" y1="5" x2="5.5" y2="5" stroke-linecap="round"/><line x1="3.5" y1="8" x2="5.5" y2="8" stroke-linecap="round"/>
    </svg>
    <div class="title">Chorded</div>
  </div>
  <div class="screen">${rows}</div>
</div></div></div>`;
}

/** Retakes every shot, or only the ones `names` lists. */
export async function screenshots(names: readonly string[]): Promise<void> {
  const only = new Set(names);
  const browser = await puppeteer.launch({ executablePath: CHROME });

  try {
    await mkdir(IMAGES, { recursive: true });

    const tab = await browser.newPage();

    await tab.setViewport({ width: 1600, height: 1000, deviceScaleFactor: 2 });

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

      // Square and opaque, the backdrop to the picture's edge.
      await element.screenshot({ path: join(IMAGES, `${shot.name}.png`) });
      console.log(`docs/images/${shot.name}.png`);
    }
  } finally {
    await browser.close();
  }
}
