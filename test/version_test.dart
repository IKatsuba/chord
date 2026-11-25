import 'dart:io';

import 'package:chord/version.dart';
import 'package:test/test.dart';

String _versionOf(String pubspec) {
  final lines = File(pubspec).readAsLinesSync();
  final line = lines.firstWhere((line) => line.startsWith('version:'));
  return line.substring('version:'.length).trim();
}

void main() {
  test('the version is the one pubspec.yaml gives', () {
    expect(_versionOf('pubspec.yaml'), version);
  });

  test("the framework's pubspec.yaml carries the port's version", () {
    const framework = 'packages/chord_tui/pubspec.yaml';
    expect(_versionOf(framework), _versionOf('pubspec.yaml'));
    expect(_versionOf(framework), version);
  });
}
