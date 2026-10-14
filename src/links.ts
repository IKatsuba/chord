/**
 * Opening a link an agent asked the person to open, in the system's browser,
 * through the `open` package: `open` on macOS, `xdg-open` on Linux, `start`
 * on Windows and the Windows browser from WSL. chord calls it only on a key
 * press, never on its own.
 */
import open from 'open';

/** Opens `url` in the system's browser; what went wrong, if anything. */
export type LinkOpener = (url: string) => Promise<string | undefined>;

export const openLink: LinkOpener = async (url) => {
  try {
    await open(url);

    return undefined;
  } catch (error) {
    return error instanceof Error ? error.message : String(error);
  }
};
