import type { SignIn } from '../../session/sign_in.ts';
import { offersLine, wayOn } from '../../session/sign_in.ts';
import { pinLine } from '../../session/start_failure.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { BOLD, FILL } from '../theme/text.ts';
import { Under } from '../transcript/tools/Tool.tsx';

/**
 * Under a start failure the agent needs a login for, its result: the
 * registry's pin chord ran, when `pinned` (CHD-454), the ways in `agent`
 * offers, each its name bold and its description after, in the agent's own
 * words, then chord's way on (docs/design/CHD-435.md).
 */
export function SignInBlock({
  agent,
  signIn,
  pinned,
}: {
  agent: string;
  signIn: SignIn;
  pinned?: string | undefined;
}) {
  const { ways } = signIn;

  return (
    <>
      {pinned !== undefined && (
        <Under first>
          <text {...FILL}>{pinLine(pinned)}</text>
        </Under>
      )}
      {ways.length > 0 && (
        <Under first={pinned === undefined}>
          <text {...FILL}>{offersLine(agent, ways.length)}</text>
        </Under>
      )}
      {ways.map((way, index) => (
        <Under key={index} first={false}>
          {/* Indented under the text, a wrapped description hangs there. */}
          <box paddingLeft={2} flexGrow={1} flexShrink={1}>
            <text {...FILL}>
              {way.name !== undefined && (
                <Ansi text={way.name} attributes={BOLD} />
              )}
              {way.name !== undefined && way.description !== undefined
                ? ' · '
                : ''}
              {way.description !== undefined && <Ansi text={way.description} />}
            </text>
          </box>
        </Under>
      ))}
      <Under first={pinned === undefined && ways.length === 0}>
        <text {...FILL}>{wayOn(agent)}</text>
      </Under>
    </>
  );
}
