// A fake `codex app-server` whose answer to `initialize` never fits: with
// `oversize` (its first argument after `app-server`) one line longer than
// the reader's cap, with `growing` one line that grows with no end until
// it is stopped. It records its pid to the file its second argument names.
// It needs dart:io alone, so it runs from any directory.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

void main(List<String> args) {
  final rest = args.isNotEmpty && args.first == 'app-server'
      ? args.sublist(1)
      : args;
  final [mode, record] = rest;
  File(record).writeAsStringSync('${jsonEncode({'pid': pid})}\n');
  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    File(record).writeAsStringSync('$line\n', mode: FileMode.append);
    final request = jsonDecode(line) as Map<String, Object?>;
    if (request['method'] != 'initialize') return;
    final id = request['id'];
    if (mode == 'oversize') {
      stdout.writeln(
        jsonEncode({
          'id': id,
          'result': {'userAgent': 'x' * (256 * 1024)},
        }),
      );
      return;
    }
    stdout.write('{"id":$id,"result":{"userAgent":"');
    Timer.periodic(const Duration(milliseconds: 5), (_) {
      stdout.write('x' * (16 * 1024));
    });
  });
}
