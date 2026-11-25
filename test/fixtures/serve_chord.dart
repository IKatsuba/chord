// chord's server with a fixed window, for the compiled test: one JSON line
// on stdout, {url, person, task}, the tokens of a main session and a task;
// it closes and exits when stdin ends.
import 'dart:convert';
import 'dart:io';

import 'package:chord/server/server.dart';
import 'package:chord/server/tools.dart';

import '../server/fake_window.dart';

Future<void> main() async {
  final server = await serveChord();
  final window = FakeWindow()..closed = const Ended('scan');
  final person = server.admit(
    Caller(role: Role.person, key: 0, window: window),
  );
  final task = server.admit(
    Caller(role: Role.child, key: 0, task: 't1', window: window),
  );
  stdout.writeln(
    jsonEncode({'url': server.url, 'person': person.token, 'task': task.token}),
  );
  await stdout.flush();
  await stdin.drain<void>();
  await server.close();
  exit(0);
}
