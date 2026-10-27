/**
 * The long-run memory check (CHD-343): chord's window on the fake agent, a
 * team at work in it for as long as asked, its memory sampled and its heap
 * snapshotted over the run, and the first snapshot compared with the last.
 * Too slow for `bun check`, whose tests must end in seconds: memory that
 * grows only shows over minutes.
 *
 *   bun dev memory                        10 minutes from source
 *   bun dev memory --minutes 30 --snapshots 6
 *   bun dev memory --binary dist/bun-darwin-arm64/chord
 *   bun dev memory --development          React's development build
 *
 * chord runs in a tmux session of its own, 120×40, in a temporary directory
 * that holds the fake team `bugfix`, chord's state and an empty home and
 * configuration, so its records and snapshots are the run's and nobody's
 * else, and no one's keybindings or settings change what typing `soak` and
 * Enter does. The fake agent's `soak` hands
 * the team a job none of its agents ever finishes: main, the lead and both
 * members take turn after turn, each streaming a reply with a call, as long
 * as chord runs. Every `--sample-seconds` the script reads chord's resident
 * size, its footprint where macOS's `footprint` gives one (swapped pages
 * counted, as the owner's 5.3 GB was), and the bytes its session records
 * hold, which grow with the transcripts, and the turns each agent has
 * taken: a run whose four agents have not all taken turns within
 * `STARTUP_MS`, or whose turns stop for `STALL_MS`, fails rather than
 * report an idle window's memory. Every snapshot is chord's own, by
 * `SIGUSR2` (`src/platform/heap.ts`), with JSC's counts beside it. memlab
 * reads the first and the last snapshot: what grew by object type and name,
 * and the shortest path from a root to an example of each.
 *
 * The run's directory is kept, with `report.txt`, for the snapshots to be
 * opened in DevTools' Memory tab.
 *
 * Ctrl+C or SIGTERM, at any point, ends the run's tmux session and waits
 * for chord and every fake agent under it to exit, killing what has not
 * within `EXIT_MS`; memlab's own SIGINT listener only flushes its log.
 */
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, readdir, readFile, stat } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve } from 'node:path';
import { setTimeout as sleep } from 'node:timers/promises';
import { config, type IHeapNode, type IHeapSnapshot } from '@memlab/core';
import { getFullHeapFromFile } from '@memlab/heap-analysis';
import { quote } from 'shell-quote';
import type { HeapStats } from '../../src/platform/heap.ts';

/** `bun dev memory`'s options. */
export interface MemoryOptions {
  readonly minutes: number;
  readonly sampleSeconds: number;
  readonly snapshots: number;
  readonly stepMs: number;
  readonly binary?: string | undefined;
  readonly development: boolean;
}

const root = new URL('../..', import.meta.url).pathname;

/** One run of the check, as the comment at the top describes it. */
export async function memory(args: MemoryOptions): Promise<void> {
  const minutes = args.minutes;
  const sampleMs = args.sampleSeconds * 1000;
  const snapshots = Math.max(2, args.snapshots);

  const dir = await mkdtemp(join(tmpdir(), 'chord-memory-'));
  const state = join(dir, 'state');
  const heaps = join(state, 'chord', 'heaps');
  const records = join(state, 'chord', 'records');
  const work = join(dir, 'work');
  const session = `chord-memory-${process.pid}`;

  /** How long main, the lead and both members have to take their first turns. */
  const STARTUP_MS = 120_000;
  /** How long the agents together may go without a turn before the run fails. */
  const STALL_MS = 60_000;
  /** How long chord and its agents have to exit once asked, at each step. */
  const EXIT_MS = 10_000;
  /** The soak's agents, as `workload` names them, each of whom must take turns. */
  const AGENTS = ['main', 'lead', 'tester', 'coder'] as const;

  await mkdir(join(work, '.chord', 'teams'), { recursive: true });
  await mkdir(join(dir, 'home', '.config'), { recursive: true });
  await Bun.write(
    join(work, '.chord', 'teams', 'bugfix.md'),
    Bun.file(join(root, 'tests', 'fixtures', 'teams', 'fake', 'bugfix.md')),
  );

  // From source as `bun dev chord` runs it, React's production build defined
  // (CHD-344), unless the development build is what is measured.
  const chord =
    args.binary === undefined
      ? [
          process.execPath,
          ...(args.development
            ? []
            : ['--define', 'process.env.NODE_ENV:"production"']),
          join(root, 'src', 'main.tsx'),
        ]
      : [resolve(args.binary)];
  const env = [
    `HOME=${join(dir, 'home')}`,
    `XDG_CONFIG_HOME=${join(dir, 'home', '.config')}`,
    `XDG_STATE_HOME=${state}`,
    `CHORD_FAKE_STEP_MS=${args.stepMs}`,
  ];
  const fake = quote([
    process.execPath,
    join(root, 'tests', 'fixtures', 'fake_agent', 'main.ts'),
  ]);

  // Before the session exists, so no signal finds chord started and unowned.
  let started = false;
  let pid = 0;
  /** chord's descendants as last seen, by pid, with the command each ran. */
  const team = new Map<number, string>();
  let cleaned: Promise<string[]> | undefined;

  for (const [signal, code] of [
    ['SIGINT', 130],
    ['SIGTERM', 143],
  ] as const) {
    process.on(signal, () => {
      console.error(`\n${signal}: stopping chord and its agents`);
      void cleanUp().then((left) => {
        for (const line of left) {
          console.error(line);
        }

        console.error(dir);
        process.exit(code);
      });
    });
  }

  started = true;

  // `exec`, so the pane's process is chord itself and its pid is the pane's.
  tmux(
    'new-session',
    '-d',
    '-s',
    session,
    '-x',
    '120',
    '-y',
    '40',
    `exec env ${quote([...env, ...chord, 'fake', '--agent-command', fake, '-C', work])}`,
  );

  pid = Number(tmux('display', '-p', '-t', session, '#{pane_pid}'));

  interface Sample {
    readonly seconds: number;
    readonly rss: number;
    readonly footprint: number | undefined;
    readonly records: number;
    readonly turns: number;
  }

  const samples: Sample[] = [];
  const taken: { seconds: number; snapshot: string; stats: HeapStats }[] = [];
  const start = Date.now();
  const seconds = () => Math.round((Date.now() - start) / 1000);
  let turns: Map<string, Turns> = new Map();

  try {
    await until(() => screen().includes('for shortcuts'), 30_000, 'the window');
    tmux('send-keys', '-t', session, '-l', 'soak');
    await sleep(300);
    tmux('send-keys', '-t', session, 'Enter');
    // Two turns each, every one streamed: the soak's chains have gone round
    // once, so what is measured is the team at work and not a window idle.
    await until(
      async () => {
        turns = await workload();

        return AGENTS.every(
          (agent) =>
            (turns.get(agent)?.prompts ?? 0) >= 2 &&
            (turns.get(agent)?.chunks ?? 0) > 0,
        );
      },
      STARTUP_MS,
      'two streamed turns each from main, the lead, tester and coder',
      () => said(turns),
    );
    console.log(`at work: ${said(turns)}`);

    const end = start + minutes * 60_000;
    // The first after a minute's warm-up, so what starting allocates once is
    // not counted as growth; the last at the end.
    const warm = Math.min(60_000, (end - start) / 4);
    const at = Array.from(
      { length: snapshots },
      (_, i) => start + warm + ((end - start - warm) * i) / (snapshots - 1),
    );
    let moved = { at: Date.now(), turns: total(turns) };

    while (Date.now() < end || taken.length < snapshots) {
      if (!alive(pid)) {
        throw new Error(`chord (${pid}) exited:\n${screen()}`);
      }

      seen();

      turns = await workload();

      samples.push(await sample(total(turns)));
      console.log(row(samples.at(-1)!));

      if (total(turns) > moved.turns) {
        moved = { at: Date.now(), turns: total(turns) };
      } else if (Date.now() - moved.at > STALL_MS) {
        throw new Error(
          `no turn for ${STALL_MS / 1000} s (${said(turns)}):\n${screen()}`,
        );
      }

      if (taken.length < snapshots && Date.now() >= at[taken.length]!) {
        taken.push(await snapshot());
        console.log(`  snapshot ${taken.length} of ${snapshots}`);
      }

      await sleep(Math.min(sampleMs, Math.max(0, end - Date.now())));
    }
  } finally {
    // Said here as well, so a run that failed still says what it left.
    for (const line of await cleanUp()) {
      console.error(line);
    }
  }

  if ((await cleanUp()).length > 0) {
    throw new Error(`chord or its agents outlived the run: ${dir}`);
  }

  const report = [
    `chord ${chord.join(' ')}`,
    `${minutes} min, a sample every ${sampleMs / 1000} s, ${snapshots} snapshots`,
    `turns by the end: ${said(turns)}`,
    '',
    's\trss MB\tfootprint MB\trecords MB\tturns',
    ...samples.map(row),
    '',
    's\theap MB\textra MB\tobjects\tFunction\tError\tObject',
    ...taken.map(
      ({ seconds, stats }) =>
        `${seconds}\t${mb(stats.heap.heapSize)}\t${mb(
          stats.heap.extraMemorySize,
        )}\t${stats.heap.objectCount}\t${
          stats.heap.objectTypeCounts['Function'] ?? 0
        }\t${stats.heap.objectTypeCounts['Error'] ?? 0}\t${
          stats.heap.objectTypeCounts['Object'] ?? 0
        }`,
    ),
    '',
    ...(await compare(taken[0]!.snapshot, taken.at(-1)!.snapshot)),
  ].join('\n');

  await Bun.write(join(dir, 'report.txt'), `${report}\n`);
  console.log(`\n${report}\n\n${dir}`);

  function tmux(...argv: string[]): string {
    const run = spawnSync('tmux', argv, { encoding: 'utf8' });

    if (run.status !== 0) {
      throw new Error(`tmux ${argv[0]}: ${run.stderr}`);
    }

    return run.stdout.trim();
  }

  function screen(): string {
    return spawnSync('tmux', ['capture-pane', '-t', session, '-p'], {
      encoding: 'utf8',
    }).stdout;
  }

  function alive(of: number): boolean {
    try {
      process.kill(of, 0);

      return true;
    } catch {
      return false;
    }
  }

  async function until(
    done: () => boolean | Promise<boolean>,
    ms: number,
    what: string,
    so: () => string = () => '',
  ) {
    const by = Date.now() + ms;

    while (!(await done())) {
      if (Date.now() > by) {
        throw new Error(
          `${what} did not come within ${ms} ms${so() ? ` (${so()})` : ''}:\n${screen()}`,
        );
      }

      await sleep(250);
    }
  }

  /** Every process as `ps` lists it: pid, parent and command. */
  function processes(): { pid: number; ppid: number; command: string }[] {
    return spawnSync('ps', ['-A', '-o', 'pid=,ppid=,command='], {
      encoding: 'utf8',
    })
      .stdout.split('\n')
      .flatMap((line) => {
        const match = /^\s*(\d+)\s+(\d+)\s+(.*)$/.exec(line);

        return match === null
          ? []
          : [
              {
                pid: Number(match[1]),
                ppid: Number(match[2]),
                command: match[3]!,
              },
            ];
      });
  }

  /**
   * Adds chord's descendants now to `team`: a fake agent whose chord has died
   * is reparented and no longer found under it, so cleaning up goes by what
   * was seen as well as what is there.
   */
  function seen(): void {
    if (pid === 0) {
      return;
    }

    const all = processes();
    const ours = new Set([pid]);

    for (let grew = true; grew;) {
      grew = false;

      for (const { pid: child, ppid, command } of all) {
        if (ours.has(ppid) && !ours.has(child)) {
          ours.add(child);
          team.set(child, command);

          grew = true;
        }
      }
    }
  }

  /** Those of `team` still running the command they were seen running. */
  function running(): number[] {
    const now = new Map(processes().map((it) => [it.pid, it.command]));

    return [...team].flatMap(([of, command]) =>
      now.get(of) === command ? [of] : [],
    );
  }

  /**
   * Ends the run's tmux session, which hangs chord up, and waits for chord and
   * every agent under it to exit; what has not in `EXIT_MS` is sent SIGTERM,
   * then SIGKILL. Once, however many times it is asked; says what is left.
   */
  function cleanUp(): Promise<string[]> {
    cleaned ??= (async () => {
      if (!started) {
        return [];
      }

      seen();
      spawnSync('tmux', ['kill-session', '-t', session]);

      const left = () => [
        ...(pid !== 0 && alive(pid) ? [pid] : []),
        ...running(),
      ];

      for (const signal of [undefined, 'SIGTERM', 'SIGKILL'] as const) {
        for (const of of signal === undefined ? [] : left()) {
          try {
            process.kill(of, signal);
          } catch {
            // Gone between the look and the signal.
          }
        }

        const by = Date.now() + EXIT_MS;

        while (left().length > 0 && Date.now() < by) {
          await sleep(100);
        }

        if (left().length === 0) {
          return [];
        }
      }

      return [`still running after cleaning up: ${left().join(', ')}`];
    })();

    return cleaned;
  }

  interface Turns {
    /** Prompts the agent has been sent: its turns, begun or done. */
    prompts: number;
    /** Streamed pieces of its replies. */
    chunks: number;
  }

  /**
   * Each soak agent's turns so far, from the records: main is the session
   * nobody started, the lead the one with a team, the members by their names.
   */
  async function workload(): Promise<Map<string, Turns>> {
    const by = new Map<string, Turns>();

    for (const file of await readdir(records).catch(() => [])) {
      if (!file.endsWith('.jsonl')) {
        continue;
      }

      const text = await readFile(join(records, file), 'utf8');
      const head = JSON.parse(text.slice(0, text.indexOf('\n'))) as {
        parent?: string;
        name?: string;
        team?: string;
      };
      const agent =
        head.team !== undefined
          ? 'lead'
          : head.parent === undefined
            ? 'main'
            : (head.name ?? 'agent');
      const was = by.get(agent) ?? { prompts: 0, chunks: 0 };

      by.set(agent, {
        prompts: was.prompts + count(text, '{"type":"prompt"'),
        chunks:
          was.chunks + count(text, '"sessionUpdate":"agent_message_chunk"'),
      });
    }

    return by;
  }

  function count(text: string, of: string): number {
    let n = 0;

    for (let at = text.indexOf(of); at !== -1; at = text.indexOf(of, at + 1)) {
      n++;
    }

    return n;
  }

  function total(of: Map<string, Turns>): number {
    return [...of.values()].reduce((sum, { prompts }) => sum + prompts, 0);
  }

  function said(of: Map<string, Turns>): string {
    return AGENTS.map(
      (agent) => `${agent} ${of.get(agent)?.prompts ?? 0}`,
    ).join(', ');
  }

  async function sample(turns: number): Promise<Sample> {
    const rss =
      Number(spawnSync('ps', ['-o', 'rss=', '-p', String(pid)]).stdout) * 1024;
    // macOS's own count, the one Activity Monitor shows: what is swapped out
    // counts, as resident size does not.
    const footprint = /Footprint: (\d+) B/.exec(
      spawnSync('footprint', ['-p', String(pid), '-f', 'bytes'], {
        encoding: 'utf8',
      }).stdout ?? '',
    )?.[1];
    let bytes = 0;

    for (const file of await readdir(records).catch(() => [])) {
      bytes += (await stat(join(records, file))).size;
    }

    return {
      seconds: seconds(),
      rss,
      footprint: footprint === undefined ? undefined : Number(footprint),
      records: bytes,
      turns,
    };
  }

  function row(of: Sample): string {
    return `${of.seconds}\t${mb(of.rss)}\t${
      of.footprint === undefined ? '-' : mb(of.footprint)
    }\t${mb(of.records)}\t${of.turns}`;
  }

  function mb(bytes: number): string {
    return (bytes / 1e6).toFixed(1);
  }

  /** Has chord write a snapshot, and waits for its stats, written last. */
  async function snapshot() {
    const before = new Set(await readdir(heaps).catch(() => []));

    process.kill(pid, 'SIGUSR2');

    let stats: string | undefined;

    await until(
      async () => {
        stats = (await readdir(heaps).catch(() => [])).find(
          (file) => file.endsWith('.json') && !before.has(file),
        );

        return stats !== undefined;
      },
      300_000,
      'the snapshot',
    );

    return {
      seconds: seconds(),
      snapshot: join(heaps, stats!.replace(/\.json$/, '.heapsnapshot')),
      stats: JSON.parse(
        await readFile(join(heaps, stats!), 'utf8'),
      ) as HeapStats,
    };
  }

  /** What grew from `first` to `last`, by type and name, and what holds it. */
  async function compare(first: string, last: string): Promise<string[]> {
    config.muteConsole = true;

    const before = byName(await getFullHeapFromFile(first));
    const heap = await getFullHeapFromFile(last);
    const after = byName(heap);
    const grown = [...after]
      .map(([name, now]) => {
        const was = before.get(name);

        return {
          name,
          count: now.count - (was?.count ?? 0),
          size: now.size - (was?.size ?? 0),
          example: now.largest,
        };
      })
      .filter(({ size }) => size > 0)
      .sort((a, b) => b.size - a.size)
      .slice(0, 20);

    return [
      'grown, first snapshot to last (count, self size, type and name)',
      ...grown.map(
        ({ name, count, size }) => `${count}\t${mb(size)} MB\t${name}`,
      ),
      '',
      'held by (the shortest path from a root to the largest of each)',
      ...grown
        .slice(0, 8)
        .flatMap(({ name, example }) => [
          `${name}:`,
          ...retainers(heap.getNodeById(example)).map((step) => `  ← ${step}`),
        ]),
    ];
  }

  function byName(heap: IHeapSnapshot) {
    const groups = new Map<
      string,
      { count: number; size: number; largest: number; largestSize: number }
    >();

    heap.nodes.forEach((node) => {
      const name = `${node.type} ${node.name}`.trim();
      const group = groups.get(name) ?? {
        count: 0,
        size: 0,
        largest: node.id,
        largestSize: -1,
      };

      group.count++;

      group.size += node.self_size;

      if (node.self_size > group.largestSize) {
        group.largest = node.id;
        group.largestSize = node.self_size;
      }

      groups.set(name, group);
    });

    return groups;
  }

  function retainers(node: IHeapNode | null): string[] {
    const path: string[] = [];

    for (let at = node; at?.pathEdge && path.length < 12;) {
      const edge = at.pathEdge;

      path.push(
        `${edge.fromNode.type} ${edge.fromNode.name} .${String(edge.name_or_index)}`,
      );

      at = edge.fromNode;
    }

    return path;
  }
}
