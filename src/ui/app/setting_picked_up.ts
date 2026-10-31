/**
 * What a saved setting changes in the running window. Nothing watches the
 * file and sessions keep what they were started with, so a saved `theme`,
 * `editorMode` or `offeredAgents` takes the same state change its command
 * makes, a removed one falling to what an absent key gives; every other key
 * waits for the next start, or is read when it is needed.
 */
import type { ListedAgent } from '../../agents.ts';
import type { EditorMode, SettingChange } from '../../settings.ts';
import { agentItems } from '../prompt/commands.ts';
import type { ThemeSetting } from '../theme/theme.ts';
import type { AppAction } from './state.ts';

export function settingPickedUp(
  [key, ...deeper]: readonly string[],
  change: SettingChange,
  {
    runtimes,
    listed,
  }: {
    readonly runtimes: readonly string[];
    readonly listed: readonly ListedAgent[];
  },
): readonly AppAction[] {
  const value = 'set' in change ? change.set : undefined;

  if (deeper.length > 0) {
    return [];
  }

  switch (key) {
    case 'theme':
      return [
        { type: 'theme_chosen', theme: (value as ThemeSetting) ?? 'auto' },
      ];
    case 'editorMode':
      return [{ type: 'vim_toggled', on: (value as EditorMode) === 'vim' }];
    case 'offeredAgents':
      return [
        {
          type: 'agents_offered',
          agents: agentItems(runtimes, listed, value as string[] | undefined),
        },
      ];
    default:
      return [];
  }
}
