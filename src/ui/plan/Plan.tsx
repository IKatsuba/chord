import type { PlanEntry } from '@agentclientprotocol/sdk';
import { useGap } from '../transcript/gap.ts';
import { TextAttributes } from '@opentui/core';
import { useSelectable } from '../app/context.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { CUT, DIM, FILL, TEXT } from '../theme/text.ts';
import { Gutter } from '../transcript/tools/Tool.tsx';
import {
  entryKeys,
  PLAN_MARKS,
  type PlanRow,
  planRows,
  planSummary,
} from './plan.ts';

/**
 * The agent's plan above the prompt: `☒` done and struck through, `◐` under
 * way, `☐` still to do. While the turn runs it hangs off the spinner, as in
 * Claude Code; between turns it hangs from a line of its own, so it does not
 * read as part of the last reply. Each entry is one row, cut at the edge.
 */
export function Plan({
  plan,
  limit,
  running,
}: {
  plan: readonly PlanEntry[];
  limit: number;
  running: boolean;
}) {
  const rows = planRows(plan, limit);
  const keys = rowKeys(rows);

  return (
    <box paddingLeft={2} {...(running ? {} : { marginTop: 1 })} flexShrink={0}>
      {!running && (
        <text {...CUT} attributes={DIM}>
          {planSummary(plan)}
        </text>
      )}
      {rows.map((row, index) => (
        <box key={keys[index]!} flexDirection='row'>
          <Gutter width={3} dimColor>
            {index === 0 ? '⎿' : ' '}
          </Gutter>
          {row.kind === 'entry' ? (
            <PlanEntry entry={row.entry} running={running} />
          ) : (
            <text {...CUT} attributes={DIM}>
              {row.kind === 'done'
                ? `… ${row.count} done`
                : `… +${row.count} more`}
            </text>
          )}
        </box>
      ))}
    </box>
  );
}

/** Each row's key: an entry's by its words, a fold's by what it folds. */
function rowKeys(rows: readonly PlanRow[]): string[] {
  const keys = entryKeys(
    rows.map((row) => (row.kind === 'entry' ? row.entry.content : '')),
  );

  return rows.map((row, index) =>
    row.kind === 'entry' ? keys[index]! : row.kind,
  );
}

/** A finished plan in the transcript, whole and dim: a record, not news. */
export function PlanRecord({ entries }: { entries: readonly PlanEntry[] }) {
  const gap = useGap();

  const keys = entryKeys(entries.map(({ content }) => content));

  return (
    <>
      {gap.spacer}
      <box {...gap.props} flexShrink={0}>
        <box flexDirection='row'>
          <Gutter dimColor>⏺</Gutter>
          <text {...FILL} attributes={DIM}>
            Plan
          </text>
        </box>
        {entries.map((entry, index) => (
          <box key={keys[index]!} flexDirection='row' paddingLeft={2}>
            <Gutter width={3} dimColor>
              {index === 0 ? '⎿' : ' '}
            </Gutter>
            <PlanEntry entry={entry} running={false} dim />
          </box>
        ))}
      </box>
    </>
  );
}

/**
 * One step. Bold says the step is under way now, which is only true while a
 * turn runs; after an interrupt the `◐` alone says where it stopped.
 */
function PlanEntry({
  entry,
  running,
  dim = false,
}: {
  entry: PlanEntry;
  running: boolean;
  dim?: boolean;
}) {
  const mark = PLAN_MARKS[entry.status];
  const selectable = useSelectable();
  // The mark is chord's, so a copy takes the step's own words alone.
  const marked = (attributes: number) => (
    <text {...TEXT} attributes={attributes}>
      {`${mark} `}
    </text>
  );

  switch (entry.status) {
    case 'completed':
      return (
        <>
          {marked(DIM)}
          <text {...CUT} {...selectable} attributes={DIM}>
            <span attributes={TextAttributes.STRIKETHROUGH}>
              <Ansi text={entry.content} />
            </span>
          </text>
        </>
      );
    case 'in_progress': {
      const attributes = (running ? TextAttributes.BOLD : 0) | (dim ? DIM : 0);

      return (
        <>
          {marked(attributes)}
          <text {...CUT} {...selectable} attributes={attributes}>
            <Ansi text={entry.content} />
          </text>
        </>
      );
    }
    case 'pending':
      return (
        <>
          {marked(dim ? DIM : 0)}
          <text {...CUT} {...selectable} attributes={dim ? DIM : 0}>
            <Ansi text={entry.content} />
          </text>
        </>
      );
  }
}
