import cliTruncate from 'cli-truncate';
import { useRef, useState } from 'react';
import type { PlanAnswer, PlanWait } from '../../session/transcript/types.ts';
import { paint, useColours } from '../app/context.ts';
import { usePasted, usePress } from '../app/input.ts';
import { borderOf } from '../pickers/Pickers.tsx';
import { BOLD, CUT, DIM, fg, TEXT } from '../theme/text.ts';
import { Gutter } from '../transcript/tools/Tool.tsx';
import {
  OPEN_PLAN_BOX,
  planChoices,
  planHint,
  planKey,
  planPaste,
} from './plan.ts';
import { Typed } from './Questions.tsx';

/**
 * The box an agent's plan is put to the person in, above the prompt in the
 * permission box's place and look (docs/design/CHD-437.md): `Approve Plan`,
 * the agent's choices numbered, the question box's Note row sent with keep
 * planning, and the hint. The plan itself is in the transcript, under its
 * call. It takes the keys itself while `active`.
 */
export function PlanBox({
  wait,
  agent,
  width,
  active,
  hidden = false,
  onAnswer,
}: {
  wait: PlanWait;
  /** The agent as the agents list names it. */
  agent: string;
  /** The window's width; the box takes all of it. */
  width: number;
  active: boolean;
  /** Not drawn, its state kept, while the background view stands in its place. */
  hidden?: boolean;
  onAnswer: (answer: PlanAnswer) => void;
}) {
  const colours = useColours();
  const [state, setState] = useState(OPEN_PLAN_BOX);
  // Keys that land in one tick each see the one before.
  const latest = useRef(state);
  const choices = planChoices(wait.agent);
  const noteRow = choices.length;
  const set = (next: typeof state) => {
    latest.current = next;

    setState(next);
  };

  usePasted(
    (text) => {
      set(planPaste(wait.agent, latest.current, text));

      return true;
    },
    { isActive: active },
  );

  usePress(
    (input, key) => {
      const step = planKey(wait.agent, latest.current, input, key);

      set(step.state);

      if (step.answer !== undefined) {
        onAnswer(step.answer);
      }
    },
    { isActive: active },
  );

  const marker = (row: number) => (
    <Gutter {...paint(colours.permission)}>
      {row === state.row ? '❯' : ' '}
    </Gutter>
  );
  const onNote = state.row === noteRow;

  return (
    <box
      {...borderOf(colours.permission)}
      paddingX={1}
      flexShrink={0}
      visible={!hidden}
    >
      <text {...TEXT} {...fg(colours.permission)} attributes={BOLD}>
        Approve Plan
      </text>
      <text {...TEXT}> </text>
      <text {...TEXT}>{`${agent} has a plan. Do you want to proceed?`}</text>
      {choices.map((choice, index) => (
        <box key={index} flexDirection='row' flexShrink={0}>
          {marker(index)}
          <text
            {...CUT}
            {...(index === state.row ? fg(colours.permission) : {})}
          >
            {`${index + 1}. ${choice.label}`}
          </text>
        </box>
      ))}
      <text {...TEXT}> </text>
      <box flexDirection='row' flexShrink={0}>
        {marker(noteRow)}
        <text {...CUT}>
          <span
            {...(onNote ? fg(colours.permission) : {})}
            attributes={onNote ? BOLD : 0}
          >
            Note{'  '}
          </span>
          <Typed
            text={state.note}
            placeholder={cliTruncate(
              `Tell ${agent} what to change, sent with 2 (optional)`,
              // The `❯`, `Note  ` and the cursor's cell, inside the border.
              Math.max(width - 13, 1),
            )}
            focused={onNote && active}
          />
        </text>
      </box>
      <text {...TEXT}> </text>
      <text {...TEXT} attributes={DIM}>
        {planHint(wait.agent, state)}
      </text>
    </box>
  );
}
