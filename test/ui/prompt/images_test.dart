// From the original's tests/ui/prompt/images_test.ts; cursors are offsets.
import 'package:chord/images.dart';
import 'package:chord/ui/prompt/images.dart';
import 'package:test/test.dart';

PastedImage image(int id, [String? data]) =>
    (id: id, mediaType: 'image/png', data: data ?? 'data-$id', bytes: 4);

const ImageData pixel = (mediaType: 'image/png', data: 'cGl4', bytes: 3);

void main() {
  test('an image stands in the text as Claude Code writes it', () {
    expect(placeholder(1), '[Image #1]');
    expect(placeholder(12), '[Image #12]');
  });

  test('a pasted image goes in at the cursor, apart from the words', () {
    expect(insertImage('', 0, 1), (text: '[Image #1] ', cursor: 11));
    expect(insertImage('what is', 7, 2), (
      text: 'what is [Image #2] ',
      cursor: 19,
    ));
    // Already apart on one side, it adds no second space there.
    expect(insertImage('see  here', 4, 3), (
      text: 'see [Image #3] here',
      cursor: 14,
    ));
    expect(insertImage('one\ntwo', 4, 1), (
      text: 'one\n[Image #1] two',
      cursor: 15,
    ));
  });

  test('a prompt sends the images its placeholders stand for, in their '
      'order', () {
    final images = [image(1), image(2), image(3)];
    expect(imagesIn('[Image #3] then [Image #1]', images).map((i) => i.id), [
      3,
      1,
    ]);
    expect(attachmentsOf('[Image #2]', images), [
      (mimeType: 'image/png', data: 'data-2'),
    ]);
  });

  test('deleting a placeholder, or a part of it, drops its image', () {
    final images = [image(1), image(2)];
    expect(attachmentsOf('just text', images), isEmpty);
    expect(imagesIn('[Image #1', images), isEmpty);
    expect(imagesIn('Image #2]', images), isEmpty);
    expect(imagesIn('[Image #2] [Image #1]', [image(1)]), hasLength(1));
  });

  test('a key that cuts into a placeholder takes the whole of it', () {
    final images = [image(1), image(2)];
    const draft = 'what is [Image #1] this?';
    // Backspace with the cursor after `]`.
    expect(cutPlaceholder(draft, 'what is [Image #1 this?', images), (
      text: 'what is  this?',
      cursor: 8,
    ));
    // Delete with the cursor before `[`.
    expect(cutPlaceholder(draft, 'what is Image #1] this?', images), (
      text: 'what is  this?',
      cursor: 8,
    ));
    // A word deleted back into it.
    expect(cutPlaceholder(draft, 'what is [Image  this?', images), (
      text: 'what is  this?',
      cursor: 8,
    ));
    // ctrl+w straight after a paste.
    expect(cutPlaceholder('cut [Image #1] ', 'cut [Image ', images), (
      text: 'cut ',
      cursor: 4,
    ));
    // On a later line.
    expect(cutPlaceholder('one\n[Image #2] x', 'one\n[Image #2 x', images), (
      text: 'one\n x',
      cursor: 4,
    ));
  });

  test("a change that leaves placeholders whole is the textarea's own", () {
    final images = [image(1)];
    expect(cutPlaceholder('[Image #1] ab', '[Image #1] a', images), isNull);
    expect(cutPlaceholder('[Image #1] ', '[Image #1]', images), isNull);
    expect(cutPlaceholder('x [Image #1]', '', images), isNull);
    expect(cutPlaceholder('[Image #1]', '[Image #1]x', images), isNull);
    // Typed by hand, it stands for no image and edits as text.
    expect(cutPlaceholder('[Image #7]', '[Image #7', images), isNull);
  });

  test('an image named twice goes once; one typed by hand stands for '
      'nothing', () {
    expect(imagesIn('[Image #1] and [Image #1]', [image(1)]), hasLength(1));
    expect(attachmentsOf('[Image #7]', [image(1)]), isEmpty);
  });

  test('a paste is an insertion longer than a key', () {
    expect(pastedText('ab', 'a/x.pngb'), (text: '/x.png', end: 7));
    expect(pastedText('', '/x.png'), (text: '/x.png', end: 6));
    expect(pastedText('ab', 'abc'), isNull);
    expect(pastedText('abc', 'ab'), isNull);
  });

  test('a path names an image when it ends in an image type', () {
    expect(imagePath('/tmp/shot.png'), '/tmp/shot.png');
    expect(imagePath('/tmp/SHOT.JPEG'), '/tmp/SHOT.JPEG');
    expect(imagePath('/tmp/a.webp'), '/tmp/a.webp');
    expect(imagePath('/tmp/a.gif'), '/tmp/a.gif');
    expect(imagePath('/tmp/notes.txt'), isNull);
    expect(imagePath('/tmp/a.svg'), isNull);
  });

  test('a path is read as a terminal writes a dropped file', () {
    expect(imagePath(r'/tmp/my\ shot.png'), '/tmp/my shot.png');
    expect(imagePath("'/tmp/my shot.png'"), '/tmp/my shot.png');
    expect(imagePath('"/tmp/my shot.png"'), '/tmp/my shot.png');
    expect(imagePath('file:///tmp/my%20shot.png'), '/tmp/my shot.png');
    expect(imagePath('~/shot.png', '/srv/me'), '/srv/me/shot.png');
    expect(imagePath('~/shot.png'), isNull);
  });

  test('a relative path stays a path for the agent', () {
    expect(imagePath('assets/logo.png'), isNull);
    expect(namesImage('fix assets/logo.png'), isFalse);
    expect(namesImage('look at /tmp/a.png please'), isTrue);
    expect(namesImage('a@b/c.png'), isFalse);
  });

  test('the image paths in a draft are counted before the reads', () {
    expect(imagePathCount('/a.png and /b.jpg, not c.gif or /d.txt'), 2);
    expect(imagePathCount('no paths'), 0);
  });

  test('image paths become placeholders, numbered on from the last', () async {
    Future<ImageData?> read(String path) async =>
        path.startsWith('/real/') ? pixel : null;
    final taken = await takeImagePaths(
      r'compare /real/a.png with /real/my\ b.jpg, not /gone/c.png',
      4,
      read,
    );
    expect(taken.text, 'compare [Image #4] with [Image #5], not /gone/c.png');
    expect(taken.images.map((i) => i.id), [4, 5]);
  });

  test('a text with no image paths is left as it was', () async {
    final taken = await takeImagePaths('hello', 1, (_) async => pixel);
    expect(taken.text, 'hello');
    expect(taken.images, isEmpty);
  });

  test("ctrl+w takes a held image's placeholder whole with its space, and "
      'nothing else', () {
    final images = [image(1)];
    expect(placeholderBefore('cut [Image #1] ', images), 11);
    expect(placeholderBefore('[Image #1] ', images), 11);
    expect(placeholderBefore('cut [Image #1]', images), 0);
    expect(placeholderBefore('cut [Image #1] x', images), 0);
    expect(placeholderBefore('cut [Image #2] ', images), 0);
  });

  test('a placeholder whose number no int holds stands for nothing', () {
    final images = [image(1)];
    const huge = '[Image #999999999999999999999999999999]';
    expect(imagesIn('$huge [Image #1]', images).map((i) => i.id), [1]);
    expect(attachmentsOf(huge, images), isEmpty);
    expect(
      cutPlaceholder(
        'x $huge',
        'x [Image #99999999999999999999999999999]',
        images,
      ),
      isNull,
    );
    expect(placeholderBefore('cut $huge ', images), 0);
  });

  group('tester: image placeholder edges', () {
    test(
      'each deleted placeholder character removes its held image beside Unicode',
      () {
        const prefix = '界👩‍💻é ';
        const label = '[Image #12]';
        const suffix = ' 界👩‍💻é';
        const before = '$prefix$label$suffix';
        for (var offset = 0; offset < label.length; offset++) {
          final at = prefix.length + offset;
          final after = before.substring(0, at) + before.substring(at + 1);
          expect(cutPlaceholder(before, after, [image(12)]), (
            text: '$prefix$suffix',
            cursor: prefix.length,
          ), reason: 'offset $offset');
        }
      },
    );

    test('a deletion spanning two held placeholders expands both edges', () {
      const before = 'left [Image #1] middle [Image #2] right';
      expect(
        cutPlaceholder(before, 'left [Imag2] right', [image(1), image(2)]),
        (text: 'left  right', cursor: 5),
      );
    });

    test(
      'unreadable paths preserve punctuation and numbering of later successes',
      () async {
        final calls = <String>[];
        final result = await takeImagePaths(
          '界 /gone.png, then "/real/my shot.PNG"; and file:///real/e%CC%81.webp!',
          8,
          (path) async {
            calls.add(path);
            return path.startsWith('/real/') ? pixel : null;
          },
        );
        expect(calls, ['/gone.png', '/real/my shot.PNG', '/real/é.webp']);
        expect(result.text, '界 /gone.png, then [Image #8]; and [Image #9]!');
        expect(result.images.map((i) => i.id), [8, 9]);
      },
    );
  });
}
