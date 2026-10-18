import type { ElicitationWait } from '../../session/transcript/types.ts';
import { useColours } from '../app/context.ts';
import { usePress } from '../app/input.ts';
import { borderOf, ChoiceList } from '../pickers/Pickers.tsx';
import { Ansi } from '../theme/Ansi.tsx';
import { BOLD, CUT, DIM, fg, TEXT } from '../theme/text.ts';
import { linkHost } from './form.ts';
import type { Choice } from './permission.ts';
import { AttendHint } from './Permission.tsx';

/**
 * A link the agent asks the person to open, in the permission prompt's
 * shape: the link whole, the host it goes to, then a numbered choice. Nothing
 * opens until a choice is made; Esc answers `cancel`.
 */
export function LinkPrompt({
  wait,
  agent,
  active,
  held = false,
  onAnswer,
}: {
  wait: Extract<ElicitationWait, { mode: 'url' }>;
  agent: string;
  active: boolean;
  /** Asked between turns, the keys not taken into it yet (CHD-158). */
  held?: boolean;
  /** `open` when the person chose to open it. */
  onAnswer: (answer: 'open' | 'decline' | 'cancel') => void;
}) {
  const colours = useColours();
  const host = linkHost(wait.url);
  const choices: Choice[] =
    host === undefined
      ? [{ key: 'decline', label: '1. Decline', value: 'decline' }]
      : [
          { key: 'open', label: '1. Open in the browser', value: 'open' },
          { key: 'decline', label: '2. Decline', value: 'decline' },
        ];

  usePress(
    (_, key) => {
      if (key.escape) {
        onAnswer('cancel');
      }
    },
    { isActive: active },
  );

  return (
    <box
      {...borderOf(colours.permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
      <text {...CUT} {...fg(colours.permission)} attributes={BOLD}>
        {`${agent} asks you to open a link`}
      </text>
      <text {...TEXT}>
        <Ansi text={wait.message} />
      </text>
      <box marginTop={1} paddingLeft={2}>
        <text {...TEXT} {...fg(colours.link)}>
          <Ansi text={wait.url} />
        </text>
        {host === undefined ? (
          <text {...TEXT} {...fg(colours.error)}>
            Not a web link
          </text>
        ) : (
          <text {...TEXT} attributes={DIM}>
            Opens <span attributes={BOLD}>{host}</span>
          </text>
        )}
      </box>
      <box marginTop={1}>
        <ChoiceList
          choices={choices}
          active={active}
          marked={!held}
          onSelect={(value) => onAnswer(value === 'open' ? 'open' : 'decline')}
        />
      </box>
      {held ? (
        <AttendHint />
      ) : (
        <box marginTop={1}>
          <text {...TEXT} attributes={DIM}>
            Enter to choose · Esc to cancel
          </text>
        </box>
      )}
    </box>
  );
}
