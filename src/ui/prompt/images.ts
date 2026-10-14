/**
 * Images in the prompt: the `[Image #N]` a pasted image puts at the cursor,
 * the paths a draft names that are taken as images, and which images a
 * prompt sends. An image goes with the prompt only while its placeholder is
 * in the text, so deleting the placeholder drops it.
 */
import type { ImageData, ImageFileReader } from '../../images.ts';
import type { Attachment } from '../../session/session.ts';
import type { Cursor } from './prompt.ts';

/** An image the draft holds, by the number its placeholder shows. */
export interface PastedImage extends ImageData {
  readonly id: number;
}

/** What stands for image `id` in the text, as Claude Code writes it. */
export function placeholder(id: number): string {
  return `[Image #${id}]`;
}

const PLACEHOLDER = /\[Image #(\d+)\]/g;

/**
 * The images whose placeholders are in `text`, in the order they appear,
 * each once.
 */
export function imagesIn(
  text: string,
  images: readonly PastedImage[],
): PastedImage[] {
  const found: PastedImage[] = [];

  for (const [, id] of text.matchAll(PLACEHOLDER)) {
    const image = images.find((image) => image.id === Number(id));

    if (image !== undefined && !found.includes(image)) {
      found.push(image);
    }
  }

  return found;
}

/** The images `text` sends, as a prompt takes them. */
export function attachmentsOf(
  text: string,
  images: readonly PastedImage[],
): Attachment[] {
  return imagesIn(text, images).map(({ mediaType, data }) => ({
    mediaType,
    data,
  }));
}

/**
 * The draft with image `id`'s placeholder at the cursor, and the cursor
 * after it. It stands apart from the words round it, as a pasted word
 * would: a space before it after one, and a space after it.
 */
export function insertImage(
  draft: string,
  [line, column]: Cursor,
  id: number,
): { readonly text: string; readonly cursor: Cursor } {
  const lines = draft.split('\n');
  const current = lines[line] ?? '';
  const before = current.slice(0, column);
  const after = current.slice(column);
  const written = `${/\S$/.test(before) ? ' ' : ''}${placeholder(id)}${
    after.startsWith(' ') ? '' : ' '
  }`;

  lines[line] = before + written + after;

  return { text: lines.join('\n'), cursor: [line, column + written.length] };
}

/**
 * What a change to the draft put in, and where it ends in the new draft,
 * when it is one piece longer than a key, as a paste is; none for typing or
 * deleting.
 */
export function pastedText(
  before: string,
  after: string,
): { readonly text: string; readonly end: number } | undefined {
  if (after.length - before.length < 2) {
    return undefined;
  }

  let start = 0;

  while (start < before.length && before[start] === after[start]) {
    start++;
  }

  let end = 0;

  while (
    end < before.length - start &&
    before[before.length - 1 - end] === after[after.length - 1 - end]
  ) {
    end++;
  }

  return {
    text: after.slice(start, after.length - end),
    end: after.length - end,
  };
}

/**
 * A deletion that cut into the placeholder of an image the draft holds,
 * widened to the whole placeholder, with the cursor where it stood; none
 * for any other change. A backspace after `]` or a delete before `[` takes
 * the image, as in Claude Code, rather than leaving half a label that
 * stands for nothing.
 */
export function cutPlaceholder(
  before: string,
  after: string,
  images: readonly PastedImage[],
): { readonly text: string; readonly cursor: Cursor } | undefined {
  if (after.length >= before.length) {
    return undefined;
  }

  let start = 0;

  while (start < after.length && before[start] === after[start]) {
    start++;
  }

  let end = before.length;
  const shift = after.length - before.length;

  // The common end stops where the common start does, or a cut ending in
  // the character it began after looks one short.
  while (end + shift > start && before[end - 1] === after[end + shift - 1]) {
    end--;
  }

  // Anything but a stretch taken out of the old draft is not a deletion.
  if (before.length - (end - start) !== after.length) {
    return undefined;
  }

  let from = start;
  let to = end;

  for (const found of before.matchAll(PLACEHOLDER)) {
    const first = found.index;
    const last = first + found[0].length;
    const held = images.some((image) => image.id === Number(found[1]));
    const cut = first < end && start < last && (first < start || end < last);

    if (held && cut) {
      from = Math.min(from, first);
      to = Math.max(to, last);
    }
  }

  if (from === start && to === end) {
    return undefined;
  }

  const lines = before.slice(0, from).split('\n');

  return {
    text: before.slice(0, from) + before.slice(to),
    cursor: [lines.length - 1, lines.at(-1)?.length ?? 0],
  };
}

/**
 * How much of `before`, the cursor's line up to it, is the placeholder of an
 * image the draft holds with the space after it, as straight after a paste;
 * 0 otherwise. ctrl+w takes that whole, as react-ink-textarea's did, where
 * OpenTUI's stops at the `]` and takes the space alone.
 */
export function placeholderBefore(
  before: string,
  images: readonly PastedImage[],
): number {
  const found = /\[Image #(\d+)\] $/.exec(before);

  return found !== null && images.some((image) => image.id === Number(found[1]))
    ? found[0].length
    : 0;
}

const IMAGE_FILE = /\.(png|jpe?g|gif|webp)$/i;

/**
 * Paths as a terminal puts a dropped file in: `/abs`, `~/…` or `file://…`,
 * whole, quoted, or with its spaces escaped. Only those count, so a relative
 * path in a sentence stays a path for the agent to open.
 */
const PATH =
  /(?<=^|\s)(?:'[^'\n]+'|"[^"\n]+"|(?:~\/|\/|file:\/\/)(?:\\.|\S)+)/g;

/** The file `written` names, when it is an image's name; none otherwise. */
export function imagePath(written: string, home?: string): string | undefined {
  let path = written;

  if (/^(['"]).*\1$/.test(path)) {
    path = path.slice(1, -1);
  } else {
    path = path.replaceAll(/\\(.)/g, '$1');
  }

  if (path.startsWith('file://')) {
    try {
      path = decodeURIComponent(new URL(path).pathname);
    } catch {
      return undefined;
    }
  } else if (path.startsWith('~/')) {
    if (home === undefined) {
      return undefined;
    }

    path = `${home}${path.slice(1)}`;
  }

  return path.startsWith('/') && IMAGE_FILE.test(path) ? path : undefined;
}

/**
 * The paths `text` writes, and where each starts; the stop or comma a
 * sentence puts after one is the sentence's.
 */
function pathsIn(
  text: string,
): { readonly written: string; readonly index: number }[] {
  return [...text.matchAll(PATH)].map((found) => ({
    written: found[0].replace(/(?<!\\)[.,;:!?)]+$/, ''),
    index: found.index,
  }));
}

/** Whether `text` names an image file in a form `takeImagePaths` reads. */
export function namesImage(text: string, home?: string): boolean {
  return imagePathCount(text, home) > 0;
}

/**
 * How many image files `text` names, at most: the numbers `takeImagePaths`
 * may give them before it knows which of the files are there.
 */
export function imagePathCount(text: string, home?: string): number {
  return pathsIn(text).filter(
    ({ written }) => imagePath(written, home) !== undefined,
  ).length;
}

/**
 * `text` with each image file it names in a path's place, as `[Image #N]`,
 * numbered from `next`, and the images read. A path to no file, or to one
 * that is not an image, stays as it was written.
 */
export async function takeImagePaths(
  text: string,
  next: number,
  read: ImageFileReader,
  home?: string,
): Promise<{ readonly text: string; readonly images: PastedImage[] }> {
  const images: PastedImage[] = [];
  let taken = '';
  let from = 0;

  for (const { written, index } of pathsIn(text)) {
    const path = imagePath(written, home);
    const image = path === undefined ? undefined : await read(path);

    if (image === undefined) {
      continue;
    }

    const id = next + images.length;

    images.push({ ...image, id });

    taken += text.slice(from, index) + placeholder(id);
    from = index + written.length;
  }

  return { text: taken + text.slice(from), images };
}
