import { TextAttributes } from '@opentui/core';
import { type ReactNode, useRef, useState } from 'react';
import stringWidth from 'string-width';
import wrapAnsi from 'wrap-ansi';
import type { ElicitationReply } from '../../session/elicitations.ts';
import type { Questions } from '../../session/questions.ts';
import type { ElicitationWait, Entry } from '../../session/transcript/types.ts';
import { paint, useColours } from '../app/context.ts';
import { usePress } from '../app/input.ts';
import { borderOf } from '../pickers/Pickers.tsx';
import { BLOCK } from '../prompt/Prompt.tsx';
import { Ansi } from '../theme/Ansi.tsx';
import { BOLD, CUT, DIM, fg, FILL, TEXT } from '../theme/text.ts';
import { Gutter } from '../transcript/tools/Tool.tsx';
import {
  answeredRows,
  answeredText,
  formHint,
  formKey,
  type FormRow,
  formRows,
  type FormState,
  openForm,
  rowKeys,
  toFix,
  type ValueView,
} from './form.ts';
import { answeredQuestions, askedHeaders } from './questions.ts';
import { Fold } from './Fold.tsx';
import { AttendHint } from './Permission.tsx';
import type { AskerPart } from './asker.ts';
import { AskerHeading } from './Asker.tsx';

/** Between the label column and the values. */
export const FORM_GAP = 2;

/**
 * How a form or link was answered: what the agent asked, as a permission's
 * answer is drawn, then the answer under `⎿`. ctrl+o shows the values an
 * accepted form sent. A request out of a tool call hangs under that call.
 */
export function ElicitationRecord({
  entry,
  agent,
  expanded,
}: {
  entry: Extract<Entry, { kind: 'elicitation' }>;
  agent: string;
  expanded: boolean;
}) {
  const colours = useColours();
  const { wait, outcome, content } = entry;

  if (wait.mode === 'form' && wait.questions !== undefined) {
    return (
      <QuestionsRecord
        entry={entry}
        questions={wait.questions}
        agent={agent}
        hangs={wait.toolCallId !== undefined}
      />
    );
  }

  const opened = outcome === 'accepted' && wait.mode === 'url';
  const text = opened
    ? `Opened ${wait.url}`
    : outcome === 'accepted'
      ? answeredText(content)
      : outcome === 'declined'
        ? 'Declined'
        : 'Cancelled';
  const tone = fg(
    opened
      ? colours.link
      : outcome === 'accepted'
        ? colours.success
        : colours.error,
  );
  const rows =
    expanded &&
    outcome === 'accepted' &&
    wait.mode === 'form' &&
    content !== undefined
      ? answeredRows(wait.schema, content)
      : [];
  const labelWidth = Math.max(0, ...rows.map((row) => stringWidth(row.label)));

  return (
    <box
      {...(wait.toolCallId === undefined ? { marginTop: 1 } : {})}
      flexShrink={0}
    >
      {wait.toolCallId === undefined && (
        <box flexDirection='row'>
          <Gutter>⏺</Gutter>
          <text {...FILL}>
            {`${agent} asked: `}
            <Ansi text={wait.message} />
          </text>
        </box>
      )}
      <box flexDirection='row' paddingLeft={2}>
        <Gutter width={3} dimColor>
          ⎿
        </Gutter>
        <text {...FILL} {...tone}>
          <Ansi text={text} />
        </text>
      </box>
      {rows.map((row) => (
        <box key={row.label} flexDirection='row' paddingLeft={5}>
          <box width={labelWidth + FORM_GAP} flexShrink={0}>
            <text {...TEXT}>
              <Ansi text={row.label} />
            </text>
          </box>
          <text {...CUT}>
            <Ansi text={row.value} />
          </text>
        </box>
      ))}
    </box>
  );
}

/** How a box of questions ended, in words: none for one that was answered. */
const ENDED: Readonly<Record<string, string>> = {
  declined: 'Skipped',
  cancelled: 'Cancelled',
  timed_out: 'Timed out',
};

/**
 * How an agent's questions were answered: a row per question, its header
 * and the answer, or how the box ended. Out of a tool call it hangs under
 * the call; out of none, right under the turn's prompt, saying who asked.
 * One not answered names its questions before how it ended.
 */
function QuestionsRecord({
  entry,
  questions,
  agent,
  hangs,
}: {
  entry: Extract<Entry, { kind: 'elicitation' }>;
  questions: Questions;
  agent: string;
  hangs: boolean;
}) {
  const colours = useColours();
  const asked = hangs ? '' : `${agent} asked · `;
  const ended = ENDED[entry.outcome];
  const rows =
    ended === undefined
      ? answeredQuestions(questions, entry.content ?? {})
      : [];
  const labelWidth = Math.max(0, ...rows.map((row) => stringWidth(row.label)));
  const line = (index: number, children: ReactNode) => (
    <box
      key={index}
      flexDirection='row'
      paddingLeft={index === 0 ? 2 : 5 + stringWidth(asked)}
    >
      {index === 0 && (
        <Gutter width={3} dimColor>
          ⎿
        </Gutter>
      )}
      {children}
    </box>
  );

  return (
    <box flexShrink={0}>
      {ended !== undefined
        ? line(
            0,
            <text {...FILL}>
              {asked}
              <Ansi text={`${askedHeaders(questions)} · `} />
              <span {...fg(colours.error)}>{ended}</span>
            </text>,
          )
        : rows.map((row, index) =>
            line(
              index,
              <>
                {index === 0 && asked !== '' && (
                  <text {...TEXT} flexShrink={0}>
                    {asked}
                  </text>
                )}
                <box width={labelWidth + FORM_GAP} flexShrink={0}>
                  <text {...TEXT}>
                    <Ansi text={row.label} />
                  </text>
                </box>
                <text {...CUT}>
                  <Ansi text={row.value} />
                </text>
              </>,
            ),
          )}
    </box>
  );
}

/**
 * A form the agent asks the person to fill in, in the prompt box's place:
 * one row a field, its status, label and value in columns, the focused
 * field's description or any field's error under it, then Accept and
 * Decline. What each key does is `formKey`'s; this only draws.
 */
export function ElicitationForm({
  hidden = false,
  wait,
  filled,
  agent,
  asker,
  windowRows,
  width,
  active,
  held = false,
  between = false,
  onFill,
  onAnswer,
  onLeave,
}: {
  /**
   * Not drawn, its state kept, while the background view stands in its
   * place (CHD-462).
   */
  hidden?: boolean;
  wait: Extract<ElicitationWait, { mode: 'form' }>;
  /**
   * Asked with no turn running: its heading names `agent` as who asks and
   * says so, dim, wrapping rather than cut (CHD-158).
   */
  between?: boolean;
  /** Asked between turns, the keys not taken into it yet (CHD-158). */
  held?: boolean;
  /**
   * The form as it was left, when it was on screen before: switching to
   * another session draws this one anew.
   */
  filled?: FormState | undefined;
  agent: string;
  /**
   * Who asks, as the heading names it; `agent` alone, plain, when not given
   * (CHD-389).
   */
  asker?: readonly AskerPart[];
  windowRows: number;
  /** The window's width; the box takes all of it. */
  width: number;
  active: boolean;
  onFill?: (form: FormState) => void;
  onAnswer: (response: ElicitationReply) => void;
  /** ↓ past the buttons, where there is a list of agents to go to. */
  onLeave?: () => void;
}) {
  const [form, setForm] = useState(() => filled ?? openForm(wait.schema));
  // Keys that land in one tick each see the one before.
  const latest = useRef(form);
  const colours = useColours();
  const inner = Math.max(width - 4, 10);

  usePress(
    (input, key) => {
      const step = formKey(latest.current, input, key);

      latest.current = step.form;

      setForm(step.form);
      onFill?.(step.form);

      if (step.response) {
        onAnswer(step.response);
      }

      if (step.leave) {
        onLeave?.();
      }
    },
    { isActive: active },
  );

  const { title, description } = wait.schema;
  const says = `asks for input${title ? ` · ${title}` : ''}`;
  const limit = formRowLimit(windowRows);
  const fixed = FORM_CHROME + (description ? 1 : 0);
  const message = messageLines(wait.message, inner, limit - fixed);
  const rows = formRows(form, limit - fixed - message.length);
  const labelWidth = Math.min(
    Math.max(0, ...form.fields.map((field) => stringWidth(field.label))),
    Math.floor(inner / 3),
  );
  const valueAt = FORM_MARKS + labelWidth + FORM_GAP;
  const keys = rowKeys(rows);
  // Held, nothing reads as where the keys are, as they are not here.
  const shown = held ? rows.map(unmarked) : rows;
  const on = held ? undefined : form.focus.on;
  const fix = toFix(form);

  return (
    <box
      {...borderOf(colours.permission)}
      visible={!hidden}
      paddingX={1}
      marginTop={1}
      flexShrink={held ? 1 : 0}
    >
      <Fold held={held}>
        <AskerHeading
          asker={asker ?? [{ text: agent, tone: 'plain' }]}
          says={says}
          between={between}
        />
        {message.map((line, index) => (
          <text key={index} {...TEXT}>
            <Ansi text={line} />
          </text>
        ))}
        {description && (
          <text {...CUT} attributes={DIM}>
            <Ansi text={description} />
          </text>
        )}
        <box marginTop={1}>
          {shown.map((row, index) => (
            <FormLine
              key={keys[index]}
              row={row}
              labelWidth={labelWidth}
              valueAt={valueAt}
            />
          ))}
        </box>
        <box flexDirection='row' marginTop={rows.length > 0 ? 1 : 0}>
          <Gutter {...paint(colours.permission)}>
            {on === 'accept' ? '❯' : ' '}
          </Gutter>
          <text
            {...TEXT}
            attributes={on === 'accept' ? BOLD : 0}
            {...(on === 'accept' ? fg(colours.success) : {})}
          >
            Accept
          </text>
          <box width={1} flexShrink={1} />
          <Gutter {...paint(colours.permission)}>
            {on === 'decline' ? '❯' : ' '}
          </Gutter>
          <text {...TEXT} {...(on === 'decline' ? fg(colours.error) : {})}>
            Decline
          </text>
          {fix > 0 && (
            <text {...TEXT} {...fg(colours.error)}>
              {`     ${fix} field${fix === 1 ? '' : 's'} to fix`}
            </text>
          )}
        </box>
      </Fold>
      {held ? (
        <AttendHint />
      ) : (
        <box marginTop={1}>
          <text {...CUT} attributes={DIM}>
            {formHint(form, inner)}
          </text>
        </box>
      )}
    </box>
  );
}

/** `row` as drawn while the keys are elsewhere: no `❯`, no highlight. */
function unmarked(row: FormRow): FormRow {
  switch (row.kind) {
    case 'field':
      return { ...row, focused: false };
    case 'option':
      return { ...row, highlighted: false };
    default:
      return row;
  }
}

/** The `❯` and status columns before a field's label. */
const FORM_MARKS = 4;

/**
 * The box's rows besides its message and fields: the border, the title, the
 * blank rows around the fields, the buttons and the hint.
 */
const FORM_CHROME = 8;

/**
 * The most rows the box takes: the window less the header and five rows of
 * transcript above it and the status line below, so the prompt the form
 * answers and the working line stay in sight.
 */
export function formRowLimit(windowRows: number): number {
  return Math.max(windowRows - 7, FORM_CHROME + 4);
}

/**
 * The agent's message, wrapped to the box, cut with `…` where it would leave
 * fewer than three rows for the fields.
 */
function messageLines(message: string, width: number, room: number): string[] {
  const lines = wrapAnsi(message, width, { hard: true, trim: false }).split(
    '\n',
  );
  const keep = Math.max(room - 3, 1);

  if (lines.length <= keep) {
    return lines;
  }

  const last = lines[keep - 1] ?? '';

  return [
    ...lines.slice(0, keep - 1),
    `${last.slice(0, Math.max(width - 1, 0)).trimEnd()}…`,
  ];
}

/** One row of the form's field area. */
function FormLine({
  row,
  labelWidth,
  valueAt,
}: {
  row: FormRow;
  labelWidth: number;
  valueAt: number;
}) {
  const colours = useColours();

  switch (row.kind) {
    case 'field': {
      const invalid = row.status === 'invalid';
      const labelTone = row.focused
        ? {
            attributes: BOLD,
            ...fg(invalid ? colours.error : colours.permission),
          }
        : {};

      return (
        <box flexDirection='row'>
          <Gutter {...paint(colours.permission)}>
            {row.focused ? '❯' : ' '}
          </Gutter>
          {row.status === 'valid' ? (
            <Gutter dimColor>✔</Gutter>
          ) : (
            <Gutter {...paint(colours.error)}>
              {row.status === 'required' ? '*' : invalid ? '⚠' : ' '}
            </Gutter>
          )}
          <box width={labelWidth + FORM_GAP} flexShrink={0}>
            <text {...CUT} {...labelTone}>
              <Ansi text={row.field.label} />
            </text>
          </box>
          <FieldValueText value={row.value} />
        </box>
      );
    }
    case 'note':
      return (
        <box paddingLeft={valueAt}>
          <text
            {...CUT}
            {...(row.error ? fg(colours.error) : { attributes: DIM })}
          >
            <Ansi text={row.text} />
          </text>
        </box>
      );
    case 'option': {
      const label =
        row.number === undefined
          ? `${row.ticked ? '☒' : '☐'} ${row.option.title}`
          : `${row.number}. ${row.option.title}${row.current ? ' ✔' : ''}`;

      return (
        <box flexDirection='row' paddingLeft={valueAt}>
          <Gutter {...paint(colours.permission)}>
            {row.highlighted ? '❯' : ' '}
          </Gutter>
          <text {...CUT} {...(row.highlighted ? fg(colours.permission) : {})}>
            <Ansi text={label} />
          </text>
        </box>
      );
    }
    case 'more':
      return (
        <box paddingLeft={FORM_MARKS}>
          <text {...TEXT} attributes={DIM}>
            {`${row.direction === 'up' ? '↑' : '↓'} ${row.count} more field${
              row.count === 1 ? '' : 's'
            }`}
          </text>
        </box>
      );
  }
}

/** A field's value, with the cursor where it is being typed in. */
function FieldValueText({ value }: { value: ValueView }) {
  if (value.cursor === undefined) {
    return (
      <text {...CUT} attributes={value.dim === true ? DIM : 0}>
        <Ansi text={value.text} />
      </text>
    );
  }

  const chars = [...value.text];
  const before = chars.slice(0, value.cursor).join('');
  const at = chars[value.cursor];
  const after = chars.slice(value.cursor + 1).join('');

  return (
    <text {...CUT}>
      <Ansi text={before} />
      <span attributes={TextAttributes.INVERSE}>{at ?? BLOCK}</span>
      <Ansi text={after} />
    </text>
  );
}
