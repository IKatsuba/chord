import { useEffect, useState } from 'react';
import wrapAnsi from 'wrap-ansi';
import { useColours } from '../app/context.ts';
import { usePress } from '../app/input.ts';
import { borderOf, PickerList } from '../pickers/Pickers.tsx';
import { choiceLines } from '../pickers/picker.ts';
import { framedRows } from '../prompt/overlay.ts';
import { Ansi } from '../theme/Ansi.tsx';
import { BOLD, DIM, FILL, TEXT, fg } from '../theme/text.ts';
import { Gutter, Under } from '../transcript/tools/Tool.tsx';
import { useGap } from '../transcript/gap.ts';
import { signInView } from './sign_in.ts';
import type { RiffNotice as Notice, RiffState } from './state.ts';

export function SignInBox({
  state,
  store,
  width,
  room,
  onChoose,
  onBack,
}: {
  state: RiffState;
  store: string;
  width: number;
  room: number;
  onChoose: (value: string) => void;
  onBack: () => void;
}) {
  const colours = useColours();
  const [now, setNow] = useState(Date.now);

  useEffect(() => {
    const timer = setInterval(() => setNow(Date.now()), 1000);

    return () => clearInterval(timer);
  }, []);

  usePress((_input, key) => {
    if (key.escape) {
      onBack();
    }
  });

  const view = signInView(state, store, now, width <= 80);

  if (view === undefined) {
    return null;
  }

  const inner = Math.max(1, width - 6);
  const address =
    view.address === undefined
      ? []
      : wrapAnsi(view.address, Math.max(1, inner - 2), {
          hard: true,
          wordWrap: false,
        }).split('\n');
  const folded = address.length > 1 && room < 25;
  const choices = view.choices.map((choice) => ({ ...choice, hang: 0 }));
  const choiceRows = choices.reduce(
    (sum, choice) => sum + choiceLines(choice, Math.max(1, inner - 4)).length,
    0,
  );
  const minimum = 7 + choiceRows;
  const bodyRoom = Math.max(
    0,
    room - minimum - (view.working === undefined ? 0 : 1),
  );
  const visibleRows = framedRows(
    choiceRows,
    room - bodyRoom - (view.working === undefined ? 0 : 1),
    choiceRows,
  );
  const hasBody =
    view.body !== undefined ||
    view.address !== undefined ||
    view.code !== undefined ||
    view.foot !== undefined;

  return (
    <box flexShrink={0} maxHeight={room}>
      {view.working !== undefined && (
        <text {...TEXT} {...fg(colours.accent)}>{` ››› ${view.working}`}</text>
      )}
      <box
        {...borderOf(colours.permission)}
        paddingX={1}
        flexShrink={1}
        minHeight={0}
      >
        <text
          {...TEXT}
          {...fg(colours.permission)}
          attributes={BOLD}
          flexShrink={0}
        >
          {view.title}
        </text>
        {hasBody && (
          <box
            marginTop={1}
            flexShrink={1}
            minHeight={0}
            maxHeight={bodyRoom}
            overflow='hidden'
          >
            {view.body !== undefined && (
              <text
                {...TEXT}
                {...(view.tone === undefined ? {} : fg(colours[view.tone]))}
              >
                {view.body}
              </text>
            )}
            {view.address !== undefined && (
              <box marginTop={view.body === undefined ? 0 : 1} flexShrink={0}>
                <text
                  {...TEXT}
                  {...fg(colours.link)}
                >{`  ${(folded ? address.slice(0, 1) : address).join('\n  ')}`}</text>
                {folded && (
                  <text
                    {...TEXT}
                    attributes={DIM}
                  >{`  … +${address.length - 1} lines (${state.flow?.step.kind === 'browser' ? '2' : '3'} to copy the whole address)`}</text>
                )}
                {width > 80 && (
                  <text
                    {...TEXT}
                    attributes={DIM}
                  >{`  Opens ${new URL(view.address).hostname}`}</text>
                )}
              </box>
            )}
            {view.code !== undefined && (
              <text
                {...TEXT}
                marginTop={1}
                attributes={BOLD}
              >{`  ${view.code}`}</text>
            )}
            {view.foot !== undefined && (
              <text {...TEXT} marginTop={1}>
                {view.foot}
              </text>
            )}
          </box>
        )}
        {visibleRows > 0 && (
          <box flexShrink={0}>
            <PickerList
              key={`${state.flow?.attempt}:${state.flow?.step.kind}:${state.logout?.pending}`}
              choices={choices}
              rows={visibleRows}
              width={inner}
              active
              onPick={onChoose}
            />
          </box>
        )}
        <text {...TEXT} marginTop={1} flexShrink={0} attributes={DIM}>
          {view.choices.length > 0 && visibleRows === 0
            ? view.hint.split(' · ').at(-1)
            : view.hint}
        </text>
      </box>
    </box>
  );
}

export function RiffNotice({ notice }: { notice: Notice }) {
  const gap = useGap();
  const colours = useColours();
  const heading = notice.title !== undefined || notice.command !== undefined;

  return (
    <>
      {heading && gap.spacer}
      <box {...(heading ? gap.props : {})} flexShrink={0}>
        {heading && (
          <box flexDirection='row'>
            <Gutter>{notice.command === undefined ? '⏺' : '›'}</Gutter>
            <text {...FILL} {...(notice.error ? fg(colours.error) : {})}>
              <Ansi
                text={
                  notice.command === undefined
                    ? (notice.title ?? '')
                    : `/${notice.command}`
                }
              />
            </text>
          </box>
        )}
        {notice.text !== undefined && (
          <Under first>
            <text {...FILL} attributes={DIM}>
              <Ansi text={notice.text} />
            </text>
          </Under>
        )}
      </box>
    </>
  );
}
