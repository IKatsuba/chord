import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chord/images.dart';
import 'package:chord_tui/chord_tui.dart';
import 'package:test/test.dart';

final png = Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 13, 10, 26, 10, 0]);
final gif = Uint8List.fromList(ascii.encode('GIF89a') + [1, 0, 1, 0]);
final jpeg = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0, 0, 16]);
final webp = Uint8List.fromList(
  ascii.encode('RIFF') + [0x24, 0, 0, 0] + ascii.encode('WEBPVP8 '),
);

class _Clipboard extends Terminal {
  _Clipboard(this.answer);
  final Future<ClipboardImage> Function() answer;
  @override
  Future<ClipboardImage> readClipboardImage() => answer();
  @override
  Size get size => const Size(80, 24);
  @override
  Stream<String> get input => const Stream.empty();
  @override
  Stream<Size> get resizes => const Stream.empty();
  @override
  void enter() {}
  @override
  Future<void> leave() async {}
  @override
  void write(String data) {}
}

Future<ImageRead> read(ClipboardImage image) =>
    clipboardReader(_Clipboard(() async => image))();

void main() {
  test('the four types chord sends are told from the bytes', () {
    for (final (bytes, type) in [
      (png, 'image/png'),
      (gif, 'image/gif'),
      (jpeg, 'image/jpeg'),
      (webp, 'image/webp'),
    ]) {
      expect(imageOf(bytes), (
        mediaType: type,
        data: base64.encode(bytes),
        bytes: bytes.length,
      ));
    }
  });

  test('other bytes are no image chord sends', () {
    for (final bytes in [
      ascii.encode('hello there'),
      ascii.encode('%PDF-1.7\n'),
      [0x49, 0x49, 0x2A, 0x00, 8, 0, 0, 0],
      <int>[],
    ]) {
      expect(imageOf(Uint8List.fromList(bytes)), isNull);
    }
  });

  test("the clipboard's outcomes say the original's words", () async {
    expect(
      await read(ClipboardImageRead(png)),
      isA<ImageReadDone>().having(
        (done) => done.image.mediaType,
        'type',
        'image/png',
      ),
    );
    Future<String> said(ClipboardImage image) async =>
        ((await read(image)) as ImageReadFailed).failed;
    expect(await said(const ClipboardImageNone()), 'No image in the clipboard');
    expect(
      await said(const ClipboardImageUnavailable('osascript was not found')),
      'The clipboard cannot be read here: osascript was not found',
    );
    expect(
      await said(const ClipboardImageFailed('boom')),
      'The clipboard could not be read: boom',
    );
    expect(
      await said(ClipboardImageRead(Uint8List.fromList([0x49, 0x49, 42, 0]))),
      'The clipboard holds an image chord cannot send',
    );
    final thrown = await clipboardReader(
      _Clipboard(() => Future.error(StateError('gone'))),
    )();
    expect(
      (thrown as ImageReadFailed).failed,
      'The clipboard could not be read: Bad state: gone',
    );
  });

  test(
    'a file is read by its bytes; none when missing or not an image',
    () async {
      final dir = Directory.systemTemp.createTempSync('chord-images-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final named = File('${dir.path}/really-a-png.txt')..writeAsBytesSync(png);
      final text = File('${dir.path}/fake.png')..writeAsStringSync('not one');
      expect((await readImageFile(named.path))?.mediaType, 'image/png');
      expect(await readImageFile(text.path), isNull);
      expect(await readImageFile('${dir.path}/missing.png'), isNull);
      expect(await readImageFile(dir.path), isNull);
    },
  );

  group('tester: image byte preservation', () {
    test(
      'the original one-pixel fixture survives clipboard and file reads',
      () async {
        const encoded =
            'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';
        final bytes = base64.decode(encoded);
        final expected = (
          mediaType: 'image/png',
          data: encoded,
          bytes: bytes.length,
        );
        expect(imageOf(bytes), expected);
        final result = await read(ClipboardImageRead(bytes));
        expect((result as ImageReadDone).image, expected);
        final dir = Directory.systemTemp.createTempSync('image-tester-');
        addTearDown(() => dir.deleteSync(recursive: true));
        final path = File('${dir.path}/no-extension')..writeAsBytesSync(bytes);
        expect(await readImageFile(path.path), expected);
      },
    );

    test(
      'binary payload length and base64 include every byte after the signature',
      () {
        final bytes = Uint8List.fromList([
          ...png,
          ...List.generate(256, (i) => i),
        ]);
        final image = imageOf(bytes)!;
        expect(image.bytes, bytes.length);
        expect(base64.decode(image.data), bytes);
        expect(image.mediaType, 'image/png');
      },
    );
  });
}
