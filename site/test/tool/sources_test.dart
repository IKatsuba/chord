import 'dart:io';

import 'package:chord_site/sources.g.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/sources.dart';
import '../../web/gallery.dart';

void main() {
  final root = p.dirname(Directory.current.path);
  final framework = p.join(root, 'packages', 'chord_tui');

  test('lib/sources.g.dart is what the files give now', () {
    expect(
      File('lib/sources.g.dart').readAsStringSync(),
      generateSources(root),
      reason: 'run `dart run tool/sources.dart`',
    );
  });

  test('it holds README\'s example and every gallery example', () {
    expect(sourceExamples, [
      'main',
      for (final e in siteGallery.entries) e.name,
    ]);
  });

  test('each source is its file, character for character', () {
    for (final name in sourceExamples) {
      expect(
        exampleSources[name],
        File(p.join(framework, 'example', '$name.dart')).readAsStringSync(),
        reason: name,
      );
    }
    expect(
      testingSource,
      startsWith("import 'package:chord_tui/chord_tui.dart';"),
    );
    expect(
      File(p.join(framework, 'README.md')).readAsStringSync(),
      contains('```dart\n$testingSource```'),
    );
  });

  test('a README without the Testing block is refused', () {
    expect(() => testingExample('# x\n'), throwsStateError);
    expect(
      () => testingExample('# x\n## Testing\n\nno code\n'),
      throwsStateError,
    );
  });
}
