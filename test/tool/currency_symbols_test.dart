@TestOn('posix')
library;

import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../tool/currency_symbols.dart';

void main() {
  late Directory port;
  setUp(() {
    port = Directory.systemTemp.createTempSync('currency_symbols_test');
    addTearDown(() => port.deleteSync(recursive: true));
  });

  String table() =>
      p.join(port.path, 'lib/ui/transcript/currency_symbols.dart');
  String probe() =>
      p.join(port.path, 'test/fixtures/currency/original_probe.json');

  /// A node that runs the given script by printing [probe] as JSON.
  String node(Map<String, Object?> probe) {
    final file = File(p.join(port.path, 'node'))
      ..writeAsStringSync(
        '#!/bin/sh\n'
        'case "\$1" in *.mjs) ;; *) exit 9 ;; esac\n'
        "printf '%s' '${jsonEncode(probe)}'\n",
      );
    Process.runSync('chmod', ['+x', file.path]);
    return file.path;
  }

  test("writes each currency's sign and the probe from node's Intl", () async {
    Directory(
      p.join(port.path, 'lib/ui/transcript'),
    ).createSync(recursive: true);
    final code = await generateSigns(
      port: port.path,
      node: node({
        'icu': pinnedIcu,
        'costs': {
          'USD': [r'$3.00', r'$0.0300'],
          'XAF': ['FCFA 3.00', 'FCFA 0.0300'],
        },
      }),
    );
    expect(code, 0);
    final written = File(table()).readAsStringSync();
    expect(written, contains("from Node's Intl, en-US, ICU\n// $pinnedIcu"));
    expect(written, contains(r"  'USD': '\$',"));
    expect(written, contains("  'XAF': 'FCFA ',"));
    expect(jsonDecode(File(probe()).readAsStringSync())['icu'], pinnedIcu);
  });

  test('another ICU is refused, nothing written', () async {
    final code = await generateSigns(
      port: port.path,
      node: node({'icu': '77.1', 'costs': <String, Object?>{}}),
    );
    expect(code, 1);
    expect(File(table()).existsSync(), isFalse);
    expect(File(probe()).existsSync(), isFalse);
  });
}
