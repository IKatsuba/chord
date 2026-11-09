import { afterEach, beforeEach, describe, expect, test } from 'bun:test';
import { spawnSync } from 'node:child_process';
import { mkdir, mkdtemp, realpath, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  buildOptions,
  fffProblem,
  withFffWorker,
} from '../../scripts/dev/compile.ts';
import { hostTarget } from '../../scripts/targets.ts';
import {
  type FffReply,
  type FffRequest,
  type FffWorker,
  type Finder,
  openFinder,
} from '../../src/platform/fff.ts';

const FIXTURE = fileURLToPath(
  new URL('../fixtures/fff/main.ts', import.meta.url),
);

const live = () => new AbortController().signal;

describe('the fff finder in its Worker', () => {
  let root: string;
  let finder: Finder;

  beforeEach(async () => {
    root = await realpath(await mkdtemp(join(tmpdir(), 'chord-fff-')));

    await mkdir(join(root, 'src', 'deep'), { recursive: true });
    await writeFile(join(root, 'src', 'a.ts'), 'before\nneedle one\nafter\n');
    await writeFile(join(root, 'src', 'deep', 'b.ts'), 'needle two\n');
    await writeFile(join(root, 'notes.md'), 'nothing here\n');

    finder = openFinder(root);
  });

  afterEach(async () => {
    await finder.destroy();
    await rm(root, { recursive: true, force: true });
  });

  test('greps with context lines', async () => {
    const result = await finder.grep(
      'needle',
      { beforeContext: 1, afterContext: 1 },
      live(),
    );
    const found = result.items
      .map((item) => `${item.relativePath}:${item.lineNumber}`)
      .toSorted();

    expect(found).toEqual(['src/a.ts:2', 'src/deep/b.ts:1']);

    const a = result.items.find((item) => item.relativePath === 'src/a.ts');

    expect(a?.contextBefore).toEqual(['before']);
    expect(a?.contextAfter).toEqual(['after']);
  });

  test('globs files and searches directories', async () => {
    const files = await finder.glob('*.ts', {}, live());

    expect(files.items.map((item) => item.relativePath).toSorted()).toEqual([
      'src/a.ts',
      'src/deep/b.ts',
    ]);

    const directories = await finder.directorySearch('', {}, live());

    expect(directories.items.map((item) => item.relativePath)).toContain(
      'src/deep/',
    );
  });

  test('an aborted call rejects with its reason, and the next call still answers', async () => {
    const controller = new AbortController();
    const reason = new Error('stopped');
    const aborted = finder.grep('needle', {}, controller.signal);

    controller.abort(reason);

    await expect(aborted).rejects.toBe(reason);

    // The Worker was ended; a new one scans again and answers.
    const result = await finder.glob('*.md', {}, live());

    expect(result.items.map((item) => item.relativePath)).toEqual(['notes.md']);
  });

  test('a call the abort did not concern is sent again and answers', async () => {
    const controller = new AbortController();
    const aborted = finder.grep('needle', {}, controller.signal);
    const other = finder.glob('*.md', {}, live());

    controller.abort();

    await expect(aborted).rejects.toBeDefined();
    expect((await other).items.map((item) => item.relativePath)).toEqual([
      'notes.md',
    ]);
  });

  test('a call on an aborted signal never starts', async () => {
    const controller = new AbortController();

    controller.abort(new Error('already'));

    await expect(finder.grep('needle', {}, controller.signal)).rejects.toThrow(
      'already',
    );
  });

  test('after destroy, calls fail and a second destroy is harmless', async () => {
    await finder.glob('*.ts', {}, live());
    await finder.destroy();

    await expect(finder.glob('*.ts', {}, live())).rejects.toThrow(
      'fff: the finder is destroyed',
    );

    await finder.destroy();
  });

  test('a directory fff cannot open fails the call with its reason', async () => {
    const missing = openFinder(join(root, 'missing'));

    try {
      await expect(missing.glob('*', {}, live())).rejects.toThrow(/^fff: /);
    } finally {
      await missing.destroy();
    }
  });
});

/** A Worker the test answers by hand, in the order it chooses. */
class HeldWorker implements FffWorker {
  onmessage: ((event: MessageEvent<FffReply>) => void) | null = null;
  onerror: ((event: ErrorEvent) => void) | null = null;
  readonly requests: FffRequest[] = [];
  terminated = false;
  // What the finder had set before it retired this Worker.
  private message: ((event: MessageEvent<FffReply>) => void) | null = null;
  private error: ((event: ErrorEvent) => void) | null = null;

  postMessage(request: FffRequest): void {
    this.message = this.onmessage;
    this.error = this.onerror;

    this.requests.push(request);
  }

  terminate(): void {
    this.terminated = true;
  }

  /** Delivers as a real Worker may after terminate: to what was set. */
  reply(reply: FffReply): void {
    (this.onmessage ?? this.message)?.(
      new MessageEvent('message', { data: reply }),
    );
  }

  fail(message: string): void {
    (this.onerror ?? this.error)?.(new ErrorEvent('error', { message }));
  }
}

describe('the finder against its Worker, in a forced order', () => {
  const held = () => {
    const workers: HeldWorker[] = [];
    const finder = openFinder('/project', () => {
      const made = new HeldWorker();

      workers.push(made);

      return made;
    });

    return { workers, finder };
  };

  test("a retired Worker's late answer does not settle the call sent again", async () => {
    const { workers, finder } = held();
    const controller = new AbortController();
    const aborted = finder.grep('a', {}, controller.signal);
    const other = finder.glob('*', {}, live());

    controller.abort();
    await expect(aborted).rejects.toBeDefined();

    const [old, current] = workers;
    const otherId = old!.requests[1]!.id;

    expect(old!.terminated).toBe(true);
    expect(current!.requests.map((request) => request.id)).toEqual([otherId]);

    old!.reply({ id: otherId, ok: true, value: 'stale' });
    current!.reply({ id: otherId, ok: true, value: 'fresh' });

    expect(await other).toBe('fresh' as never);
  });

  test("a retired Worker's error leaves the calls sent again alone", async () => {
    const { workers, finder } = held();
    const controller = new AbortController();
    const aborted = finder.grep('a', {}, controller.signal);
    const other = finder.glob('*', {}, live());

    controller.abort();
    await expect(aborted).rejects.toBeDefined();

    const [old, current] = workers;
    const otherId = current!.requests[0]!.id;

    old!.fail('late');
    current!.reply({ id: otherId, ok: true, value: 'fresh' });

    expect(await other).toBe('fresh' as never);
  });

  test('a failed Worker is ended with its calls, and the next call starts another', async () => {
    const { workers, finder } = held();
    const call = finder.grep('a', {}, live());

    workers[0]!.fail('boom');

    await expect(call).rejects.toThrow('fff: the search worker failed: boom');
    expect(workers[0]!.terminated).toBe(true);

    const next = finder.glob('*', {}, live());

    workers[1]!.reply({ id: workers[1]!.requests[0]!.id, ok: true, value: 1 });

    expect(await next).toBe(1 as never);
  });

  test("destroy waits for its own answer, not a call's queued before it", async () => {
    const { workers, finder } = held();
    const call = finder.grep('a', {}, live());
    const destroyed = finder.destroy();

    await expect(call).rejects.toThrow('fff: the finder is destroyed');

    const [worker] = workers;
    const order: string[] = [];

    void destroyed.then(() => order.push('destroyed'));
    worker!.reply({ id: worker!.requests[0]!.id, ok: true, value: null });
    await Promise.resolve();
    order.push('call answered');
    expect(worker!.terminated).toBe(false);
    expect(worker!.requests.at(-1)).toMatchObject({ op: 'destroy' });

    worker!.reply({ id: worker!.requests.at(-1)!.id, ok: true, value: null });
    await destroyed;

    expect(order).toEqual(['call answered', 'destroyed']);
    expect(worker!.terminated).toBe(true);
  });
});

test('compiled with its Worker as an entry point, as chord is, the finder answers with no node_modules', async () => {
  const directory = await realpath(
    await mkdtemp(join(tmpdir(), 'chord-fff-compiled-')),
  );
  const binary = join(directory, 'fff');
  const project = join(directory, 'project');

  try {
    await mkdir(project);
    await writeFile(join(project, 'a.txt'), 'needle\n');

    const built = await Bun.build({
      ...buildOptions(FIXTURE, { compiled: true }),
      ...withFffWorker(FIXTURE),
      compile: { outfile: binary },
      metafile: true,
    });

    expect(built.success).toBe(true);
    expect(
      fffProblem(Object.keys(built.metafile!.inputs), hostTarget()!),
    ).toBeUndefined();

    const run = spawnSync(binary, [project], {
      cwd: directory,
      encoding: 'utf8',
    });

    expect(run.stderr).toBe('');
    expect(JSON.parse(run.stdout)).toEqual(['a.txt']);
  } finally {
    await rm(directory, { recursive: true, force: true });
  }
}, 120_000);

describe('tester: a failed current fff Worker', () => {
  test('rejects pending work once, starts fresh and retires every Worker', async () => {
    const workers: HeldWorker[] = [];
    const finder = openFinder('/project', () => {
      const made = new HeldWorker();

      workers.push(made);

      return made;
    });

    const outcomes: string[] = [];
    const pending = finder.grep('needle', {}, live()).then(
      () => outcomes.push('resolved'),
      (error: unknown) => {
        outcomes.push(error instanceof Error ? error.message : String(error));
      },
    );
    const failed = workers[0]!;

    try {
      failed.fail('forced failure');
      await pending;

      const next = finder.glob('*', {}, live());
      const fresh = workers[1]!;
      const id = fresh.requests[0]!.id;

      failed.reply({ id, ok: true, value: 'stale' });
      failed.fail('late failure');
      fresh.reply({ id, ok: true, value: 'fresh' });

      expect(await next).toBe('fresh' as never);
      expect(workers).toHaveLength(2);
      expect(outcomes).toEqual([
        'fff: the search worker failed: forced failure',
      ]);
    } finally {
      const destroyed = finder.destroy();
      const current = workers.at(-1)!;

      current.reply({ id: -1, ok: true, value: null });
      await destroyed;
    }

    expect(workers.every((worker) => worker.terminated)).toBe(true);
  });
});
