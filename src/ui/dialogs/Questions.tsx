import { TextAttributes } from '@opentui/core';
import cliTruncate from 'cli-truncate';
import { type ReactNode, useEffect, useRef, useState } from 'react';
import stringWidth from 'string-width';
import wrapAnsi from 'wrap-ansi';
import type { ElicitationReply } from '../../session/elicitations.ts';
import type { Question, Questions } from '../../session/questions.ts';
import type { ElicitationWait } from '../../session/transcript/types.ts';
import { paint, useColours } from '../app/context.ts';
import { usePasted, usePress } from '../app/input.ts';
import { borderOf } from '../pickers/Pickers.tsx';
import { BLOCK } from '../prompt/Prompt.tsx';
import { Ansi } from '../theme/Ansi.tsx';
import { BOLD, CUT, DIM, fg, TEXT } from '../theme/text.ts';
import { Gutter } from '../transcript/tools/Tool.tsx';
import { formRowLimit } from './Form.tsx';
import { AttendHint } from './Permission.tsx';
import type { AskerPart } from './asker.ts';
import { AskerHeading } from './Asker.tsx';
import {
  answered,
  answerText,
  answerTo,
  asksYou,
  askHint,
  askKey,
  askPaste,
  type AskState,
  blockers,
  capLines,
  clock,
  expiresIn,
  headerOf,
  openAsk,
  ownIsOption,
  rowsOf,
  windowOf,
} from './questions.ts';

/**
 * The box's rows besides a step's: the border, the heading, the steps, the
 * hint and the blank rows between them.
 */
const BOX_CHROME = 8;

/** Under this much of the agent's wait, the countdown turns `warning`. */
const WARN_MS = 30_000;

/**
 * An agent's questions in the prompt box's place, one step at a time, then
 * Submit, as Claude Code's AskUserQuestion draws them. What each key does is
 * `askKey`'s; this only draws.
 */
export function QuestionBox({
  wait,
  questions,
  filled,
  agent,
  asker,
  windowRows,
  width,
  active,
  held = false,
  between = false,
  now = Date.now,
  onFill,
  onAnswer,
}: {
  wait: Extract<ElicitationWait, { mode: 'form' }>;
  /** Asked between turns, the keys not taken into it yet (CHD-158). */
  held?: boolean;
  /**
   * Asked with no turn running: its heading names `agent` as who asks and
   * says so, dim, wrapping rather than cut (CHD-158).
   */
  between?: boolean;
  questions: Questions;
  /** The box as it was left, when it was on screen before. */
  filled?: AskState | undefined;
  agent: string;
  /**
   * Who asks, as the heading names it; `agent` alone, plain, when not given
   * (CHD-389).
   */
  asker?: readonly AskerPart[];
  windowRows: number;
  width: number;
  active: boolean;
  now?: () => number;
  onFill?: (state: AskState) => void;
  onAnswer: (response: ElicitationReply) => void;
}) {
  const [state, setState] = useState(() => filled ?? openAsk(questions));
  // Keys that land in one tick each see the one before.
  const latest = useRef(state);
  const colours = useColours();
  const inner = Math.max(width - 4, 10);
  const [time, setTime] = useState(now);
  // A request drawn with no time of its own counts from when it was first
  // drawn.
  const [shownAt] = useState(now);

  useEffect(() => {
    if (questions.expiresInMs === undefined) {
      return;
    }

    const timer = setInterval(() => setTime(now()), 1000);

    return () => clearInterval(timer);
  }, [questions.expiresInMs, now]);

  usePasted(
    (text) => {
      const next = askPaste(questions, latest.current, text);

      latest.current = next;

      setState(next);
      onFill?.(next);

      return true;
    },
    { isActive: active },
  );

  usePress(
    (input, key) => {
      const step = askKey(questions, wait.schema, latest.current, input, key);

      latest.current = step.state;

      setState(step.state);
      onFill?.(step.state);

      if (step.response) {
        onAnswer(step.response);
      }
    },
    { isActive: active },
  );

  const left = expiresIn(questions, wait.at ?? shownAt, time);
  const problems = blockers(questions, wait.schema, state);
  // Held, no row reads as where the keys are, as they are not here.
  const shown = held ? { ...state, row: -1 } : state;
  const countdown =
    left === undefined ? undefined : `answers itself in ${clock(left)}`;
  const body =
    state.step < questions.questions.length ? (
      <QuestionStep
        question={questions.questions[state.step]!}
        state={shown}
        width={inner}
        limit={formRowLimit(windowRows) - BOX_CHROME}
      />
    ) : (
      <SubmitStep
        questions={questions}
        state={shown}
        problems={problems}
        agent={agent}
      />
    );

  return (
    <box
      {...borderOf(colours.permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
      <box flexDirection='row'>
        <AskerHeading
          asker={asker ?? [{ text: agent, tone: 'plain' }]}
          says={asksYou(questions)}
          between={between}
          grow
        />
        {countdown !== undefined && (
          <text
            {...TEXT}
            flexShrink={0}
            {...(left !== undefined && left < WARN_MS
              ? fg(colours.warning)
              : { attributes: DIM })}
          >
            {countdown}
          </text>
        )}
      </box>
      <box marginTop={1}>
        <Steps questions={questions} state={state} problems={problems} />
      </box>
      <box marginTop={1}>{body}</box>
      {held ? (
        <AttendHint />
      ) : (
        <box marginTop={1}>
          <text {...CUT} attributes={DIM}>
            {askHint(questions, state, inner)}
          </text>
        </box>
      )}
    </box>
  );
}

/**
 * `← ◉ Language   ○ Verbosity   ○ Submit →`: a question answered as the
 * agent takes it `✔`, one it would refuse still `○`.
 */
function Steps({
  questions,
  state,
  problems,
}: {
  questions: Questions;
  state: AskState;
  problems: ReadonlyMap<string, string>;
}) {
  const colours = useColours();
  const chips: ReactNode[] = questions.questions.map((question, index) => {
    const current = index === state.step;
    const done = answered(question, state) && !problems.has(question.id);

    return (
      <span key={question.id}>
        {question.required && <span {...fg(colours.warning)}>* </span>}
        {current ? (
          <span {...fg(colours.permission)}>◉</span>
        ) : done ? (
          <span {...fg(colours.success)}>✔</span>
        ) : (
          '○'
        )}
        <span attributes={current ? BOLD : 0}>
          {` ${headerOf(questions, index)}`}
        </span>
        {'   '}
      </span>
    );
  });

  const onSubmit = state.step === questions.questions.length;

  return (
    <text {...CUT}>
      {'← '}
      {chips}
      {onSubmit ? <span {...fg(colours.permission)}>◉</span> : '○'}
      <span attributes={onSubmit ? BOLD : 0}> Submit</span>
      {' →'}
    </text>
  );
}

/** A text row's value: the cursor at its end while the `❯` is on it. */
function Typed({
  text,
  placeholder,
  focused,
  secret,
}: {
  text: string;
  placeholder?: string | undefined;
  focused: boolean;
  secret?: boolean | undefined;
}) {
  const shown = secret === true ? '•'.repeat([...text].length) : text;

  return (
    <>
      {shown !== '' && <Ansi text={shown} />}
      {focused && <span attributes={TextAttributes.INVERSE}>{BLOCK}</span>}
      {shown === '' && placeholder !== undefined && (
        <span attributes={DIM}>{`${focused ? ' ' : ''}${placeholder}`}</span>
      )}
    </>
  );
}

/** One question: its text, its options, its own answer. */
function QuestionStep({
  question,
  state,
  width,
  limit,
}: {
  question: Question;
  state: AskState;
  width: number;
  limit: number;
}) {
  const colours = useColours();
  const answer = answerTo(state, question);
  const rows = rowsOf(question);
  const lines: { node: ReactNode; row?: number }[] = [];
  const marker = (index: number) => (
    <Gutter {...paint(colours.permission)}>
      {index === state.row ? '❯' : ' '}
    </Gutter>
  );
  const number = (index: number) => `${index + 1}. `;
  const box = (ticked: boolean) =>
    question.multiSelect ? `[${ticked ? '✔' : ' '}] ` : '';
  const indent = question.multiSelect ? 9 : 5;

  for (const line of wrapAnsi(
    `${question.text}${question.multiSelect ? ' (pick any)' : ''}`,
    width,
    { hard: true, trim: false },
  ).split('\n')) {
    lines.push({
      node: (
        <text {...TEXT} attributes={BOLD}>
          <Ansi text={line} />
        </text>
      ),
    });
  }

  lines.push({ node: <text {...TEXT}> </text> });

  rows.forEach((row, index) => {
    const focused = index === state.row;
    const tone = focused ? fg(colours.permission) : {};

    if (row.kind === 'option') {
      const option = question.options[row.index]!;
      const picked = answer.picks.includes(option.value);

      lines.push({
        row: index,
        node: (
          <box flexDirection='row'>
            {marker(index)}
            <text {...CUT} {...tone}>
              {box(picked)}
              {number(row.index)}
              <Ansi text={option.title} />
              {!question.multiSelect && picked ? ' ✔' : ''}
            </text>
          </box>
        ),
      });

      // An option's title and the two rows that count what is cut off
      // always fit beside its description.
      for (const part of option.description === undefined
        ? []
        : capLines(
            wrapAnsi(option.description, Math.max(width - indent, 10), {
              hard: true,
              trim: false,
            }).split('\n'),
            Math.max(limit, 6) - 3,
          )) {
        lines.push({
          row: index,
          node: (
            <box paddingLeft={indent}>
              <text {...CUT} attributes={DIM}>
                <Ansi text={part} />
              </text>
            </box>
          ),
        });
      }

      return;
    }

    if (row.kind === 'text') {
      lines.push({
        row: index,
        node: (
          <box flexDirection='row'>
            {marker(index)}
            <text {...CUT}>
              <Typed
                text={answer.text}
                focused={focused}
                secret={question.secret}
              />
            </text>
          </box>
        ),
      });

      return;
    }

    const own = question.own!;

    if (ownIsOption(question)) {
      const label = own.mode === 'instead' ? 'Your own answer' : 'Other answer';

      lines.push({
        row: index,
        node: (
          <box flexDirection='row'>
            {marker(index)}
            <text {...CUT} {...tone}>
              {box(answer.ownChosen)}
              {`${question.options.length + 1}. ${label}: `}
              <Typed
                text={answer.own}
                focused={focused}
                secret={question.secret}
              />
            </text>
          </box>
        ),
      });

      return;
    }

    lines.push({ node: <text {...TEXT}> </text> });
    lines.push({
      row: index,
      node: (
        <box flexDirection='row'>
          {marker(index)}
          <text {...CUT}>
            <span {...tone} attributes={focused ? BOLD : 0}>
              Note{'  '}
            </span>
            <Typed
              text={answer.own}
              placeholder={cliTruncate(
                own.placeholder ?? 'your own answer (optional)',
                // The `❯`, `Note  ` and the cursor's cell.
                Math.max(width - 9, 1),
              )}
              focused={focused}
              secret={question.secret}
            />
          </text>
        </box>
      ),
    });
  });

  // Keyed by the line's place in its own question, not on screen: OpenTUI
  // leaves a prop the new line lacks, such as an indent, on a box it reuses.
  const shown = windowed(
    lines.map((line, index) => ({ ...line, key: `${question.id}:${index}` })),
    state.row,
    Math.max(limit, 6),
  );

  return (
    <box>
      {shown.map((line) => (
        <box key={line.key} flexShrink={0}>
          {line.node}
        </box>
      ))}
    </box>
  );
}

/** The lines that fit `limit` (`windowOf`), with a line for what is cut off. */
function windowed<T extends { node: ReactNode; row?: number; key: string }>(
  lines: readonly T[],
  focus: number,
  limit: number,
): { node: ReactNode; key: string }[] {
  const { top, end, above, below } = windowOf(
    lines.map((line) => line.row),
    focus,
    limit,
  );
  const more = (count: number, arrow: string) => ({
    key: `more ${arrow}`,
    node: (
      <text {...TEXT} attributes={DIM}>
        {count > 0 ? `  ${arrow} ${count} more` : `  ${arrow}`}
      </text>
    ),
  });

  return [
    ...(top > 0 ? [more(above, '↑')] : []),
    ...lines.slice(top, end),
    ...(end < lines.length ? [more(below, '↓')] : []),
  ];
}

/** Submit: each answer, then Send and Skip. */
function SubmitStep({
  questions,
  state,
  problems,
  agent,
}: {
  questions: Questions;
  state: AskState;
  problems: ReadonlyMap<string, string>;
  agent: string;
}) {
  const colours = useColours();
  const labels = questions.questions.map((_, index) =>
    headerOf(questions, index),
  );
  const labelWidth = Math.max(0, ...labels.map((label) => stringWidth(label)));
  const sendable = problems.size === 0;

  return (
    <box>
      {questions.questions.map((question, index) => {
        const problem = problems.get(question.id);
        const text = answerText(question, state);

        return (
          <box key={question.id} flexDirection='row'>
            <box width={labelWidth + 2} flexShrink={0}>
              <text {...CUT}>
                <Ansi text={labels[index]!} />
              </text>
            </box>
            {problem !== undefined ? (
              <text {...CUT} {...fg(colours.warning)}>
                {problem === 'required'
                  ? `no answer yet, and ${agent} needs one`
                  : problem}
              </text>
            ) : text === undefined ? (
              <text {...CUT} attributes={DIM}>
                no answer
              </text>
            ) : (
              <text {...CUT}>
                <Ansi text={text} />
              </text>
            )}
          </box>
        );
      })}
      <box marginTop={1} flexDirection='row'>
        <Gutter {...paint(colours.permission)}>
          {sendable && state.row === 0 ? '❯' : ' '}
        </Gutter>
        <text
          {...TEXT}
          {...(!sendable
            ? { attributes: DIM }
            : state.row === 0
              ? fg(colours.permission)
              : {})}
        >
          1. Send the answers
        </text>
      </box>
      <box flexDirection='row'>
        <Gutter {...paint(colours.permission)}>
          {(!sendable && state.row >= 0) || state.row === 1 ? '❯' : ' '}
        </Gutter>
        <text
          {...TEXT}
          {...((!sendable && state.row >= 0) || state.row === 1
            ? fg(colours.permission)
            : {})}
        >
          2. Skip these questions
        </text>
      </box>
    </box>
  );
}
