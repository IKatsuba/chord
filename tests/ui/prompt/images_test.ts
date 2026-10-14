import { expect, test } from 'bun:test';
import { mkdtemp, rm, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { type ImageData, imageOf, readImageFile } from '../../../src/images.ts';
import {
  attachmentsOf,
  cutPlaceholder,
  imagePath,
  imagePathCount,
  imagesIn,
  insertImage,
  namesImage,
  type PastedImage,
  pastedText,
  placeholder,
  placeholderBefore,
  takeImagePaths,
} from '../../../src/ui/prompt/images.ts';
import { PIXEL_BYTES, PIXEL_PNG } from '../../fixtures/images.ts';

function image(id: number, data = `data-${id}`): PastedImage {
  return { id, mediaType: 'image/png', data, bytes: 4 };
}

const PIXEL: ImageData = {
  mediaType: 'image/png',
  data: PIXEL_PNG,
  bytes: PIXEL_BYTES.length,
};

test('an image stands in the text as Claude Code writes it', () => {
  expect(placeholder(1)).toStrictEqual('[Image #1]');
  expect(placeholder(12)).toStrictEqual('[Image #12]');
});

test('a pasted image goes in at the cursor, apart from the words', () => {
  expect(insertImage('', [0, 0], 1)).toStrictEqual({
    text: '[Image #1] ',
    cursor: [0, 11],
  });
  expect(insertImage('what is', [0, 7], 2)).toStrictEqual({
    text: 'what is [Image #2] ',
    cursor: [0, 19],
  });
  // Already apart on one side, it adds no second space there.
  expect(insertImage('see  here', [0, 4], 3)).toStrictEqual({
    text: 'see [Image #3] here',
    cursor: [0, 14],
  });
  expect(insertImage('one\ntwo', [1, 0], 1)).toStrictEqual({
    text: 'one\n[Image #1] two',
    cursor: [1, 11],
  });
});

test('a prompt sends the images its placeholders stand for, in their order', () => {
  const images = [image(1), image(2), image(3)];

  expect(
    imagesIn('[Image #3] then [Image #1]', images).map(({ id }) => id),
  ).toStrictEqual([3, 1]);
  expect(attachmentsOf('[Image #2]', images)).toStrictEqual([
    { mediaType: 'image/png', data: 'data-2' },
  ]);
});

test('deleting a placeholder, or a part of it, drops its image', () => {
  const images = [image(1), image(2)];

  expect(attachmentsOf('just text', images)).toStrictEqual([]);
  expect(imagesIn('[Image #1', images)).toStrictEqual([]);
  expect(imagesIn('Image #2]', images)).toStrictEqual([]);
  expect(imagesIn('[Image #2] [Image #1]', [image(1)]).length).toStrictEqual(1);
});

test('a key that cuts into a placeholder takes the whole of it', () => {
  const images = [image(1), image(2)];
  const draft = 'what is [Image #1] this?';

  // Backspace with the cursor after `]`.
  expect(
    cutPlaceholder(draft, 'what is [Image #1 this?', images),
  ).toStrictEqual({
    text: 'what is  this?',
    cursor: [0, 8],
  });
  // Delete with the cursor before `[`.
  expect(
    cutPlaceholder(draft, 'what is Image #1] this?', images),
  ).toStrictEqual({
    text: 'what is  this?',
    cursor: [0, 8],
  });
  // A word deleted back into it.
  expect(cutPlaceholder(draft, 'what is [Image  this?', images)).toStrictEqual({
    text: 'what is  this?',
    cursor: [0, 8],
  });
  // ctrl+w straight after a paste: the cut starts inside the placeholder
  // and runs past it, and ends in the space it began after.
  expect(
    cutPlaceholder('cut [Image #1] ', 'cut [Image ', images),
  ).toStrictEqual({
    text: 'cut ',
    cursor: [0, 4],
  });
  // On a later line, the cursor's line and column are that line's.
  expect(
    cutPlaceholder('one\n[Image #2] x', 'one\n[Image #2 x', images),
  ).toStrictEqual({
    text: 'one\n x',
    cursor: [1, 0],
  });
});

test("a change that leaves placeholders whole is the textarea's own", () => {
  const images = [image(1)];

  expect(cutPlaceholder('[Image #1] ab', '[Image #1] a', images)).toStrictEqual(
    undefined,
  );
  expect(cutPlaceholder('[Image #1] ', '[Image #1]', images)).toStrictEqual(
    undefined,
  );
  expect(cutPlaceholder('x [Image #1]', '', images)).toStrictEqual(undefined);
  expect(cutPlaceholder('[Image #1]', '[Image #1]x', images)).toStrictEqual(
    undefined,
  );
  // Typed by hand, it stands for no image and edits as text.
  expect(cutPlaceholder('[Image #7]', '[Image #7', images)).toStrictEqual(
    undefined,
  );
});

test('an image named twice goes once', () => {
  expect(
    imagesIn('[Image #1] and [Image #1]', [image(1)]).length,
  ).toStrictEqual(1);
});

test('a placeholder typed by hand stands for nothing', () => {
  expect(attachmentsOf('[Image #7]', [image(1)])).toStrictEqual([]);
});

test('a paste is an insertion longer than a key', () => {
  expect(pastedText('ab', 'a/x.pngb')).toStrictEqual({
    text: '/x.png',
    end: 7,
  });
  expect(pastedText('', '/x.png')).toStrictEqual({ text: '/x.png', end: 6 });
  expect(pastedText('ab', 'abc')).toStrictEqual(undefined);
  expect(pastedText('abc', 'ab')).toStrictEqual(undefined);
});

test('a path names an image when it ends in an image type', () => {
  expect(imagePath('/tmp/shot.png')).toStrictEqual('/tmp/shot.png');
  expect(imagePath('/tmp/SHOT.JPEG')).toStrictEqual('/tmp/SHOT.JPEG');
  expect(imagePath('/tmp/a.webp')).toStrictEqual('/tmp/a.webp');
  expect(imagePath('/tmp/a.gif')).toStrictEqual('/tmp/a.gif');
  expect(imagePath('/tmp/notes.txt')).toStrictEqual(undefined);
  expect(imagePath('/tmp/a.svg')).toStrictEqual(undefined);
});

test('a path is read as a terminal writes a dropped file', () => {
  expect(imagePath('/tmp/my\\ shot.png')).toStrictEqual('/tmp/my shot.png');
  expect(imagePath("'/tmp/my shot.png'")).toStrictEqual('/tmp/my shot.png');
  expect(imagePath('"/tmp/my shot.png"')).toStrictEqual('/tmp/my shot.png');
  expect(imagePath('file:///tmp/my%20shot.png')).toStrictEqual(
    '/tmp/my shot.png',
  );
  expect(imagePath('~/shot.png', '/srv/me')).toStrictEqual('/srv/me/shot.png');
  expect(imagePath('~/shot.png')).toStrictEqual(undefined);
});

test('a relative path stays a path for the agent', () => {
  expect(imagePath('assets/logo.png')).toStrictEqual(undefined);
  expect(namesImage('fix assets/logo.png')).toStrictEqual(false);
  expect(namesImage('look at /tmp/a.png please')).toStrictEqual(true);
  expect(namesImage('a@b/c.png')).toStrictEqual(false);
});

test('the image paths in a draft are counted before the reads', () => {
  expect(
    imagePathCount('/a.png and /b.jpg, not c.gif or /d.txt'),
  ).toStrictEqual(2);
  expect(imagePathCount('no paths')).toStrictEqual(0);
});

test('image paths become placeholders, numbered on from the last', async () => {
  const read = (path: string) =>
    Promise.resolve(path.startsWith('/real/') ? PIXEL : undefined);
  const taken = await takeImagePaths(
    'compare /real/a.png with /real/my\\ b.jpg, not /gone/c.png',
    4,
    read,
  );

  expect(taken.text).toStrictEqual(
    'compare [Image #4] with [Image #5], not /gone/c.png',
  );
  expect(taken.images.map(({ id }) => id)).toStrictEqual([4, 5]);
});

test('a text with no image paths is left as it was', async () => {
  const taken = await takeImagePaths('hello', 1, () => Promise.resolve(PIXEL));

  expect(taken).toStrictEqual({ text: 'hello', images: [] });
});

test('what an image is comes from its bytes, not its name', async () => {
  expect(await imageOf(PIXEL_BYTES)).toStrictEqual(PIXEL);
  expect(
    await imageOf(new TextEncoder().encode('not an image at all')),
  ).toStrictEqual(undefined);
});

test('an image file is read; anything else at the path is not', async () => {
  const dir = await mkdtemp(join(tmpdir(), 'chord-images-'));

  try {
    await writeFile(join(dir, 'pixel.png'), PIXEL_BYTES);
    await writeFile(join(dir, 'fake.png'), 'text in disguise');

    expect(await readImageFile(join(dir, 'pixel.png'))).toStrictEqual(PIXEL);
    expect(await readImageFile(join(dir, 'fake.png'))).toStrictEqual(undefined);
    expect(await readImageFile(join(dir, 'none.png'))).toStrictEqual(undefined);
    expect(await readImageFile(dir)).toStrictEqual(undefined);
  } finally {
    await rm(dir, { recursive: true });
  }
});

test("ctrl+w takes a held image's placeholder whole with its space, and nothing else", () => {
  const images = [image(1)];

  expect(placeholderBefore('cut [Image #1] ', images)).toStrictEqual(11);
  expect(placeholderBefore('[Image #1] ', images)).toStrictEqual(11);
  // Anywhere else ctrl+w is the textarea's word cut.
  expect(placeholderBefore('cut [Image #1]', images)).toStrictEqual(0);
  expect(placeholderBefore('cut [Image #1] x', images)).toStrictEqual(0);
  expect(placeholderBefore('cut [Image #2] ', images)).toStrictEqual(0);
});
