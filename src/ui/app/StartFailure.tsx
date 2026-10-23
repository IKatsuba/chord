import {
  cutLine,
  pinLine,
  STDERR_HEADING,
  type StartFailure,
  wayOnFor,
} from '../../session/start_failure.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { DIM, FILL } from '../theme/text.ts';
import { Under } from '../transcript/tools/Tool.tsx';

/** A row of the block: chord's words, or a line of the agent's stderr. */
interface Row {
  readonly text: string;
  /** A line of the tail, two in under the block's text. */
  readonly tail?: true;
  readonly dim?: true;
}

/**
 * Under a start failure, what chord knows of why: the registry's pin it ran,
 * the end of the agent's stderr with what was cut before it, and the way on
 * chord knows for `agent`, each only when it has something to say
 * (docs/design/CHD-454.md).
 */
export function StartFailureBlock({
  agent,
  failure,
}: {
  agent: string;
  failure: StartFailure;
}) {
  const way = wayOnFor(agent, failure);
  const { pinned, stderr } = failure;
  const rows: Row[] = [
    ...(pinned === undefined ? [] : [{ text: pinLine(pinned) }]),
    ...(stderr === undefined
      ? []
      : [
          { text: STDERR_HEADING },
          ...(stderr.cut === 0
            ? []
            : [{ text: cutLine(stderr.cut), tail: true, dim: true } as const]),
          ...stderr.lines.map((line) => ({ text: line, tail: true }) as const),
        ]),
    ...(way === undefined ? [] : [{ text: way }]),
  ];

  return rows.map((row, index) => (
    <Under key={index} first={index === 0}>
      {/* A tail's line wraps under its column, not its own indent. */}
      <box paddingLeft={row.tail ? 2 : 0} flexGrow={1} flexShrink={1}>
        <text {...FILL} {...(row.dim ? { attributes: DIM } : {})}>
          <Ansi text={row.text} />
        </text>
      </box>
    </Under>
  ));
}
