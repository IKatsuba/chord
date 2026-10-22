/**
 * The suite's timings kept current (CHD-501, the owner's Q145-Q149):
 * `tests/timings.json` records how long each test file takes, which
 * `bun test --parallel` places its files by. A whole run measures them
 * again into a scratch file beside it, and a file past its budget, one that
 * moved far from its record, one run but unrecorded or one recorded but gone
 * fails the run, named. Nothing here rewrites the record: a person does,
 * with `bun dev test --update-timings`, and commits it.
 */

/** The record of each test file's time, which the repository keeps. */
export const RECORD = 'tests/timings.json';

/** Where a whole run measures them again, beside the record; not kept. */
export const MEASURED = 'tests/timings.measured.json';

/** The longest a test file may take (Q146). */
export const BUDGET_MS = 90_000;

/**
 * How far a file's time may move from its record before the record is
 * stale (Q149): by this share of it and by this many ms, both.
 */
export const MOVED = { share: 0.35, ms: 10_000 } as const;

/** Each test file's time, in ms, by its path from the repository's root. */
export type Timings = Readonly<Record<string, number>>;

/** A file whose time moved from its record past `MOVED`. */
export interface Moved {
  readonly file: string;
  readonly recorded: number;
  readonly measured: number;
}

/** What a run's times say against the record, each list in path order. */
export interface TimingReport {
  /** Files that took longer than `BUDGET_MS`, with their time. */
  readonly over: readonly { readonly file: string; readonly ms: number }[];
  readonly moved: readonly Moved[];
  /** Test files on disk the record does not name. */
  readonly unrecorded: readonly string[];
  /** Files the record names that are no longer on disk. */
  readonly gone: readonly string[];
}

/**
 * The times in timings file `path`, whose text is `text`: a file that is
 * not there, is not JSON or holds no times is an error that says so, never
 * no times, as a run measured against nothing would pass.
 */
export function readTimings(path: string, text: string | undefined): Timings {
  if (text === undefined) {
    throw new Error(`timings: ${path} is not there`);
  }

  let parsed: unknown;

  try {
    parsed = JSON.parse(text);
  } catch {
    throw new Error(`timings: ${path} is not JSON`);
  }

  const files =
    typeof parsed === 'object' && parsed !== null && 'files' in parsed
      ? parsed.files
      : undefined;

  if (
    typeof files !== 'object' ||
    files === null ||
    Object.values(files).some((ms) => typeof ms !== 'number')
  ) {
    throw new Error(`timings: ${path} holds no file's time`);
  }

  return files as Timings;
}

/** Whether `path` is a file Bun's test runner runs, by its name. */
export function isTestFile(path: string): boolean {
  return /[._](test|spec)\.[cm]?[jt]sx?$/.test(path);
}

/**
 * `measured` against `recorded`, for test files `onDisk`. A run that
 * rewrites the record (`refreshing`) is held only to the budget.
 */
export function compare(
  recorded: Timings,
  measured: Timings,
  onDisk: readonly string[],
  { refreshing = false }: { readonly refreshing?: boolean } = {},
): TimingReport {
  const byPath = (a: string, b: string) => (a < b ? -1 : a > b ? 1 : 0);
  const over = Object.entries(measured)
    .filter(([file, ms]) => ms > BUDGET_MS && onDisk.includes(file))
    .map(([file, ms]) => ({ file, ms }))
    .sort((a, b) => byPath(a.file, b.file));

  if (refreshing) {
    return { over, moved: [], unrecorded: [], gone: [] };
  }

  const moved = Object.entries(measured)
    .flatMap(([file, ms]): Moved[] => {
      const was = recorded[file];

      if (was === undefined) {
        return [];
      }

      const by = Math.abs(ms - was);

      return by >= MOVED.ms && by >= MOVED.share * was
        ? [{ file, recorded: was, measured: ms }]
        : [];
    })
    .sort((a, b) => byPath(a.file, b.file));

  return {
    over,
    moved,
    unrecorded: onDisk.filter((file) => !(file in recorded)).sort(byPath),
    gone: Object.keys(recorded)
      .filter((file) => !onDisk.includes(file))
      .sort(byPath),
  };
}

/** Whether `report` fails the run. */
export function fails(report: TimingReport): boolean {
  return (
    report.over.length +
      report.moved.length +
      report.unrecorded.length +
      report.gone.length >
    0
  );
}

const seconds = (ms: number) => `${(ms / 1000).toFixed(1)} s`;

/** What a failing `report` says, a line each; nothing when it passes. */
export function reportLines(report: TimingReport): string[] {
  if (!fails(report)) {
    return [];
  }

  return [
    ...(report.over.length === 0
      ? []
      : [
          `timings: over the ${seconds(BUDGET_MS)} a test file may take; split it:`,
          ...report.over.map(({ file, ms }) => `  ${file}  ${seconds(ms)}`),
        ]),
    ...(report.moved.length === 0
      ? []
      : [
          `timings: moved from ${RECORD} by ${MOVED.share * 100}% and ${seconds(MOVED.ms)} or more:`,
          ...report.moved.map(
            ({ file, recorded, measured }) =>
              `  ${file}  ${seconds(recorded)} recorded, ${seconds(measured)} now`,
          ),
        ]),
    ...(report.unrecorded.length === 0
      ? []
      : [
          `timings: run but not in ${RECORD}:`,
          ...report.unrecorded.map((file) => `  ${file}`),
        ]),
    ...(report.gone.length === 0
      ? []
      : [
          `timings: in ${RECORD} but no longer a test file:`,
          ...report.gone.map((file) => `  ${file}`),
        ]),
    ...(report.moved.length + report.unrecorded.length + report.gone.length ===
    0
      ? []
      : [
          `timings: if the change is right, refresh the record with \`bun dev test --update-timings\` and commit ${RECORD}.`,
        ]),
  ];
}
