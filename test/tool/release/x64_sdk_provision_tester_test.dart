import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/runner.dart';
import '../../../tool/release/x64_sdk.dart';
import 'fixtures/recording_runner.dart';

Matcher refuses(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

final class _RenameRace extends IOOverrides {
  _RenameRace(this.appear);
  final void Function(String destination) appear;
  var renames = 0;

  @override
  Directory createDirectory(String path) {
    final directory = super.createDirectory(path);
    if (p.basename(path) != 'dart-sdk' ||
        !p.basename(p.dirname(path)).startsWith('macos-x64.partial-')) {
      return directory;
    }
    return _RaceDirectory(directory, (destination) {
      renames++;
      appear(destination);
      throw FileSystemException('simulated rename race', destination);
    });
  }
}

class _RaceDirectory implements Directory {
  _RaceDirectory(this.directory, this.onRename);
  final Directory directory;
  final Directory Function(String) onRename;

  @override
  String get path => directory.path;

  @override
  Directory renameSync(String newPath) => onRename(newPath);

  @override
  void createSync({bool recursive = false}) =>
      directory.createSync(recursive: recursive);

  @override
  bool existsSync() => directory.existsSync();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('tester: x64 SDK provisioning boundaries', () {
    late Directory temp;
    const stable = '3.13.5';
    final zip = utf8.encode('recorded archive bytes');
    late List<Uri> fetched;
    late List<String> output;
    late List<String> staged;
    late String version;
    var omitDart = false;

    String folder() => sdkFolder(temp.path, version);
    List<String> siblings() {
      final parent = Directory(p.dirname(folder()));
      if (!parent.existsSync()) return [];
      return parent.listSync().map((e) => p.basename(e.path)).toList()..sort();
    }

    setUp(() {
      temp = Directory.systemTemp.createTempSync('sdk_provision_tester');
      version = stable;
      fetched = [];
      output = [];
      staged = [];
      omitDart = false;
    });
    tearDown(() => temp.deleteSync(recursive: true));

    Future<List<int>> fetch(Uri url) async {
      fetched.add(url);
      if (url.toString() == sdkChecksumUrl(version)) {
        return utf8.encode('${sha256.convert(zip)} *$sdkZipName\r\n');
      }
      expect(url.toString(), sdkZipUrl(version));
      return zip;
    }

    RecordingRunner machine() => RecordingRunner((argv) {
      if (argv case ['ditto', '-x', '-k', final archive, final destination]) {
        staged.add(destination);
        expect(File(archive).readAsBytesSync(), zip);
        expect(Directory(folder()).existsSync(), isFalse);
        Directory(p.join(destination, 'dart-sdk')).createSync();
        if (!omitDart) {
          File(sdkDart(p.join(destination, 'dart-sdk')))
            ..createSync(recursive: true)
            ..writeAsStringSync('fresh');
        }
        return const Ran(0);
      }
      if (argv case ['arch', '-x86_64', final dart, '--version']) {
        if (!File(dart).existsSync()) {
          return const Ran(127, stderr: 'missing bin/dart');
        }
        return Ran(0, stderr: 'Dart SDK version: $version (channel)\n');
      }
      throw StateError('unexpected command $argv');
    });

    Future<String> provide(RecordingRunner runner, {Fetch? fetching}) =>
        provideX64Sdk(
          runner: runner,
          version: version,
          cache: temp.path,
          fetch: fetching ?? fetch,
          out: output.add,
        );

    for (final channel in ['beta', 'dev']) {
      test(
        '$channel is fetched once and then reused without a fetch',
        () async {
          version = '3.14.0-123.4.$channel';
          final first = machine();
          expect(await provide(first), sdkDart(folder()));
          expect(fetched.map((u) => u.toString()), [
            sdkChecksumUrl(version),
            sdkZipUrl(version),
          ]);
          expect(fetched.every((u) => u.pathSegments[2] == channel), isTrue);
          expect(siblings(), ['macos-x64']);
          final second = machine();
          expect(
            await provide(second, fetching: (_) => throw StateError('fetched')),
            sdkDart(folder()),
          );
          expect(second.argvs, [
            ['arch', '-x86_64', sdkDart(folder()), '--version'],
          ]);
        },
      );
    }

    test(
      'a zip without bin/dart is refused and its staging is removed',
      () async {
        omitDart = true;
        final runner = machine();
        await expectLater(provide(runner), refuses('missing bin/dart'));
        expect(runner.calls, hasLength(2));
        expect(Directory(folder()).existsSync(), isFalse);
        expect(siblings(), isEmpty);
      },
    );

    test('a malformed checksum stops before zip fetch or extraction', () async {
      final runner = machine();
      await expectLater(
        provide(
          runner,
          fetching: (url) async {
            fetched.add(url);
            return utf8.encode('not a checksum');
          },
        ),
        refuses('checksum says no sha256'),
      );
      expect(fetched, [Uri.parse(sdkChecksumUrl(version))]);
      expect(runner.calls, isEmpty);
      expect(siblings(), isEmpty);
    });

    test(
      'a failed zip fetch preserves foreign staging byte for byte',
      () async {
        final marker = File(
          p.join(p.dirname(folder()), 'macos-x64.partial-leftover', 'marker'),
        )..createSync(recursive: true);
        marker.writeAsStringSync('another run owns this');
        final runner = machine();
        await expectLater(
          provide(
            runner,
            fetching: (url) async {
              if (url.toString() == sdkZipUrl(version)) {
                throw const SocketException('recorded interruption');
              }
              return fetch(url);
            },
          ),
          refuses('recorded interruption'),
        );
        expect(marker.readAsStringSync(), 'another run owns this');
        expect(siblings(), ['macos-x64.partial-leftover']);
        expect(runner.calls, isEmpty);
      },
    );

    test(
      'a failed rename with no appeared target refuses and cleans staging',
      () async {
        final race = _RenameRace((_) {});
        await IOOverrides.runWithIOOverrides(() async {
          await expectLater(provide(machine()), refuses('cannot move'));
        }, race);
        expect(race.renames, 1);
        expect(siblings(), isEmpty);
      },
    );

    for (final valid in [true, false]) {
      test('a target appearing during failed rename is checked '
          'and ${valid ? 'taken' : 'refused'}', () async {
        final race = _RenameRace((destination) {
          File(sdkDart(destination))
            ..createSync(recursive: true)
            ..writeAsStringSync('foreign');
        });
        final runner = RecordingRunner((argv) {
          if (argv case ['arch', '-x86_64', final dart, '--version']) {
            if (dart == sdkDart(folder())) {
              return Ran(
                0,
                stdout: 'Dart SDK version: ${valid ? version : '3.12.0'}\n',
              );
            }
          }
          return machine().answer!(argv);
        });
        await IOOverrides.runWithIOOverrides(() async {
          if (valid) {
            expect(await provide(runner), sdkDart(folder()));
          } else {
            await expectLater(provide(runner), refuses('not $version'));
          }
        }, race);
        expect(race.renames, 1);
        expect(File(sdkDart(folder())).readAsStringSync(), 'foreign');
        expect(runner.argvs.last, [
          'arch',
          '-x86_64',
          sdkDart(folder()),
          '--version',
        ]);
        expect(siblings(), ['macos-x64']);
      });
    }
  });
}
