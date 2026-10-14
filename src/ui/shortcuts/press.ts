/**
 * A press as OpenTUI parses it, read as chord's own `Press`: pure, so the
 * reading of kitty's base-layout key and of a modifier on its own is tested
 * without a terminal.
 */
import type { KeyEvent } from '@opentui/core';
import type { Press } from './state.ts';

/**
 * A modifier or a lock key pressed on its own, by OpenTUI's names for kitty's
 * codes: a terminal that reports every key sends one ahead of the key it goes
 * with, and it is no key to answer, which would end a chord begun.
 */
export function alone(event: Pick<KeyEvent, 'name'>): boolean {
  return ALONE.test(event.name);
}

const ALONE =
  /^(?:(?:left|right)(?:shift|ctrl|alt|super|hyper|meta)|iso_level[35]_shift|(?:caps|scroll|num)lock)$/;

/** One character that is no control code, as a key's text is. */
const PRINTABLE = /^\P{Cc}$/u;

/**
 * A press as OpenTUI parsed it, in the shape Ink's `useInput` gave, which
 * chord's keys were written against. The key's text is what it types, or
 * the letter a ctrl or alt press is on.
 */
export function pressOf(event: KeyEvent): [string, Press] {
  const { name } = event;
  const key: Press = {
    upArrow: name === 'up',
    downArrow: name === 'down',
    leftArrow: name === 'left',
    rightArrow: name === 'right',
    pageDown: name === 'pagedown',
    pageUp: name === 'pageup',
    home: name === 'home',
    end: name === 'end',
    return: name === 'return' || name === 'enter',
    escape: name === 'escape',
    ctrl: event.ctrl,
    shift: event.shift,
    tab: name === 'tab',
    backspace: name === 'backspace',
    delete: name === 'delete',
    meta: event.meta || event.option,
    super: event.super === true,
  };
  const base = baseOf(event);
  const input =
    name === 'space'
      ? ' '
      : name === 'linefeed'
        ? '\n'
        : event.ctrl || event.meta || event.option
          ? name.length === 1
            ? name
            : ''
          : [...event.sequence].length === 1 && PRINTABLE.test(event.sequence)
            ? event.sequence
            : '';

  return [input, base === undefined ? key : { ...key, base }];
}

/**
 * What each key of the base layout, US PC-101 whatever the person's, types
 * with shift, for a key that is no letter: the protocol's table, not a
 * layout's.
 */
const SHIFTED: Record<string, string> = Object.fromEntries(
  [..."`1234567890-=[]\\;',./"].map((key, index) => [
    key,
    '~!@#$%^&*()_+{}|:"<>?'[index]!,
  ]),
);

/**
 * The key in the press's place on the base layout, which a terminal speaking
 * kitty's protocol names (OpenTUI's `baseCode`), as the character it types:
 * lower case for a letter, as shift is the press's to say, and for any other
 * key with shift held the one US PC-101 types there, `?` for `/`. None where
 * the terminal named none, or named a control code or one of the protocol's
 * own functional keys.
 */
function baseOf({ baseCode, shift }: KeyEvent): string | undefined {
  if (
    baseCode === undefined ||
    baseCode <= 0x20 ||
    baseCode > 0x10ffff ||
    (baseCode >= 0xe000 && baseCode <= 0xf8ff)
  ) {
    return undefined;
  }

  const key = String.fromCodePoint(baseCode).toLowerCase();

  return (shift ? SHIFTED[key] : undefined) ?? key;
}
