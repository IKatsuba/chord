// A fake `claude` for the usage reader's wire: it records its argv, the
// environment the SDK sets or removes, and each stdin line, to the file
// CHORD_FAKE_USAGE_RECORD names, and answers the two control requests as
// CHORD_FAKE_USAGE_MODE says: `normal`, `error` (an error answer), `garbage`
// (a line that is not JSON), `exit` (gone before the usage answer), `flood`
// (short lines past the output bound) or `oversize` (one long line past
// it). It needs dart:io alone, so it runs from any directory.
import 'dart:convert';
import 'dart:io';

void main(List<String> argv) {
  final env = Platform.environment;
  final record = File(env['CHORD_FAKE_USAGE_RECORD']!);
  final mode = env['CHORD_FAKE_USAGE_MODE'] ?? 'normal';
  record.writeAsStringSync(
    '${jsonEncode({
      'argv': argv,
      'env': {for (final MapEntry(:key, :value) in env.entries)
        if (RegExp('CLAUDE|SDK|NODE_OPTIONS|DEBUG', caseSensitive: false).hasMatch(key)) key: value},
    })}\n',
  );
  void answer(Object? id, Object? response, {String subtype = 'success'}) {
    stdout.writeln(
      jsonEncode({
        'type': 'control_response',
        'response': {
          'subtype': subtype,
          'request_id': id,
          if (subtype == 'success') 'response': response else 'error': 'no',
        },
      }),
    );
  }

  stdin.transform(utf8.decoder).transform(const LineSplitter()).listen((line) {
    record.writeAsStringSync('$line\n', mode: FileMode.append);
    final message = jsonDecode(line) as Map<String, Object?>;
    final request = message['request'] as Map<String, Object?>;
    final id = message['request_id'];
    if (request['subtype'] == 'initialize') {
      // Lines that are not control answers come first, as the SDK skips
      // them.
      stdout.writeln(jsonEncode({'type': 'system', 'subtype': 'init'}));
      return answer(id, {'commands': <Object?>[]});
    }
    switch (mode) {
      case 'error':
        answer(id, null, subtype: 'error');
      case 'garbage':
        stdout.writeln('not json');
      case 'exit':
        exit(0);
      case 'flood':
        for (var i = 0; i < 40000; i++) {
          stdout.writeln('{"type":"x"}');
        }
      case 'oversize':
        stdout.writeln('{"type":"x","pad":"${'x' * (300 * 1024)}"}');
      default:
        answer(id, {
          'rate_limits_available': true,
          'rate_limits': {
            'five_hour': {'utilization': 1, 'resets_at': null},
          },
        });
    }
  }, onDone: () => exit(0));
}
