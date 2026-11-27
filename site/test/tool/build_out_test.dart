import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

// CHD-638: `build --out` only ever fills a new or empty folder, so a
// mistyped one can never replace the checkout or anything else.
void main() {
  Future<ProcessResult> build(String out) => Process.run(
    Platform.resolvedExecutable,
    ['run', 'tool/build.dart', 'build', '--out=$out'],
  );

  test('an empty --out is refused', () async {
    final run = await build('');
    expect(run.exitCode, 64);
    expect(run.stderr, contains('--out needs a folder'));
  });

  test('a folder with files in it is refused and left as it was', () async {
    final out = Directory.systemTemp.createTempSync('chord_site_out_');
    addTearDown(() => out.deleteSync(recursive: true));
    final kept = File(p.join(out.path, 'kept.txt'))..writeAsStringSync('mine');
    final run = await build(out.path);
    expect(run.exitCode, 64);
    expect(run.stderr, contains('is not empty'));
    expect(kept.readAsStringSync(), 'mine');
    expect(out.listSync(), hasLength(1));
  });
}
