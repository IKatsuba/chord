import 'dart:io';

import 'package:chord/platform/process.dart';

/// Prints where `resolveProgram` finds `<program>` for an agent in `<cwd>`
/// with `PATH` set to `<path>`, from whatever directory this runs in, or
/// `cannot start` when it finds none. A test runs it in its own process,
/// since the current directory is the whole process's.
void main(List<String> args) {
  final [program, cwd, path] = args;
  try {
    stdout.writeln(resolveProgram(program, cwd: cwd, env: {'PATH': path}));
  } on CannotStart {
    stdout.writeln('cannot start');
  }
}
