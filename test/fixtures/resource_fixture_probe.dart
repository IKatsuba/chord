/// Prints which resource source a chord built as this one would use: the
/// compile-time flag's mode, and the fixture case the environment chooses.
library;

import 'dart:io';

import 'package:chord/platform/resource_fixture.dart';

void main() {
  stdout.writeln(
    '${resourceSourceMode(resourceFixtureFlag).name} '
    '${resourceFixtureCase(Platform.environment['CHORD_FAKE_RESOURCE_CASE'])}',
  );
}
