import type { ElicitationWait } from '../../session/transcript/types.ts';
import { useColours } from '../app/context.ts';
import { usePress } from '../app/input.ts';
import { borderOf, ChoiceList, type KeptChoice } from '../pickers/Pickers.tsx';
import { Ansi } from '../theme/Ansi.tsx';
import { BOLD, DIM, fg, TEXT } from '../theme/text.ts';
import { linkHost } from './form.ts';
import type { Choice } from './permission.ts';
import { Fold } from './Fold.tsx';
import { AttendHint } from './Permission.tsx';
import type { AskerPart } from './asker.ts';
import { AskerHeading } from './Asker.tsx';

/**
 * A link the agent asks the person to open, in the permission prompt's
 * shape: the link whole, the host it goes to, then a numbered choice. Nothing
 * opens until a choice is made; Esc answers `cancel`.
 */
export function LinkPrompt({
  hidden = false,
  wait,
  agent,
  asker,
  active,
  held = false,
  between = false,
  onAnswer,
  kept,
}: {
  /**
   * Not drawn, its state kept, while the background view stands in its
   * place (CHD-462).
   */
  hidden?: boolean;
  wait: Extract<ElicitationWait, { mode: 'url' }>;
  /**
   * Asked with no turn running: its heading names `agent` as who asks and
   * says so, dim, wrapping rather than cut (CHD-158).
   */
  between?: boolean;
  agent: string;
  /**
   * Who asks, as the heading names it; `agent` alone, plain, when not given
   * (CHD-389).
   */
  asker?: readonly AskerPart[];
  active: boolean;
  /** Asked between turns, the keys not taken into it yet (CHD-158). */
  held?: boolean;
  /** `open` when the person chose to open it. */
  onAnswer: (answer: 'open' | 'decline' | 'cancel') => void;
  /** Its choice kept with its agent, and the way out to the agents list. */
  kept?: KeptChoice;
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
      visible={!hidden}
      paddingX={1}
      marginTop={1}
      flexShrink={held ? 1 : 0}
    >
      <Fold held={held}>
        <AskerHeading
          asker={asker ?? [{ text: agent, tone: 'plain' }]}
          says='asks you to open a link'
          between={between}
        />
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
            onSelect={(value) =>
              onAnswer(value === 'open' ? 'open' : 'decline')
            }
            {...kept}
          />
        </box>
      </Fold>
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
