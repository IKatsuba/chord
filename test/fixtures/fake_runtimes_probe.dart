/// Prints whether a chord built as this one routes every runtime to the
/// fake: the compile-time flag alone, whatever the environment says.
library;

import 'dart:io';

import 'package:chord/session/place.dart';

void main() => stdout.writeln('fake runtimes $fakeRuntimesFlag');
