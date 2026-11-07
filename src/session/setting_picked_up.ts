/**
 * What a saved setting changes in a running process. Nothing watches the
 * file and sessions keep what they were started with, so a saved `theme`,
 * `editorMode` or `offeredAgents` takes the same change its command makes, a
 * removed one falling to what an absent key gives; every other key waits for
 * the next start, or is read when it is needed.
 */
import type { EditorMode, SettingChange, Settings } from '../settings.ts';

/** A saved setting's change, as whatever is running takes it up. */
export type SettingPickedUp =
  | {
      readonly key: 'theme';
      readonly theme: NonNullable<Settings['theme']>;
    }
  | { readonly key: 'editorMode'; readonly vim: boolean }
  | {
      readonly key: 'offeredAgents';
      readonly offered: readonly string[] | undefined;
    };

export function settingPickedUp(
  [key, ...deeper]: readonly string[],
  change: SettingChange,
): SettingPickedUp | undefined {
  const value = 'set' in change ? change.set : undefined;

  if (deeper.length > 0) {
    return undefined;
  }

  switch (key) {
    case 'theme':
      return {
        key,
        theme: (value as NonNullable<Settings['theme']>) ?? 'auto',
      };
    case 'editorMode':
      return { key, vim: (value as EditorMode) === 'vim' };
    case 'offeredAgents':
      return { key, offered: value as string[] | undefined };
    default:
      return undefined;
  }
}
