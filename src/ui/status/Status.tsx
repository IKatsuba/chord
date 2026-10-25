import { type ReactNode, useEffect, useState } from 'react';
import { modelName } from '../../session/models.ts';
import { runningSubagents } from '../../session/subagents.ts';
import type { TurnState } from '../../session/transcript/types.ts';
import { blockCopyNote, copyNote } from '../app/selection.ts';
import type { AppState } from '../app/state.ts';
import { SPINNER_STEPS, spinnerMarks, workingLine } from './status.ts';
import { useColours, useHintKey } from '../app/context.ts';
import { type Binding, hintKey, type Sequence } from '../shortcuts/bindings.ts';
import { CUT, DIM, fg, TEXT } from '../theme/text.ts';
import type { Palette } from '../theme/theme.ts';
import { stillRunning } from '../transcript/agents/subagents.ts';
import {
  LEADER_GAP,
  leaderLine,
  STATUS_SEPARATOR,
  statusLine,
  type StatusPart,
  type StatusTone,
  type WaitsNotice,
} from './status.ts';

/** The working line's spinner, on a timer of its own (`spinnerMarks`). */
function Spinner() {
  const [step, setStep] = useState(0);
  const { mark } = useColours();

  useEffect(() => {
    const timer = setInterval(
      () => setStep((at) => (at + 1) % SPINNER_STEPS),
      140,
    );

    return () => clearInterval(timer);
  }, []);

  return (
    <text {...TEXT}>
      {spinnerMarks(step, mark).map(({ colour, dim }, index) => (
        <span key={index} {...fg(colour)} attributes={dim ? DIM : 0}>
          ›
        </span>
      ))}
    </text>
  );
}

export function Working({
  turn,
  asking,
  compacting,
}: {
  turn: TurnState;
  /** The form, link or plan open below, if any, and when it asked. */
  asking:
    { readonly at?: number | undefined; readonly plan?: true } | undefined;
  compacting: boolean;
}) {
  const [now, setNow] = useState(Date.now);
  const busy = turn.status !== 'idle' || asking !== undefined;

  useEffect(() => {
    if (!busy) {
      return;
    }

    setNow(Date.now());

    const timer = setInterval(() => setNow(Date.now()), 250);

    return () => clearInterval(timer);
  }, [busy]);

  const line = workingLine(
    turn,
    now,
    asking ?? false,
    useHintKey('chat:cancel'),
    compacting,
  );
  const { accent } = useColours();

  if (!line) {
    return null;
  }

  return (
    <box flexDirection='row' paddingX={1} marginTop={1} gap={1} flexShrink={0}>
      <Spinner />
      <text {...TEXT} {...fg(accent)}>
        {line.label}
      </text>
      <text {...TEXT} attributes={DIM}>
        ({line.detail})
      </text>
    </box>
  );
}

/**
 * What Tab says on an agent that takes no steering, and the way out by the
 * key bound to send, if any (CHD-378); 72 cells with Enter, whole at 80
 * columns.
 */
export function unsteeredNote(submit: string | undefined): string {
  const note = 'This agent does not take messages into a running turn';

  return submit === undefined ? note : `${note} · ${submit} queues it`;
}

/**
 * What a code block put into the prompt says where a draft is in the box,
 * which it never replaces (docs/design/CHD-394.md §4).
 */
export const DRAFT_HELD = 'The prompt holds a draft · ctrl+c clears it';

/** What `ctrl+x b` says with no code block in the transcript (CHD-394 §3). */
export const NO_CODE_BLOCK = 'No code block to pick';

/** Claude Code's mode colours, in the theme's tones; the rest is dim. */
function statusColour(tone: StatusTone, colours: Palette): string | undefined {
  switch (tone) {
    case 'plain':
      return undefined;
    case 'plan':
    case 'edits':
    case 'auto':
    case 'bash':
      return colours[tone];
    case 'bypass':
      return colours.error;
    case 'low':
    case 'failed':
    case 'waits':
      return colours.warning;
    case 'ended':
    case 'error':
      return colours.error;
  }
}

export function StatusLine({
  state,
  agent,
  effort,
  waits,
  armed,
  draft,
  width,
  hint,
}: {
  state: AppState;
  agent: string;
  /** The effort the shown session is on; none for a runtime with none. */
  effort: string | undefined;
  waits: WaitsNotice | undefined;
  /** What an armed close or quit waits on the second press for. */
  armed: string | undefined;
  draft: string;
  /** Cells inside the line's padding. */
  width: number;
  /** What the keys do while a list under the line has them. */
  hint?: string | undefined;
}) {
  const { transcript, connection } = state;
  const colours = useColours();
  const failure = state.editorFailed ?? state.pasteFailed ?? state.keysFailed;
  const helpKey = hintKey(state.keys, 'help:toggle');
  const cycleKey = hintKey(state.keys, 'chat:cycleMode');
  const copied =
    state.copied &&
    (state.copied.block
      ? blockCopyNote(state.copied.result)
      : copyNote(state.copied.result));
  const held = state.draftHeld === undefined ? undefined : DRAFT_HELD;
  const noBlock = state.noCodeBlock === undefined ? undefined : NO_CODE_BLOCK;
  const unsteered =
    state.steerRefused === undefined
      ? undefined
      : unsteeredNote(hintKey(state.keys, 'chat:submit'));
  // A picked code block's line of keys comes before every note but an
  // armed quit's: they are what the keys do now (CHD-394 §3).
  const notice =
    armed ??
    (connection.status === 'closing'
      ? `Stopping ${agent}…`
      : state.codePick !== undefined
        ? undefined
        : (failure ??
          unsteered ??
          held ??
          noBlock ??
          copied ??
          state.sessionsNote ??
          (connection.status === 'starting'
            ? `Starting ${agent}…`
            : undefined)));
  // A question waiting on a second press stands alone, so the sessions it
  // names are never cut for the model beside them; so does a copy's note,
  // which nothing may cut at 80 columns.
  // So does a picked code block's line of keys, as the design draws it
  // (CHD-394 §3).
  const alone =
    armed !== undefined ||
    (copied !== undefined && notice === copied) ||
    (state.codePick !== undefined && notice === undefined);
  // A picked block's line of keys stands alone, before bash mode, a mode,
  // vim's mark and the waits, as the design draws it (CHD-394 §3).
  const picking = state.codePick !== undefined && notice === undefined;
  const { left, right } = statusLine(
    {
      model: alone ? undefined : modelName(state.models),
      effort: alone ? undefined : effort,
      failed:
        notice !== undefined &&
        (notice === failure || notice === unsteered || notice === held),
      error:
        copied !== undefined &&
        notice === copied &&
        state.copied?.result.kind === 'failed',
      mode: picking ? undefined : transcript.mode,
      modeName: picking
        ? undefined
        : state.modes.find((mode) => mode.id === transcript.mode)?.name,
      usage: alone ? undefined : transcript.usage,
      notice,
      bash: picking ? false : state.bash,
      // Subagents a finished turn left at work may be out of sight, so the
      // line says so, in place of Claude Code's pointer to its panel.
      hint:
        hint ??
        // A selection shown, copied or not, keeps the copy key in the
        // shortcuts' place until something clears it.
        (state.selection?.kind === 'shown' ? 'ctrl + c to copy' : undefined) ??
        (transcript.turn.status === 'idle'
          ? stillRunning(runningSubagents(transcript))
          : undefined) ??
        (draft === '' && helpKey !== undefined
          ? `${helpKey} for shortcuts`
          : undefined),
      cycleKey: cycleKey ?? null,
      vim: picking ? undefined : state.vim?.mode,
      waits: picking ? undefined : waits,
    },
    width,
  );

  return (
    <box
      flexDirection='row'
      justifyContent='space-between'
      width={width}
      flexShrink={1}
    >
      <text {...CUT}>
        {left.map((part, index) => (
          <span key={index}>
            {index > 0 && ' '}
            {statusText(part, colours)}
          </span>
        ))}
      </text>
      {right.length > 0 && (
        <box
          flexDirection='row'
          flexShrink={0}
          marginLeft={left.length === 0 ? 0 : 2}
        >
          <text {...CUT}>
            {right.map((part, index) => (
              <span key={index}>
                {index > 0 && <span attributes={DIM}>{STATUS_SEPARATOR}</span>}
                {statusText(part, colours)}
              </span>
            ))}
          </text>
        </box>
      )}
    </box>
  );
}

/**
 * The status line after a chord's first keys: the keys held, then each key
 * that can follow, with what it does dim.
 */
export function LeaderLine({
  held,
  bindings,
  width,
}: {
  held: Sequence;
  bindings: readonly Binding[];
  width: number;
}) {
  const view = leaderLine(held, bindings, width);

  return (
    <text {...CUT}>
      {view.held}
      {LEADER_GAP}
      {view.items.map(({ keys, words }, index) => (
        <span key={keys}>
          {index > 0 && <span attributes={DIM}>{STATUS_SEPARATOR}</span>}
          {keys}
          {words !== '' && <span attributes={DIM}>{` ${words}`}</span>}
        </span>
      ))}
    </text>
  );
}

/**
 * One part of the status line in its tone's colour; a function rather than
 * a component, so the line's `<text>` holds every run and cuts them as one.
 */
function statusText(part: StatusPart, colours: Palette): ReactNode {
  const colour = statusColour(part.tone, colours);

  return colour === undefined ? (
    <span attributes={DIM}>{part.text}</span>
  ) : (
    <span {...fg(colour)}>{part.text}</span>
  );
}
