import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:test/test.dart';

import '../chord_stub.dart';
import '../options.dart' as options;
import '../rpc.dart';
import '../sessions.dart';
import '../turn.dart';
import 'chord_tools.dart';
import 'settings.dart';

final class _Recorded {
  _Recorded([void Function(Map update)? onUpdate]) {
    connection = Connection.serve(
      input.stream,
      (bytes) {
        final message = jsonDecode(utf8.decode(bytes)) as Map;
        final update = (message['params'] as Map)['update'] as Map;
        updates.add(update);
        onUpdate?.call(update);
      },
      () async {},
      requests: {},
      notifications: {},
    );
  }

  final input = StreamController<List<int>>();
  final updates = <Map>[];
  late final Connection connection;

  Future<void> close() async {
    await input.close();
    await connection.closed;
  }
}

void main() {
  group('tester: CTUI-147 linked settings fixture cleanup', () {
    setUp(() => options.args = ['--step-ms', '0']);
    for (final preexisting in [false, true]) {
      for (final reject in [false, true]) {
        test(
          'existing directory $preexisting and MCP rejection $reject clean the owned link and target',
          () async {
            final root = Directory.systemTemp.createTempSync(
              'chord-linked-test-',
            );
            addTearDown(() => root.deleteSync(recursive: true));
            final directory = Directory('${root.path}/.chord');
            final link = Link('${directory.path}/settings.json');
            final sentinel = File('${directory.path}/keep.txt');
            if (preexisting) {
              directory.createSync();
              sentinel.writeAsStringSync('keep');
            }
            final server = await ChordStub.start(
              tools: reject ? [] : ['settings'],
            );
            addTearDown(server.close);
            String? target;
            final recorded = _Recorded((update) {
              if (update['sessionUpdate'] == 'tool_call') {
                target = link.targetSync();
                expect(
                  jsonDecode(File(target!).readAsStringSync()),
                  linkTarget,
                );
              }
            });
            addTearDown(recorded.close);
            const id = 'tester-linked';
            cwds[id] = root.path;
            mcpServers[id] = [
              {
                'name': 'chord',
                'type': 'http',
                'url': server.url,
                'headers': [],
              },
            ];
            addTearDown(() {
              cwds.remove(id);
              mcpServers.remove(id);
            });
            final result = settingsPlays['settingsreadlinked']!(
              Turn(recorded.connection.client, id, Aborter().signal),
            );
            if (reject) {
              await expectLater(result, throwsA(isA<McpFailure>()));
            } else {
              expect(await result, 'end_turn');
            }
            expect(target, isNotNull);
            expect(
              FileSystemEntity.typeSync(link.path, followLinks: false),
              FileSystemEntityType.notFound,
            );
            expect(File(target!).existsSync(), isFalse);
            expect(File(target!).parent.existsSync(), isFalse);
            expect(directory.existsSync(), preexisting);
            if (preexisting) expect(sentinel.readAsStringSync(), 'keep');
          },
        );
      }
    }

    test(
      'an existing project settings file is left byte for byte intact',
      () async {
        final root = Directory.systemTemp.createTempSync(
          'chord-existing-settings-',
        );
        addTearDown(() => root.deleteSync(recursive: true));
        final directory = Directory('${root.path}/.chord')..createSync();
        final file = File('${directory.path}/settings.json')
          ..writeAsStringSync('{"theme":"dark","unknown":"keep"}\n');
        final before = file.readAsBytesSync();
        final server = await ChordStub.start(tools: []);
        addTearDown(server.close);
        final recorded = _Recorded();
        addTearDown(recorded.close);
        const id = 'tester-existing';
        cwds[id] = root.path;
        mcpServers[id] = [
          {'name': 'chord', 'type': 'http', 'url': server.url, 'headers': []},
        ];
        addTearDown(() {
          cwds.remove(id);
          mcpServers.remove(id);
        });
        expect(
          await settingsPlays['settingsreadlinked']!(
            Turn(recorded.connection.client, id, Aborter().signal),
          ),
          'end_turn',
        );
        expect(file.readAsBytesSync(), before);
        expect(recorded.updates, hasLength(1));
        expect(recorded.updates.single['content'], {
          'type': 'text',
          'text': 'No link planted.',
        });
      },
    );
  });
}
