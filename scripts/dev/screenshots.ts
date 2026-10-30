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
 * `logo` takes the README's two logos the same way: the title page in each
 * theme, kept to its art, with no window and a transparent background.
 *
 * Chrome is the system's: `CHROME` names its binary where it is not at
 * macOS's usual place.
 */
import { spawnSync } from 'node:child_process';
import { mkdir, readdir, readFile, rm, writeFile } from 'node:fs/promises';
import { join } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { AnsiUp } from 'ansi_up';
import puppeteer from 'puppeteer-core';
import { quote } from 'shell-quote';
import sliceAnsi from 'slice-ansi';
import stripAnsi from 'strip-ansi';
import { TAGLINE } from '../../src/ui/app/start_layout.ts';

/** What a shot does to the window before it is taken. */
type Step =
  | { readonly type: string }
  | { readonly keys: readonly string[] }
  | { readonly until: string }
  | { readonly wait: number }
  /** chord gone from its pane, as a `/exit` leaves it. */
  | { readonly exited: true }
  /** The sessions recorded so far aged, the latest first, by these hours. */
  | { readonly aged: readonly number[] }
  /** chord started again in the same pane and home, with these arguments. */
  | { readonly respawn: readonly string[] };

export interface Shot {
  /** The file under docs/images, without `.png`. */
  readonly name: string;
  /** The fake agent's scenario for every prompt that names none. */
  readonly scenario: string;
  /** chord's arguments; `claude` by default, as an unnamed start asks first. */
  readonly args?: readonly string[];
  /** What chord's first screen shows; the prompt's hint by default. */
  readonly first?: string;
  /** More of chord's environment. */
  readonly env?: readonly string[];
  /** The settings' theme; `dark` by default. */
  readonly theme?: 'dark' | 'light';
  /** Which group of shots a name on the command line also takes it by. */
  readonly group?: 'logo';
  readonly steps: readonly Step[];
  /** Whether the project has the `bugfix` team saved; it has by default. */
  readonly team?: boolean;
}

/** A prompt typed and sent. */
function prompt(text: string): Step[] {
  return [{ type: text }, { keys: ['Enter'] }];
}

export const SHOTS: readonly Shot[] = [
  {
    // Nothing picked, so no agent starts. The system's own PATH leaves out
    // every own CLI on the machine that takes it, so the list is the same
    // on any.
    name: 'start',
    scenario: 'text',
    args: [],
    first: 'Select agent',
    env: ['PATH=/usr/bin:/bin'],
    steps: [],
  },
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
    // The agents beside the main one, under the prompt: `docs` waits on a
    // permission, which the status line names with the key that goes there.
    name: 'agents',
    // parser told nothing, so main is idle once its first turn ends.
    scenario: 'agentsquiet',
    steps: [
      ...prompt('Fix the parser, and have the README say what changed'),
      { until: 'docs needs your permission' },
      { until: 'Waiting on parser.' },
      { wait: 4000 },
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
      ...prompt('/exit'),
      { exited: true },
      // Taken one after another, they would all say "just now".
      { aged: [2, 26, 75] },
      { respawn: ['--resume'] },
      { until: 'Resume a session' },
    ],
  },
  {
    // A reply's code blocks, each with its [copy], and [run] on a command.
    name: 'codeblocks',
    scenario: 'markdown',
    steps: [
      ...prompt('Walk me through landing a change'),
      { until: 'built $bin' },
      { until: 'context used' },
    ],
  },
  {
    // The conversation so far goes on in a fork, picked at once, its row in
    // the agents list beside main.
    name: 'fork',
    scenario: 'edit',
    steps: [
      ...prompt('Greet people by name with a template literal'),
      { until: 'context used' },
      ...prompt('/fork arrow-function'),
      { until: 'forked from main' },
    ],
  },
];

/** The title page's art, for the README: its own colours on no background. */
const LOGOS: readonly Shot[] = (['dark', 'light'] as const).map((theme) => ({
  name: `logo-${theme}`,
  scenario: 'text',
  args: [],
  first: TAGLINE,
  theme,
  group: 'logo',
  steps: [],
}));

const ROOT = new URL('../..', import.meta.url).pathname;
const IMAGES = join(ROOT, 'docs', 'images');
const CHROME =
  process.env['CHROME'] ??
  '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';
/** The terminal's size; `proposal` is the tallest shot, and fits in this. */
const COLUMNS = 120;
const ROWS = 37;
const SOCKET = `chord-screenshots-${String(process.pid)}`;
/** The art of the title page's `full` step. */
const LOGO_COLUMNS = 57;
const LOGO_ROWS = 8;

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

async function exited(shot: string): Promise<void> {
  const end = Date.now() + 30_000;

  while (tmux('display', '-p', '-t', 'shot', '#{pane_dead}').trim() !== '1') {
    if (Date.now() > end) {
      throw new Error(`${shot}: chord never left.\n${screen()}`);
    }

    await sleep(100);
  }
}

/**
 * The records in `dir` that hold a prompt, the latest first, each aged by its
 * of `hours`: every time it says goes back by as much.
 */
async function aged(dir: string, hours: readonly number[]): Promise<void> {
  const records = await Promise.all(
    (await readdir(dir)).map(async (file) => {
      const lines = (await readFile(join(dir, file), 'utf8'))
        .split('\n')
        .filter((line) => line !== '')
        .map((line) => JSON.parse(line) as { type: string; at?: number });

      return { path: join(dir, file), lines };
    }),
  );
  const sessions = records
    .filter(({ lines }) => lines.some(({ type }) => type === 'prompt'))
    .toSorted(
      (a, b) =>
        Math.max(...b.lines.map(({ at }) => at ?? 0)) -
        Math.max(...a.lines.map(({ at }) => at ?? 0)),
    );

  await Promise.all(
    sessions.map(({ path, lines }, index) => {
      const back = (hours[index] ?? 0) * 3_600_000;

      return writeFile(
        path,
        lines
          .map((line) =>
            JSON.stringify(
              line.at === undefined ? line : { ...line, at: line.at - back },
            ),
          )
          .join('\n') + '\n',
      );
    }),
  );
}

/** A home of chord's own, where the settings and the project are the shot's. */
async function world(
  dir: string,
  team: boolean,
  theme: 'dark' | 'light',
): Promise<string> {
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
      theme,
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
    const home = await world(dir, shot.team ?? true, shot.theme ?? 'dark');
    const env = [
      `HOME=${home}`,
      `XDG_CONFIG_HOME=${join(home, '.config')}`,
      `XDG_STATE_HOME=${join(dir, 'state')}`,
      'COLORTERM=truecolor',
      `CHORD_FAKE_SCENARIO=${shot.scenario}`,
      'CHORD_FAKE_STEP_MS=40',
      // It offers `session/fork`, as the fork shot's `/fork` asks, and the
      // `auto` mode the team's coder is on.
      'CHORD_FAKE_FORK=1',
      'CHORD_FAKE_AUTO_MODE=1',
      // The children a scenario opens run on codex, a name the settings give
      // the fake, on its model, opened on a person's words.
      'CHORD_FAKE_CHILD_RUNTIME=codex',
      'CHORD_FAKE_CHILD_MODEL=gpt-6.1-sol',
      // A fork stays on its source's model, main's in the fork shot.
      'CHORD_FAKE_FORK_MODEL=claude-opus-5-5',
      `CHORD_FAKE_SAID=${JSON.stringify({
        agentchild: 'Run the parser tests and fix what fails',
        permission: 'Say in the README what changed',
      })}`,
    ];
    const chord = (args: readonly string[]) =>
      `exec env ${quote([
        ...env,
        ...(shot.env ?? []),
        process.execPath,
        '--define',
        'process.env.NODE_ENV:"production"',
        join(ROOT, 'src', 'main.tsx'),
        ...args,
        '-C',
        join(home, 'src', 'app'),
      ])}`;

    tmux(
      'new-session',
      '-d',
      '-s',
      'shot',
      '-x',
      String(COLUMNS),
      '-y',
      String(ROWS),
      chord(shot.args ?? ['claude']),
    );
    tmux('set', '-g', 'default-terminal', 'tmux-256color');
    tmux('set', '-as', 'terminal-overrides', ',*:RGB');
    // Its pane outlives a chord that leaves, for a `respawn` to start in.
    tmux('set', '-w', '-t', 'shot', 'remain-on-exit', 'on');
    await until(shot.first ?? 'for shortcuts', shot.name);

    for (const step of shot.steps) {
      if ('type' in step) {
        tmux('send-keys', '-t', 'shot', '-l', step.type);
        await sleep(300);
      } else if ('keys' in step) {
        tmux('send-keys', '-t', 'shot', ...step.keys);
        await sleep(300);
      } else if ('until' in step) {
        await until(step.until, shot.name);
      } else if ('exited' in step) {
        await exited(shot.name);
      } else if ('aged' in step) {
        await aged(join(dir, 'state', 'chord', 'records'), step.aged);
      } else if ('respawn' in step) {
        tmux('respawn-pane', '-k', '-t', 'shot', chord(step.respawn));
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

/**
 * The title page's art out of a captured frame: the rows above the tagline's
 * gap, from the art's left edge, with their colours. So the logo cannot drift
 * from what chord draws.
 */
export function logoRows(frame: string): string[] {
  const rows = frame.split('\n');
  const tagline = rows.findIndex((row) => stripAnsi(row).includes(TAGLINE));

  if (tagline < LOGO_ROWS + 1) {
    throw new Error('The frame has no title page art above its tagline.');
  }

  const art = rows.slice(tagline - 1 - LOGO_ROWS, tagline - 1);
  const left = Math.min(
    ...art.map((row) => stripAnsi(row).search(/\S/u)).filter((at) => at >= 0),
  );

  return art.map((row) => sliceAnsi(row, left, left + LOGO_COLUMNS));
}

/** Rows as HTML, the terminal's colours kept inline. */
function rowsHtml(frame: readonly string[]): string {
  const ansi = new AnsiUp();

  ansi.use_classes = false;

  return frame
    .map((line) => `<div class="row">${ansi.ansi_to_html(line) || ' '}</div>`)
    .join('');
}

const FONT = `
  @font-face { font-family: Term; src: local('JetBrains Mono'), local('JetBrainsMono-Regular'); }
  @font-face { font-family: Term; font-weight: bold; src: local('JetBrains Mono Bold'), local('JetBrainsMono-Bold'); }
`;

/**
 * A logo alone, nothing behind it, its cell a whole 12×24 pixels: the shots'
 * fractional cell leaves seams between the block glyphs, which show on white.
 */
function logoPage(frame: string): string {
  return `<!doctype html>
<meta charset="utf-8">
<style>
  ${FONT}
  html, body { margin: 0; background: transparent; }
  .page {
    display: inline-block; width: ${String(LOGO_COLUMNS)}ch;
    font: 20px/24px Term, Menlo, monospace; white-space: pre;
    font-variant-ligatures: none;
  }
  .row { height: 24px; }
</style>
<div class="page">${rowsHtml(logoRows(frame))}</div>`;
}

function page(frame: string): string {
  const rows = rowsHtml(frame.replace(/\n$/u, '').split('\n'));

  return `<!doctype html>
<meta charset="utf-8">
<style>
  ${FONT}
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
    /* The whole window: a capture ends each row at its last cell drawn, and a
       centred page has no row that reaches the edge. */
    width: ${String(COLUMNS)}ch;
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

    for (const shot of [...SHOTS, ...LOGOS]) {
      if (
        only.size > 0 &&
        !only.has(shot.name) &&
        (shot.group === undefined || !only.has(shot.group))
      ) {
        continue;
      }

      const frame = await capture(shot);

      await tab.setContent(
        shot.group === 'logo' ? logoPage(frame) : page(frame),
        {
          waitUntil: 'load',
        },
      );
      await tab.evaluate(() => document.fonts.ready);

      const element = await tab.$('.page');

      if (element === null) {
        throw new Error(`${shot.name}: nothing was drawn.`);
      }

      // Square and opaque, the backdrop to the picture's edge; a logo has
      // none, for the page it sits on.
      await element.screenshot({
        path: join(IMAGES, `${shot.name}.png`),
        omitBackground: shot.group === 'logo',
      });
      console.log(`docs/images/${shot.name}.png`);
    }
  } finally {
    await browser.close();
  }
}
