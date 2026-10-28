/** One read of the providers' limits, a line per window or per provider not read. */
import { Budgets, type ResourceWindow } from '../../../session/budgets.ts';

function utc(value: string, read: string, seconds = false): string {
  const date = new Date(value);
  const time = date.toISOString().slice(11, seconds ? 19 : 16);

  return `${value.slice(0, 10) === read.slice(0, 10) ? '' : `${date.toISOString().slice(0, 10)} `}${time} UTC`;
}

function duration(seconds: number): string {
  for (const [unit, size] of [
    ['d', 86400],
    ['h', 3600],
    ['m', 60],
  ] as const) {
    if (seconds % size === 0) {
      return `${seconds / size}${unit}`;
    }
  }

  return `${seconds}s`;
}

function windowLine(
  agent: string,
  window: ResourceWindow,
  read: string,
): string {
  const label =
    window.windowSeconds === null
      ? window.name
      : duration(window.windowSeconds);

  return `${agent} · ${label}: ${window.usedPercent === null ? 'usage unknown' : `${window.usedPercent}% used`} · reset ${window.resetsAt === null ? 'unknown' : utc(window.resetsAt, read)} · ${window.models === null ? 'models unknown' : `models ${window.models.join(', ') || 'none'}`}`;
}

export function resourceLines(value: unknown): string[] {
  const parsed = Budgets.safeParse(value);

  if (!parsed.success) {
    return ['Recorded in an older format; not shown.'];
  }

  const { readAt, providers } = parsed.data;

  return [
    `Read: ${utc(readAt, readAt, true)} · advisory snapshot`,
    ...(providers.length === 0 ? ['No providers read.'] : []),
    ...providers.flatMap((provider) =>
      'unavailable' in provider
        ? [`${provider.agent}: unavailable · ${provider.unavailable}`]
        : provider.windows.length === 0
          ? [`${provider.agent}: no windows reported`]
          : provider.windows.map((window) =>
              windowLine(provider.agent, window, readAt),
            ),
    ),
  ];
}
