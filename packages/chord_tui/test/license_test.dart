import 'dart:io';

import 'package:test/test.dart';

void main() {
  test("the package keeps its own LICENSE, which pub reads", () {
    final licence = File('LICENSE');
    expect(licence.existsSync(), isTrue);
    expect(
      licence.readAsStringSync(),
      contains('Permission is hereby granted'),
    );
  });

  // Outside the repository, as an exported package, there is no root
  // LICENSE to compare with.
  final root = File('../../LICENSE');
  test(
    "the package's LICENSE is the repository's, byte for byte",
    () {
      // pub reads the licence from the package's own folder, so it keeps a
      // copy of the root one.
      expect(File('LICENSE').readAsBytesSync(), root.readAsBytesSync());
    },
    skip: root.existsSync()
        ? false
        : 'no repository LICENSE beside the package to compare with',
  );
}
