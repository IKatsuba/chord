/**
 * chord's note to an agent whose calls of chord's own tools were cut off
 * before they reached chord, as Claude's adapter cuts a batch a steer
 * interrupts (docs/design/CHD-417.md): what happened to each, then what to
 * do, a sentence a line, in the order the calls were made.
 */
import type { ChordCall } from './transcript/types.ts';

/** A call of chord's tools that never reached chord. */
export type CutCall = Pick<ChordCall, 'tool' | 'input'>;

/** How much of a message's first line the note quotes, in characters. */
const QUOTED = 60;

function field(input: unknown, key: string): string | undefined {
  const value =
    typeof input === 'object' && input !== null
      ? (input as Record<string, unknown>)[key]
      : undefined;

  return typeof value === 'string' && value.trim() !== ''
    ? value.trim()
    : undefined;
}

/**
 * The start of a message's text, so an agent that sent several knows which
 * was lost: its first line, cut at `QUOTED` characters with `…`.
 */
function quoted(text: string): string {
  const first = [...(text.split('\n')[0] ?? '')];

  return first.length > QUOTED
    ? `${first.slice(0, QUOTED).join('').trimEnd()}…`
    : first.join('');
}

/**
 * The sentence for one cut call: a message names its recipient, `main` for
 * one to the agent that started the sender, as its row does, and quotes its
 * start; any other call names the tool.
 */
export function cutSentence(call: CutCall): string {
  if (call.tool !== 'send_message') {
    return `Your ${call.tool} call was cut off before it reached chord and did nothing. Call it again if you still need it, on its own.`;
  }

  const text = field(call.input, 'text');

  return `Your send_message to @${field(call.input, 'to') ?? 'main'} was cut off before it reached chord and was not delivered${
    text === undefined ? '' : ` ("${quoted(text)}")`
  }. Send it again, on its own.`;
}

/** The note for the calls cut since the agent's last turn, a line each. */
export function cutNote(calls: readonly CutCall[]): string {
  return calls.map(cutSentence).join('\n');
}
