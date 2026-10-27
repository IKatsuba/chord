import { recordedSelection } from '../../session/team_selection.ts';
import type { ChordCall } from '../../session/transcript/types.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { DIM, FILL, fg } from '../theme/text.ts';
import { useColours } from '../app/context.ts';
import { wrapLine } from '../transcript/message.ts';
import { Under } from '../transcript/tools/Tool.tsx';
import { selectionLines } from '../transcript/tools/selection_lines.ts';

/** An owned record report, with no ACP tool marker or claim of live work. */
export function RecordedReceipt({
  call,
  historical,
  width,
}: {
  call: ChordCall;
  historical: boolean;
  width: number;
}) {
  const colours = useColours();
  const receipt = recordedSelection(call);

  if (receipt === undefined) {
    return null;
  }

  const input = call.input;
  const job =
    typeof input === 'object' &&
    input !== null &&
    'job' in input &&
    typeof input.job === 'string'
      ? input.job
      : undefined;
  const lines = [
    `Recorded by Chord · current state unknown${historical ? ' · historical observation' : ''}`,
    'Recorded: time unknown',
    ...(job === undefined ? [] : job.split('\n')),
    ...selectionLines(receipt, true, true),
    ...(call.error === undefined ? [] : [`Recorded failure: ${call.error}`]),
  ];

  return (
    <box marginTop={1} flexShrink={0}>
      <text {...FILL}>
        <Ansi text={`Recorded Team receipt (${receipt.saved.name})`} />
      </text>
      {lines
        .flatMap((line, index) =>
          wrapLine(line, Math.max(1, width - 5)).map((text) => ({
            text,
            dim:
              index < 2 ||
              line.startsWith('Read ') ||
              line.startsWith('Read:') ||
              line.startsWith('Billing:') ||
              line.startsWith('Run:'),
            failed:
              call.error !== undefined && line.startsWith('Recorded failure:'),
          })),
        )
        .map(({ text, dim, failed }, index) => (
          <Under key={index} first={index === 0}>
            <text
              {...FILL}
              attributes={dim ? DIM : 0}
              {...(failed ? fg(colours.error) : {})}
            >
              <Ansi text={text} attributes={dim ? DIM : 0} />
            </text>
          </Under>
        ))}
    </box>
  );
}
