/**
 * What chord tells OpenTUI's native side of how the terminal measures text.
 *
 * Under tmux OpenTUI measures by code point (`wcwidth`), where tmux draws an
 * emoji with VS16 two cells wide, so it goes blank (anomalyco/opentui#1654).
 * It measures by grapheme where told to; this can go once that is fixed.
 */
const FORCE_UNICODE = 'OPENTUI_FORCE_UNICODE';
const OWN_SETTINGS = ['OPENTUI_FORCE_WCWIDTH', FORCE_UNICODE];

/**
 * Whether OpenTUI takes this for tmux from the environment, as `terminal.zig`
 * does at 0.8.1, in its order: `TMUX` set at all; else, outside Zellij and
 * screen, `TERM` starting `tmux`; else, outside Zellij, `TERM_PROGRAM` of
 * `tmux`. No wider, so chord never overrules it elsewhere.
 */
export function seesTmux(get: (name: string) => string | undefined): boolean {
  const zellij =
    get('ZELLIJ') !== undefined ||
    get('ZELLIJ_SESSION_NAME') !== undefined ||
    get('ZELLIJ_PANE_ID') !== undefined;

  return (
    get('TMUX') !== undefined ||
    (!zellij &&
      get('STY') === undefined &&
      get('TERM')?.startsWith('tmux') === true) ||
    (!zellij && get('TERM_PROGRAM') === 'tmux')
  );
}

/**
 * The `environment` for OpenTUI's renderer, which goes to its native side only,
 * so no process chord starts inherits it. A person's own setting wins, as
 * OpenTUI reads theirs from the process.
 */
export function rendererEnvironment(
  get: (name: string) => string | undefined,
): Readonly<Record<string, string>> {
  return seesTmux(get) && OWN_SETTINGS.every((name) => get(name) === undefined)
    ? { [FORCE_UNICODE]: '1' }
    : {};
}
