import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

import '../../../tool/release/runner.dart';
import '../../../tool/release/x64_sdk.dart';
import 'fixtures/recording_runner.dart';

Matcher dies(String text) => throwsA(
  isA<ReleaseError>().having((e) => e.message, 'message', contains(text)),
);

const hash = '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef';

void main() {
  group('the channel', () {
    test('of a plain release is stable', () {
      expect(channelOf('3.13.5'), 'stable');
    });

    test('of a prerelease is the one it names', () {
      expect(channelOf('3.14.0-123.1.beta'), 'beta');
      expect(channelOf('3.14.0-200.0.dev'), 'dev');
    });

    test('of any other version is refused', () {
      for (final version in ['3.14.0-edge', '3.14.0-1.0.main', 'main', '']) {
        expect(
          () => channelOf(version),
          dies('is of no channel the Dart archive publishes'),
          reason: version,
        );
      }
    });
  });

  group('the archive', () {
    test('serves the zip by channel and version', () {
      expect(
        sdkZipUrl('3.13.5'),
        'https://storage.googleapis.com/dart-archive/channels/stable/release/'
        '3.13.5/sdk/dartsdk-macos-x64-release.zip',
      );
      expect(
        sdkZipUrl('3.14.0-200.0.dev'),
        'https://storage.googleapis.com/dart-archive/channels/dev/release/'
        '3.14.0-200.0.dev/sdk/dartsdk-macos-x64-release.zip',
      );
    });

    test('serves its checksum beside it', () {
      expect(
        sdkChecksumUrl('3.14.0-123.1.beta'),
        'https://storage.googleapis.com/dart-archive/channels/beta/release/'
        '3.14.0-123.1.beta/sdk/dartsdk-macos-x64-release.zip.sha256sum',
      );
    });
  });

  group('the cache', () {
    test(r'is $XDG_CACHE_HOME when set', () {
      expect(userCache({'XDG_CACHE_HOME': '/xdg'}, '/home/x'), '/xdg');
    });

    test('is ~/Library/Caches otherwise', () {
      expect(userCache({}, '/home/x'), '/home/x/Library/Caches');
      expect(
        userCache({'XDG_CACHE_HOME': ''}, '/home/x'),
        '/home/x/Library/Caches',
      );
    });

    test('keeps each version in its own folder', () {
      final folder = sdkFolder('/cache', '3.13.5');
      expect(folder, '/cache/chord-release/dart-sdk/3.13.5/macos-x64');
      expect(sdkDart(folder), '$folder/bin/dart');
    });
  });

  group('the checksum', () {
    test("is read from sha256sum's binary and text lines", () {
      expect(checksumOf('$hash *dartsdk-macos-x64-release.zip\n'), hash);
      expect(checksumOf('$hash  dartsdk-macos-x64-release.zip'), hash);
    });

    test('is lowercased', () {
      expect(
        checksumOf('${hash.toUpperCase()} *dartsdk-macos-x64-release.zip'),
        hash,
      );
    });

    test('of another file is refused', () {
      expect(
        () => checksumOf('$hash *dartsdk-linux-x64-release.zip'),
        dies(
          'the SDK checksum is of dartsdk-linux-x64-release.zip, not '
          'dartsdk-macos-x64-release.zip',
        ),
      );
    });

    test('without a hash is refused', () {
      for (final sum in ['', '<html>Not Found</html>', 'abc *x.zip']) {
        expect(
          () => checksumOf(sum),
          dies('the SDK checksum says no sha256'),
          reason: sum,
        );
      }
    });
  });

  group('the x64 SDK', () {
    Ran says(String version) =>
        Ran(0, stdout: 'Dart SDK version: $version (stable) on "macos_x64"\n');

    test('says the version it runs as under Rosetta', () async {
      final runner = RecordingRunner((_) => says('3.12.0'));
      expect(await x64VersionOf(runner, '/x64/dart'), '3.12.0');
      expect(runner.argvs, [
        ['arch', '-x86_64', '/x64/dart', '--version'],
      ]);
    });

    test('that says no version says null', () async {
      final runner = RecordingRunner((_) => const Ran(0, stdout: 'hello\n'));
      expect(await x64VersionOf(runner, '/x64/dart'), isNull);
    });

    test('that does not run is refused with its words', () async {
      final runner = RecordingRunner(
        (_) => const Ran(null, stderr: 'No such file or directory\n'),
      );
      await expectLater(
        x64VersionOf(runner, '/x64/dart'),
        dies(
          'arch -x86_64 /x64/dart --version failed: No such file or directory',
        ),
      );
    });

    test('of another version is named', () {
      expect(
        otherVersion('/x64/dart', '3.12.0', '3.13.5'),
        '/x64/dart is Dart 3.12.0, not 3.13.5: darwin-x64 is built by the '
        'same SDK as the rest',
      );
      expect(
        otherVersion('/x64/dart', null, '3.13.5'),
        startsWith('/x64/dart is Dart of no version it says, not 3.13.5'),
      );
    });
  });

  group('the x64 SDK is provided', () {
    const version = '3.13.5';
    const staged = 'staged';
    final zip = utf8.encode('the zip');
    final sum = '${sha256.convert(zip)} *dartsdk-macos-x64-release.zip\n';
    late String cache;
    late String folder;
    late List<String> said;
    late List<Uri> fetched;
    late Map<String, String> versions;
    late Set<String> broken;
    late List<String> stagings;
    void Function()? beforeFreshCheck;

    setUp(() {
      final temp = Directory.systemTemp.createTempSync('x64_sdk_test');
      addTearDown(() => temp.deleteSync(recursive: true));
      cache = temp.path;
      folder = sdkFolder(cache, version);
      said = [];
      fetched = [];
      versions = {};
      broken = {};
      stagings = [];
      beforeFreshCheck = null;
    });

    /// The folders beside the cache folder, as a run leaves them.
    List<String> beside() {
      final parent = Directory(p.dirname(folder));
      if (!parent.existsSync()) return [];
      return [
        for (final entry in parent.listSync())
          if (entry.path != folder) p.basename(entry.path),
      ];
    }

    /// Unzips into ditto's target a dart-sdk with its bin/dart, noting the
    /// target in [stagings]. Each dart says [versions]' version for it, or
    /// [version]; one in [broken] does not run. A staged dart is keyed as
    /// [staged], its folder's name being the run's own.
    RecordingRunner machine({Ran? ditto}) => RecordingRunner((argv) {
      if (argv case ['ditto', '-x', '-k', final zipPath, final into]) {
        stagings.add(into);
        expect(p.dirname(zipPath), into);
        expect(File(zipPath).readAsBytesSync(), zip);
        if (ditto != null) return ditto;
        File(sdkDart(p.join(into, 'dart-sdk'))).createSync(recursive: true);
        return const Ran(0);
      }
      if (argv case ['arch', '-x86_64', final dart, '--version']) {
        final key = stagings.any((s) => p.isWithin(s, dart)) ? staged : dart;
        if (key == staged) beforeFreshCheck?.call();
        if (!File(dart).existsSync() || broken.contains(key)) {
          return const Ran(1, stderr: 'No such file or directory\n');
        }
        return Ran(
          0,
          stdout: 'Dart SDK version: ${versions[key] ?? version} (stable)\n',
        );
      }
      return null;
    });

    Future<List<int>> archive(Uri url) async {
      fetched.add(url);
      if (url.toString() == sdkChecksumUrl(version)) return utf8.encode(sum);
      if (url.toString() == sdkZipUrl(version)) return zip;
      throw StateError('no $url');
    }

    Future<String> provide(RecordingRunner runner, {Fetch? fetch}) =>
        provideX64Sdk(
          runner: runner,
          version: version,
          cache: cache,
          fetch: fetch ?? archive,
          out: said.add,
        );

    void keep({String? marker}) {
      File(sdkDart(folder)).createSync(recursive: true);
      if (marker != null) File(p.join(folder, marker)).createSync();
    }

    test('from the cache when the kept one passes, with nothing '
        'downloaded', () async {
      keep();
      final runner = machine();
      expect(await provide(runner), sdkDart(folder));
      expect(runner.argvs, [
        ['arch', '-x86_64', sdkDart(folder), '--version'],
      ]);
      expect(fetched, isEmpty);
      expect(said, isEmpty);
    });

    test('by a download, checked, unzipped into a folder of its own beside '
        'the cache folder and renamed into place', () async {
      final runner = machine();
      expect(await provide(runner), sdkDart(folder));
      expect(fetched, [
        Uri.parse(sdkChecksumUrl(version)),
        Uri.parse(sdkZipUrl(version)),
      ]);
      final [staging] = stagings;
      expect(p.dirname(staging), p.dirname(folder));
      expect(p.basename(staging), startsWith('macos-x64.partial-'));
      expect(runner.argvs, [
        ['ditto', '-x', '-k', p.join(staging, sdkZipName), staging],
        ['arch', '-x86_64', sdkDart(p.join(staging, 'dart-sdk')), '--version'],
      ]);
      expect(File(sdkDart(folder)).existsSync(), isTrue);
      expect(beside(), isEmpty);
      expect(said, [
        'Downloading the x64 Dart SDK 3.13.5 from '
            '${sdkZipUrl(version)} into $folder',
      ]);
    });

    test('a zip that does not match its checksum is refused, with nothing '
        'kept', () async {
      final runner = machine();
      await expectLater(
        provide(
          runner,
          fetch: (url) async => url.toString() == sdkZipUrl(version)
              ? utf8.encode('another zip')
              : utf8.encode(sum),
        ),
        dies(
          'dartsdk-macos-x64-release.zip of 3.13.5 has sha256 '
          '${sha256.convert(utf8.encode('another zip'))}, not the published '
          '${sha256.convert(zip)}: nothing is kept',
        ),
      );
      expect(runner.calls, isEmpty);
      expect(Directory(folder).existsSync(), isFalse);
      expect(beside(), isEmpty);
    });

    test('a kept SDK of another version is downloaded again and '
        'replaced', () async {
      keep(marker: 'old');
      versions[sdkDart(folder)] = '3.12.0';
      final runner = machine();
      expect(await provide(runner), sdkDart(folder));
      expect(fetched, hasLength(2));
      expect(File(p.join(folder, 'old')).existsSync(), isFalse);
      expect(File(sdkDart(folder)).existsSync(), isTrue);
      expect(beside(), isEmpty);
      expect(said.first, contains('The kept x64 Dart SDK is damaged'));
      expect(said.first, contains('is Dart 3.12.0, not 3.13.5'));
      expect(said.last, startsWith('Downloading the x64 Dart SDK 3.13.5'));
    });

    test('a kept SDK that no longer runs is refused with its path, with no '
        'download', () async {
      keep();
      broken.add(sdkDart(folder));
      final runner = machine();
      await expectLater(
        provide(runner),
        dies(
          'arch -x86_64 ${sdkDart(folder)} --version failed: No such file '
          'or directory',
        ),
      );
      expect(runner.calls, hasLength(1));
      expect(fetched, isEmpty);
      expect(said, isEmpty);
      expect(File(sdkDart(folder)).existsSync(), isTrue);
    });

    test('what other runs are staging beside the cache folder is neither '
        'taken nor touched', () async {
      // macos-x64.partial is the name every run once shared.
      const foreign = ['macos-x64.partial', 'macos-x64.partial-other'];
      for (final name in foreign) {
        File(sdkDart(p.join(p.dirname(folder), name, 'dart-sdk')))
          ..createSync(recursive: true)
          ..writeAsStringSync(name);
      }
      final runner = machine();
      expect(await provide(runner), sdkDart(folder));
      expect(fetched, hasLength(2));
      expect(beside()..sort(), foreign);
      for (final name in foreign) {
        expect(stagings.single, isNot(p.join(p.dirname(folder), name)));
        expect(
          File(
            sdkDart(p.join(p.dirname(folder), name, 'dart-sdk')),
          ).readAsStringSync(),
          name,
        );
      }
    });

    test('when another run keeps the SDK first, this one drops its own '
        'and takes that one once it passes', () async {
      beforeFreshCheck = () => keep(marker: 'theirs');
      final runner = machine();
      expect(await provide(runner), sdkDart(folder));
      expect(File(p.join(folder, 'theirs')).existsSync(), isTrue);
      expect(beside(), isEmpty);
      expect(runner.argvs.last, [
        'arch',
        '-x86_64',
        sdkDart(folder),
        '--version',
      ]);
      expect(
        said.last,
        'Another run kept the x64 Dart SDK in $folder first; '
        'taking it.',
      );
    });

    test('an SDK another run kept first is refused when it says another '
        'version', () async {
      beforeFreshCheck = () {
        keep(marker: 'theirs');
        versions[sdkDart(folder)] = '3.12.0';
      };
      await expectLater(
        provide(machine()),
        dies('${sdkDart(folder)} is Dart 3.12.0, not 3.13.5'),
      );
      expect(File(p.join(folder, 'theirs')).existsSync(), isTrue);
      expect(beside(), isEmpty);
    });

    test('a failed download stops the release with its words, with nothing '
        'kept', () async {
      final runner = machine();
      await expectLater(
        provide(
          runner,
          fetch: (url) async => throw const SocketException('no route'),
        ),
        dies('download of ${sdkChecksumUrl(version)} failed: '),
      );
      await expectLater(
        provide(runner, fetch: (url) async => die('$url answered 404')),
        dies(
          'download of ${sdkChecksumUrl(version)} failed: '
          '${sdkChecksumUrl(version)} answered 404',
        ),
      );
      expect(runner.calls, isEmpty);
      expect(Directory(folder).existsSync(), isFalse);
      expect(beside(), isEmpty);
    });

    test('a failed unzip stops the release, with nothing kept', () async {
      final runner = machine(ditto: const Ran(9, stderr: 'bad zip\n'));
      await expectLater(provide(runner), dies('failed: bad zip'));
      expect(runner.argvs.single, [
        'ditto',
        '-x',
        '-k',
        p.join(stagings.single, sdkZipName),
        stagings.single,
      ]);
      expect(Directory(folder).existsSync(), isFalse);
      expect(beside(), isEmpty);
    });

    test('a downloaded SDK of another version is refused, with nothing '
        'kept', () async {
      versions[staged] = '3.12.0';
      await expectLater(provide(machine()), dies('is Dart 3.12.0, not 3.13.5'));
      expect(Directory(folder).existsSync(), isFalse);
      expect(beside(), isEmpty);
    });

    test('a downloaded SDK that does not run is refused, with nothing '
        'kept', () async {
      broken.add(staged);
      await expectLater(provide(machine()), dies('macos-x64.partial-'));
      await expectLater(
        provide(machine()),
        dies('/dart-sdk/bin/dart --version failed: No such file'),
      );
      expect(Directory(folder).existsSync(), isFalse);
      expect(beside(), isEmpty);
    });

    test('a version of no channel is refused before anything is '
        'fetched', () async {
      final runner = machine();
      await expectLater(
        provideX64Sdk(
          runner: runner,
          version: '3.14.0-edge',
          cache: cache,
          fetch: archive,
          out: said.add,
        ),
        dies('is of no channel'),
      );
      expect(fetched, isEmpty);
      expect(runner.calls, isEmpty);
    });
  });
}
