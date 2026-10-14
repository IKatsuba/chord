import type {
  PermissionWait,
  SaveBox as SaveBoxQuestion,
  Subagent,
} from '../../session/transcript/types.ts';
import { capital } from '../shortcuts/state.ts';
import { useColours, useHintKey } from '../app/context.ts';
import { borderOf, ChoiceList } from '../pickers/Pickers.tsx';
import { Ansi } from '../theme/Ansi.tsx';
import { BOLD, CUT, DIM, fg, TEXT } from '../theme/text.ts';
import { askerRow } from '../transcript/agents/subagents.ts';
import {
  choicesFor,
  inputLines,
  locationsShown,
  saveChoices,
} from './permission.ts';

/** The question waiting: the agent's, or chord's own save box. */
export function PermissionPrompt(props: Parameters<typeof AgentPermission>[0]) {
  const { wait, active, onChoose } = props;

  return wait.save === undefined ? (
    <AgentPermission {...props} />
  ) : (
    <SaveBox wait={wait} save={wait.save} active={active} onChoose={onChoose} />
  );
}

/**
 * The agent's question, drawn inline above the prompt as Claude Code does:
 * what the tool wants to do, then the agent's own options, numbered.
 * ink-select-input reads 1–9, ↑/↓, j/k and Enter; Esc is the window's.
 */
function AgentPermission({
  wait,
  asker = [],
  child,
  width = 0,
  active,
  onChoose,
}: {
  wait: PermissionWait;
  /** The way down to the subagent that asks; empty when the agent does. */
  asker?: readonly Subagent[];
  /** The long-lived child that asks, picked, with its colour. */
  child?: { readonly name: string; readonly colour: string | undefined };
  /** Cells inside the box's border and padding, for the asker's row. */
  width?: number;
  active: boolean;
  onChoose: (optionId: string) => void;
}) {
  const { accent } = useColours();
  const asks = askerRow(asker, width);

  return (
    <box
      {...borderOf(useColours().permission)}
      paddingX={1}
      marginTop={1}
      flexShrink={0}
    >
      {child !== undefined && asks.length === 0 && (
        <text {...CUT}>
          <span {...fg(child.colour)} attributes={BOLD}>
            {child.name}
          </span>
          {` asks`}
        </text>
      )}
      {asks.length > 0 && (
        <text {...CUT} {...fg(accent)}>
          {asks.map((piece, index) => (
            <span key={index} attributes={piece.bold ? BOLD : 0}>
              <Ansi text={piece.text} />
            </span>
          ))}
        </text>
      )}
      <text {...TEXT} {...fg(useColours().permission)} attributes={BOLD}>
        <Ansi text={wait.title ?? 'Tool call'} />
      </text>
      {locationsShown(wait).map((path) => (
        <text key={path} {...CUT} attributes={DIM}>
          <Ansi text={path} />
        </text>
      ))}
      {inputLines(wait).map((line, index) => (
        <box key={index} paddingLeft={2}>
          <text {...TEXT}>
            <Ansi text={line} />
          </text>
        </box>
      ))}
      <box marginTop={1}>
        <text {...TEXT}>Do you want to proceed?</text>
      </box>
      <ChoiceList
        choices={choicesFor(wait)}
        active={active}
        onSelect={onChoose}
      />
      <PermissionHint />
    </box>
  );
}

/**
 * chord's own question in the permission box's shape, as `propose_team`'s
 * save box: the question, the choices with the file each writes, and what
 * Esc does, which is the last choice.
 */
function SaveBox({
  wait,
  save,
  active,
  onChoose,
}: {
  wait: PermissionWait;
  save: SaveBoxQuestion;
  active: boolean;
  onChoose: (optionId: string) => void;
}) {
  const { permission } = useColours();
  const key = useHintKey('confirm:no');

  return (
    <box {...borderOf(permission)} paddingX={1} marginTop={1} flexShrink={0}>
      <text {...TEXT} {...fg(permission)} attributes={BOLD}>
        {save.question}
      </text>
      <box marginTop={1}>
        <ChoiceList
          choices={saveChoices(wait)}
          active={active}
          onSelect={onChoose}
        />
      </box>
      {key !== undefined && (
        <box marginTop={1}>
          <text {...TEXT} attributes={DIM}>
            {`${capital(key)} to ${save.escape}`}
          </text>
        </box>
      )}
    </box>
  );
}

/** The permission prompt's last line: the key that rejects, when one does. */
function PermissionHint() {
  const key = useHintKey('confirm:no');

  return key === undefined ? null : (
    <box marginTop={1}>
      <text {...TEXT} attributes={DIM}>{`${capital(key)} to reject`}</text>
    </box>
  );
}
