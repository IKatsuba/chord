/**
 * Who a box that asks the person names as asking, as pieces each drawn in
 * its role, so the question, form, link and permission boxes all say it the
 * same way (CHD-389, after CHD-158's asker row).
 */
import { subagentPath } from '../../session/subagents.ts';
import type { Entry, Subagent } from '../../session/transcript/types.ts';
import { askerRow } from '../transcript/agents/subagents.ts';

/** How a piece is drawn: as the subagent row is, an agent's name, or plain. */
export type AskerTone = 'accent' | 'agent' | 'plain' | 'dim';

export interface AskerPart {
  readonly text: string;
  readonly tone: AskerTone;
  readonly bold?: true;
  /** The agent's colour, for an `agent` piece; none for one with no colour. */
  readonly colour?: string | undefined;
}

/** The long-lived child or member on screen, which the session's agent is. */
export interface PickedAsker {
  readonly name: string;
  readonly colour?: string | undefined;
  /** A member's team, by its run's name. */
  readonly team?: string | undefined;
}

export interface Asking {
  readonly entries: readonly Entry[];
  /** The subagent or task that asks, by its id; none when the agent does. */
  readonly subagentId?: string | undefined;
  /** The way down to it, where the caller has it already. */
  readonly path?: readonly Subagent[] | undefined;
  /** Asked with no turn running. */
  readonly between?: boolean;
  /** The child or member on screen, when one is. */
  readonly picked?: PickedAsker | undefined;
  /**
   * The runtime, which names main's request in a turn (the owner's Q33); none
   * where main's request names nobody, as its permission box does.
   */
  readonly runtime?: string | undefined;
}

/**
 * Who asks: a subagent or task by its way down from the session, as its
 * call is headed, in the accent colour, or `a subagent of <who>` when chord
 * drew none of it between turns; a child by its name, bold in its colour, a
 * member's team after it, dim (the owner's Q34–Q36); main by `main` between
 * turns, as CHD-158 names it, and in a turn by its runtime. None when nothing
 * names it: main's permission in a turn.
 */
export function askerParts({
  entries,
  subagentId,
  path: given,
  between = false,
  picked,
  runtime,
}: Asking): AskerPart[] {
  const owner = picked?.name ?? 'main';

  if (subagentId !== undefined || (given?.length ?? 0) > 0) {
    const path =
      given !== undefined && given.length > 0
        ? given
        : subagentId === undefined
          ? []
          : subagentPath(entries, subagentId);

    if (path.length > 0) {
      return askerRow(path)
        .slice(0, -1)
        .map((piece) => ({
          text: piece.text,
          tone: 'accent',
          ...(piece.bold && { bold: true as const }),
        }));
    }

    if (between) {
      return [{ text: `a subagent of ${owner}`, tone: 'accent' }];
    }
  }

  if (picked !== undefined) {
    return [
      { text: picked.name, tone: 'agent', bold: true, colour: picked.colour },
      ...(picked.team === undefined
        ? []
        : [{ text: ` · ${picked.team}`, tone: 'dim' as const }]),
    ];
  }

  if (between) {
    return [{ text: 'main', tone: 'plain', bold: true }];
  }

  return runtime === undefined ? [] : [{ text: runtime, tone: 'plain' }];
}
