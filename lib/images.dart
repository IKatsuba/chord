/// The images a prompt takes, from the original's `images.ts`: the one on
/// the system clipboard, read through the framework's terminal service, and
/// a file a path names. What the bytes are is `mime`'s word from the bytes,
/// not the file name's.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:chord_tui/chord_tui.dart';
import 'package:mime/mime.dart';

/// The image types chord sends: the ones Claude and its kin read.
const imageTypes = ['image/png', 'image/jpeg', 'image/gif', 'image/webp'];

/// An image as it goes to the agent, with its size for the person:
/// [mediaType], [data] as base64, as a prompt's image block takes it, and
/// how many [bytes] it is.
typedef ImageData = ({String mediaType, String data, int bytes});

/// An image the draft holds, by the number its placeholder shows.
typedef PastedImage = ({int id, String mediaType, String data, int bytes});

/// What reading the clipboard came to: an image, or a sentence why not.
sealed class ImageRead {
  const ImageRead();
}

/// The clipboard's image.
final class ImageReadDone extends ImageRead {
  const ImageReadDone(this.image);
  final ImageData image;
}

/// Why there is no image, in the original's words.
final class ImageReadFailed extends ImageRead {
  const ImageReadFailed(this.failed);
  final String failed;
}

/// Reads the clipboard's image.
typedef ClipboardReader = Future<ImageRead> Function();

/// Reads the image a path names; none when it is not one.
typedef ImageFileReader = Future<ImageData?> Function(String path);

/// [bytes] as an image chord sends, or none when they are not one.
ImageData? imageOf(Uint8List bytes) {
  final type = lookupMimeType('', headerBytes: bytes);
  if (type == null || !imageTypes.contains(type)) return null;
  return (mediaType: type, data: base64.encode(bytes), bytes: bytes.length);
}

/// The clipboard's image as [terminal] reads it, in the original's words.
ClipboardReader clipboardReader(Terminal terminal) => () async {
  try {
    return switch (await terminal.readClipboardImage()) {
      ClipboardImageUnavailable(:final reason) => ImageReadFailed(
        'The clipboard cannot be read here: $reason',
      ),
      ClipboardImageNone() => const ImageReadFailed(
        'No image in the clipboard',
      ),
      ClipboardImageFailed(:final reason) => ImageReadFailed(
        'The clipboard could not be read: $reason',
      ),
      ClipboardImageRead(:final bytes) => switch (imageOf(bytes)) {
        final image? => ImageReadDone(image),
        null => const ImageReadFailed(
          'The clipboard holds an image chord cannot send',
        ),
      },
    };
  } catch (error) {
    return ImageReadFailed('The clipboard could not be read: $error');
  }
};

/// The image file at [path]; none when there is none or it is something
/// else.
Future<ImageData?> readImageFile(String path) async {
  try {
    return imageOf(await File(path).readAsBytes());
  } catch (_) {
    return null;
  }
}
