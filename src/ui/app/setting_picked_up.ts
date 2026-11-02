/**
 * A saved setting's change as the window takes it: the same state change the
 * setting's command makes.
 */
import type { ListedAgent } from '../../agents.ts';
import type { SettingPickedUp } from '../../session/setting_picked_up.ts';
import { agentItems } from '../prompt/commands.ts';
import type { AppAction } from './state.ts';

export function settingActions(
  picked: SettingPickedUp | undefined,
  {
    runtimes,
    listed,
  }: {
    readonly runtimes: readonly string[];
    readonly listed: readonly ListedAgent[];
  },
): readonly AppAction[] {
  switch (picked?.key) {
    case 'theme':
      return [{ type: 'theme_chosen', theme: picked.theme }];
    case 'editorMode':
      return [{ type: 'vim_toggled', on: picked.vim }];
    case 'offeredAgents':
      return [
        {
          type: 'agents_offered',
          agents: agentItems(runtimes, listed, picked.offered),
        },
      ];
    case undefined:
      return [];
  }
}
