import 'dart:convert';
import 'dart:io';

import 'package:chord/session/record.dart';
import 'package:chord/session/state_dir.dart';
import 'package:path/path.dart' as p;

/// AOT probe against the port's production dependency resolution.
Future<void> main(List<String> args) async {
  if (args.contains('--missing-home')) {
    try {
      chordStateDir();
      throw StateError('Expected HOME/XDG requirement');
    } on StateError catch (error) {
      if (!error.message.toString().contains('HOME or XDG_STATE_HOME')) rethrow;
      print('PASS missing HOME/XDG requirement');
      return;
    }
  }
  final state = chordStateDir();
  final override = Platform.environment['XDG_STATE_HOME'];
  final expected = override != null && override.isNotEmpty
      ? p.join(override, 'chord')
      : p.join(Platform.environment['HOME']!, '.local', 'state', 'chord');
  if (state != expected) throw StateError('XDG state mismatch');
  print('PASS xdg_directories 1.1.0 stateHome');
  final names = {
    for (var i = 0; i < 10000; i++) p.basename(newRecordPath(state)),
  };
  final v4 = RegExp(
    r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\.jsonl$',
  );
  if (names.length != 10000 || names.any((name) => !v4.hasMatch(name))) {
    throw StateError('UUID v4');
  }
  print('PASS uuid 4.6.0: 10000 distinct canonical v4 basenames');
  final dir = await Directory.systemTemp.createTemp('chord-record-probe-');
  try {
    final file = File(p.join(dir.path, 'record.jsonl'));
    final first = encodeRecord({'type': 'opened', 'at': 1});
    final next = encodeRecord({'type': 'future', 'text': '界 🐈'});
    await file.writeAsString(first, mode: FileMode.append, flush: true);
    await file.writeAsString(next, mode: FileMode.append, flush: true);
    if (await file.readAsString() != '$first$next') {
      throw StateError('Append prefix');
    }
    final sink = file.openWrite(mode: FileMode.append);
    sink.add(utf8.encode(encodeRecord({'type': 'opened', 'at': 2})));
    await sink.flush();
    await sink.close();
    if ((await recordLines(file.path).toList()).length != 3) {
      throw StateError('UTF-8 stream');
    }
    print('PASS SDK append, preserved prefix, UTF-8 stream, flush and close');
  } finally {
    await dir.delete(recursive: true);
  }
  print('PASS owned probe directory removed');
}
