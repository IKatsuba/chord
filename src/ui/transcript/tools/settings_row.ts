/**
 * The `settings` tool's call on the transcript: its headline, and its rows, a
 * value wrapped at the cell under its own column and never folded, as the row
 * is what the person reads it in.
 */
import wrapAnsi from 'wrap-ansi';
import stringWidth from 'string-width';
import type { ChordCall } from '../../../session/transcript/types.ts';
import { shownSettingPath, shownValue } from '../../../settings.ts';
import { changeWord } from '../../../settings_tool.ts';
import type { Headline } from './tools.ts';

/** One row under the call: a label and what it says, in a role's colour. */
export interface SettingsRow {
  readonly label: string;
  readonly text: string;
  readonly tone: 'text' | 'dim' | 'warning' | 'success';
}

function record(value: unknown): Record<string, unknown> {
  return typeof value === 'object' && value !== null
    ? (value as Record<string, unknown>)
    : {};
}

/** The path asked for, none where an agent sent no list of keys. */
function pathOf(call: Pick<ChordCall, 'input'>): readonly string[] {
  const { path } = record(call.input);

  return Array.isArray(path) && path.every((key) => typeof key === 'string')
    ? (path as string[])
    : [];
}

/** Whether `call` is a read of every key, the one that folds. */
function readsEveryKey(call: ChordCall): boolean {
  return (
    call.tool === 'settings' &&
    call.answer !== undefined &&
    record(call.input).action === 'read' &&
    pathOf(call).length === 0
  );
}

/** What a served call did, as its headline names it. */
function settingsNote(call: ChordCall): string {
  const answer = record(call.answer);

  return record(call.input).action === 'read'
    ? 'read'
    : answer.unchanged === true
      ? 'unchanged'
      : changeWord(answer);
}

/** `Settings(path)`, its note named once served; a refusal has none. */
export function settingsHeadline(call: ChordCall): Headline {
  const path = pathOf(call);

  return {
    name: 'Settings',
    ...(path.length === 0 ? {} : { arg: shownSettingPath(path) }),
    ...(call.answer === undefined ? {} : { note: ` · ${settingsNote(call)}` }),
  };
}

/** A read of every key's headline, which says the key that opens it. */
export function foldedSettingsNote(
  line: Headline,
  call: ChordCall | undefined,
  expanded: boolean,
  key: string | undefined,
): Headline {
  return call !== undefined &&
    !expanded &&
    key !== undefined &&
    readsEveryKey(call)
    ? { ...line, note: `${line.note ?? ''} (${key} to expand)` }
    : line;
}

/** `label` and `text`, the rows past the first under the text's own column. */
function labelled(
  label: string,
  text: string,
  width: number,
  tone: SettingsRow['tone'] = 'text',
): SettingsRow[] {
  const room = Math.max(width - stringWidth(label), 1);

  return wrapAnsi(text, room, { hard: true, trim: false, wordWrap: false })
    .split('\n')
    .map((row, index) => ({
      label: index === 0 ? label : ' '.repeat(stringWidth(label)),
      text: row,
      tone,
    }));
}

/** A value as drawn, an absent one in words. */
function valueWords(value: unknown): string {
  return value === undefined ? 'not set' : shownValue(value);
}

/** A `set` or `remove`: what it changes, then what became of it. */
function changeRows(
  answer: Record<string, unknown>,
  width: number,
): readonly SettingsRow[] {
  const shadow =
    typeof answer.shadowedBy === 'string'
      ? labelled(
          '',
          `${answer.shadowedBy} sets this too, and wins here`,
          width,
          'warning',
        )
      : [];

  if (answer.unchanged === true) {
    const held =
      answer.before === undefined
        ? 'Not set'
        : `Already ${shownValue(answer.before)}`;

    return [
      ...labelled('', `${held}; nothing to change`, width, 'dim'),
      ...shadow,
    ];
  }

  return [
    ...labelled('Now    ', valueWords(answer.before), width),
    ...labelled('After  ', valueWords(answer.after), width),
    ...shadow,
    ...(answer.saved === true
      ? labelled(
          '',
          `Saved to ${String(answer.file)} · takes effect ${
            answer.takesEffect === 'now' ? 'now' : 'at the next start'
          }`,
          width,
          'success',
        )
      : answer.saved === false
        ? labelled(
            '',
            'Not saved · the person will say what to change',
            width,
            'dim',
          )
        : []),
  ];
}

/**
 * The rows under a served `settings` call, none for one with no answer yet or
 * a refusal, which the transcript draws as any of chord's. `width` is the room
 * beside the gutter.
 */
export function settingsRows(
  call: ChordCall,
  expanded: boolean,
  width: number,
): readonly SettingsRow[] | undefined {
  if (call.tool !== 'settings' || call.answer === undefined) {
    return undefined;
  }

  const answer = record(call.answer);

  if (record(call.input).action !== 'read') {
    return changeRows(answer, width);
  }

  if (!readsEveryKey(call)) {
    return [
      ...labelled('Effective  ', valueWords(answer.effective), width),
      ...labelled('User       ', valueWords(answer.user), width),
      ...labelled('Project    ', valueWords(answer.project), width),
    ];
  }

  if (expanded) {
    return shownValue(call.answer, 2)
      .split('\n')
      .flatMap((line) => {
        const indent = /^ */u.exec(line)![0];

        return labelled(indent, line.slice(indent.length), width);
      });
  }

  const problems = Array.isArray(answer.problems) ? answer.problems.length : 0;

  return [
    ...labelled('User     ', call.settingsFiles?.user ?? '', width),
    ...labelled('Project  ', call.settingsFiles?.project ?? '', width),
    ...(problems === 0
      ? []
      : labelled(
          '',
          `${problems} ${problems === 1 ? 'problem' : 'problems'}`,
          width,
          'warning',
        )),
  ];
}
