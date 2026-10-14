/**
 * The images a prompt takes: the one on the system clipboard, read by
 * @mariozechner/clipboard (clipboard-rs, through N-API), and a file a path
 * names. What the bytes are is file-type's word, not the file name's.
 */
import { Buffer } from 'node:buffer';
import { readFile } from 'node:fs/promises';
import { fileTypeFromBuffer } from 'file-type';

/** The image types chord sends: the ones Claude and its kin read. */
export const IMAGE_TYPES: readonly string[] = [
  'image/png',
  'image/jpeg',
  'image/gif',
  'image/webp',
];

/** An image as it goes to the agent, with its size for the person. */
export interface ImageData {
  readonly mediaType: string;
  /** The bytes, base64, as an image block in a prompt takes them. */
  readonly data: string;
  /** How many bytes the image is. */
  readonly bytes: number;
}

/** What reading the clipboard came to: an image, or a sentence why not. */
export type ImageRead =
  { readonly image: ImageData } | { readonly failed: string };

/** Reads the clipboard's image; the system's clipboard by default. */
export type ClipboardReader = () => Promise<ImageRead>;

/** Reads the image a path names; none when it is not one. */
export type ImageFileReader = (path: string) => Promise<ImageData | undefined>;

function messageOf(error: unknown): string {
  return error instanceof Error ? error.message : String(error);
}

/** `bytes` as an image chord sends, or none when they are not one. */
export async function imageOf(
  bytes: Uint8Array,
): Promise<ImageData | undefined> {
  const type = await fileTypeFromBuffer(bytes);

  if (type === undefined || !IMAGE_TYPES.includes(type.mime)) {
    return undefined;
  }

  return {
    mediaType: type.mime,
    data: Buffer.from(bytes).toString('base64'),
    bytes: bytes.length,
  };
}

/**
 * The clipboard's image, as PNG whatever the application put there, since
 * clipboard-rs reads every image type the system knows and writes PNG. The
 * library is loaded here, not at start: a platform its native part does not
 * load on costs ctrl+v, not chord.
 */
export const readClipboardImage: ClipboardReader = async () => {
  let clipboard: typeof import('@mariozechner/clipboard');

  try {
    clipboard = (await import('@mariozechner/clipboard')).default;
  } catch (error) {
    return { failed: `The clipboard cannot be read here: ${messageOf(error)}` };
  }

  try {
    if (!clipboard.hasImage()) {
      return { failed: 'No image in the clipboard' };
    }

    const image = await imageOf(
      Uint8Array.from(await clipboard.getImageBinary()),
    );

    return image === undefined
      ? { failed: 'The clipboard holds an image chord cannot send' }
      : { image };
  } catch (error) {
    return { failed: `The clipboard could not be read: ${messageOf(error)}` };
  }
};

/** The image file at `path`; none when there is none or it is something else. */
export const readImageFile: ImageFileReader = async (path) => {
  try {
    return await imageOf(await readFile(path));
  } catch {
    return undefined;
  }
};
