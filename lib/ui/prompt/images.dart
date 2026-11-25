/// Images in the prompt, from the original's `ui/prompt/images.ts`: the
/// `[Image #N]` a pasted image puts at the cursor, the paths a draft names
/// that are taken as images, and which images a prompt sends. An image goes
/// with the prompt only while its placeholder is in the text, so deleting
/// the placeholder drops it. Cursors are offsets into the draft, as the
/// port's prompt keeps them.
library;

import 'package:characters/characters.dart';

import '../../images.dart';

export '../../images.dart' show PastedImage;
import '../../session/session.dart' show PromptImage;
import 'prompt.dart' show Cursor;

/// [image] held as image [id].
PastedImage pasted(ImageData image, int id) =>
    (id: id, mediaType: image.mediaType, data: image.data, bytes: image.bytes);

/// What stands for image [id] in the text, as Claude Code writes it.
String placeholder(int id) => '[Image #$id]';

// A number too long for an int names no image held: tryParse gives none.
final _placeholder = RegExp(r'\[Image #(\d+)\]');

/// [start, end), grapheme offsets in [text], widened to take whole every
/// placeholder of an image held that it cuts into: vim's deletions, as
/// backspace and ctrl+w take a placeholder whole.
(int, int) wholePlaceholders(
  String text,
  int start,
  int end,
  List<PastedImage> images,
) {
  var from = start, to = end;
  for (final match in _placeholder.allMatches(text)) {
    final id = int.tryParse(match.group(1)!);
    if (!images.any((image) => image.id == id)) continue;
    final first = text.substring(0, match.start).characters.length;
    final last = first + match.group(0)!.length;
    if (to <= first || from >= last) continue;
    if (first < from) from = first;
    if (last > to) to = last;
  }
  return (from, to);
}

/// The images whose placeholders are in [text], in the order they appear,
/// each once.
List<PastedImage> imagesIn(String text, List<PastedImage> images) {
  final found = <PastedImage>[];
  for (final match in _placeholder.allMatches(text)) {
    final id = int.tryParse(match.group(1)!);
    final image = images.where((image) => image.id == id).firstOrNull;
    if (image != null && !found.contains(image)) found.add(image);
  }
  return found;
}

/// The images [text] sends, as a prompt takes them.
List<PromptImage> attachmentsOf(String text, List<PastedImage> images) => [
  for (final image in imagesIn(text, images))
    (mimeType: image.mediaType, data: image.data),
];

/// The draft with image [id]'s placeholder at [cursor], and the cursor
/// after it. It stands apart from the words round it, as a pasted word
/// would: a space before it after one, and a space after it.
({String text, Cursor cursor}) insertImage(
  String draft,
  Cursor cursor,
  int id,
) {
  final before = draft.substring(0, cursor);
  final after = draft.substring(cursor);
  final line = before.substring(before.lastIndexOf('\n') + 1);
  final written =
      '${RegExp(r'\S$').hasMatch(line) ? ' ' : ''}${placeholder(id)}'
      '${after.startsWith(' ') ? '' : ' '}';
  return (text: before + written + after, cursor: cursor + written.length);
}

/// What a change to the draft put in, and where it ends in the new draft,
/// when it is one piece longer than a key, as a paste is; none for typing
/// or deleting.
({String text, int end})? pastedText(String before, String after) {
  if (after.length - before.length < 2) return null;
  var start = 0;
  while (start < before.length && before[start] == after[start]) {
    start++;
  }
  var end = 0;
  while (end < before.length - start &&
      before[before.length - 1 - end] == after[after.length - 1 - end]) {
    end++;
  }
  return (
    text: after.substring(start, after.length - end),
    end: after.length - end,
  );
}

/// A deletion that cut into the placeholder of an image the draft holds,
/// widened to the whole placeholder, with the cursor where it stood; none
/// for any other change. A backspace after `]` or a delete before `[` takes
/// the image, as in Claude Code, rather than leaving half a label that
/// stands for nothing.
({String text, Cursor cursor})? cutPlaceholder(
  String before,
  String after,
  List<PastedImage> images,
) {
  if (after.length >= before.length) return null;
  var start = 0;
  while (start < after.length && before[start] == after[start]) {
    start++;
  }
  var end = before.length;
  final shift = after.length - before.length;
  // The common end stops where the common start does, or a cut ending in
  // the character it began after looks one short.
  while (end + shift > start && before[end - 1] == after[end + shift - 1]) {
    end--;
  }
  // Anything but a stretch taken out of the old draft is not a deletion.
  if (before.length - (end - start) != after.length) return null;
  var from = start, to = end;
  for (final found in _placeholder.allMatches(before)) {
    final first = found.start, last = found.end;
    final id = int.tryParse(found.group(1)!);
    final held = images.any((image) => image.id == id);
    final cut = first < end && start < last && (first < start || end < last);
    if (held && cut) {
      if (first < from) from = first;
      if (last > to) to = last;
    }
  }
  if (from == start && to == end) return null;
  return (text: before.substring(0, from) + before.substring(to), cursor: from);
}

final _placeholderSpace = RegExp(r'\[Image #(\d+)\] $');

/// How much of [before], the draft up to the cursor, is the placeholder of
/// an image the draft holds with the space after it, as straight after a
/// paste; 0 otherwise. ctrl+w takes that whole.
int placeholderBefore(String before, List<PastedImage> images) {
  final found = _placeholderSpace.firstMatch(before);
  if (found == null) return 0;
  final id = int.tryParse(found.group(1)!);
  return images.any((image) => image.id == id) ? found.group(0)!.length : 0;
}

final _imageFile = RegExp(r'\.(png|jpe?g|gif|webp)$', caseSensitive: false);

/// Paths as a terminal puts a dropped file in: `/abs`, `~/…` or `file://…`,
/// whole, quoted, or with its spaces escaped. Only those count, so a
/// relative path in a sentence stays a path for the agent to open.
final _path = RegExp(
  r'''(?<=^|\s)(?:'[^'\n]+'|"[^"\n]+"|(?:~/|/|file://)(?:\\.|\S)+)''',
);

/// The file [written] names, when it is an image's name; none otherwise.
String? imagePath(String written, [String? home]) {
  var path = written;
  if (RegExp(r'''^(['"]).*\1$''').hasMatch(path)) {
    path = path.substring(1, path.length - 1);
  } else {
    path = path.replaceAllMapped(RegExp(r'\\(.)'), (m) => m.group(1)!);
  }
  if (path.startsWith('file://')) {
    try {
      path = Uri.decodeComponent(Uri.parse(path).path);
    } catch (_) {
      return null;
    }
  } else if (path.startsWith('~/')) {
    if (home == null) return null;
    path = '$home${path.substring(1)}';
  }
  return path.startsWith('/') && _imageFile.hasMatch(path) ? path : null;
}

final _sentenceEnd = RegExp(r'(?<!\\)[.,;:!?)]+$');

/// The paths [text] writes, and where each starts; the stop or comma a
/// sentence puts after one is the sentence's.
List<({String written, int index})> _pathsIn(String text) => [
  for (final found in _path.allMatches(text))
    (
      written: found.group(0)!.replaceFirst(_sentenceEnd, ''),
      index: found.start,
    ),
];

/// Whether [text] names an image file in a form [takeImagePaths] reads.
bool namesImage(String text, [String? home]) => imagePathCount(text, home) > 0;

/// How many image files [text] names, at most: the numbers
/// [takeImagePaths] may give them before it knows which files are there.
int imagePathCount(String text, [String? home]) => _pathsIn(
  text,
).where((path) => imagePath(path.written, home) != null).length;

/// [text] with each image file it names in a path's place, as
/// `[Image #N]`, numbered from [next], and the images read. A path to no
/// file, or to one that is not an image, stays as it was written.
Future<({String text, List<PastedImage> images})> takeImagePaths(
  String text,
  int next,
  ImageFileReader read, [
  String? home,
]) async {
  final images = <PastedImage>[];
  final taken = StringBuffer();
  var from = 0;
  for (final (:written, :index) in _pathsIn(text)) {
    final path = imagePath(written, home);
    final image = path == null ? null : await read(path);
    if (image == null) continue;
    final id = next + images.length;
    images.add(pasted(image, id));
    taken
      ..write(text.substring(from, index))
      ..write(placeholder(id));
    from = index + written.length;
  }
  taken.write(text.substring(from));
  return (text: taken.toString(), images: images);
}
