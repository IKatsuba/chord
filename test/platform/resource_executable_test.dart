// The original's tests/platform/resource_executable_test.ts: the official
// executables found, checked native and asked their version, through an
// injected inspection; plus the Mach-O/ELF check and the version read on a
// real script.
import 'dart:io';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/platform/resource_executable.dart';
import 'package:chord/platform/resources.dart';
import 'package:path/path.dart' as p;
import 'package:test/test.dart';

/// An inspection whose parts the tests set.
final class _Inspection implements ExecutableInspection {
  _Inspection({
    this.platform = 'darwin',
    this.arch = 'arm64',
    Future<String?> Function(String name)? lookup,
    bool isNative = true,
    Future<String> Function()? version,
  }) : _lookup = lookup ?? ((_) async => '/fixture/codex'),
       _native = isNative,
       _version = version ?? (() async => 'codex-cli 0.163.0');

  @override
  final String platform;
  @override
  final String arch;
  final Future<String?> Function(String name) _lookup;
  final bool _native;
  final Future<String> Function() _version;
  var lookups = 0;

  @override
  Future<String?> lookup(String name) {
    lookups++;
    return _lookup(name);
  }

  @override
  Future<bool> native(String path) async => _native;

  @override
  Future<String> version(String path, String cwd, CancellationToken c) =>
      _version();
}

Future<Object> _resolve(
  String provider,
  ExecutableInspection inspect, {
  bool customCommand = false,
}) async => switch (await resolveResourceExecutable(
  provider,
  cwd: '/project',
  cancelled: CancellationToken(),
  customCommand: customCommand,
  inspect: inspect,
)) {
  ExecutableFound(:final path, :final version) => (path, version),
  ExecutableUnavailable(:final unavailable) => unavailable,
};

void main() {
  group('CTUI-37 tester: executable refusal side effects', () {
    test('custom and unsupported targets never look up a provider', () async {
      for (final (platform, arch, custom) in [
        ('darwin', 'arm64', true),
        ('linux', 'arm64', false),
        ('darwin', 'x64', false),
      ]) {
        final inspect = _Inspection(
          platform: platform,
          arch: arch,
          lookup: (_) async =>
              throw TestFailure('no provider lookup is permitted'),
        );
        expect(
          await _resolve('claude', inspect, customCommand: custom),
          isA<String>(),
        );
        expect(inspect.lookups, 0);
      }
    });
  });

  test('resolves evaluated native versions, without using an ACP command as '
      'the provider path', () async {
    expect(await _resolve('codex', _Inspection()), (
      '/fixture/codex',
      '0.163.0',
    ));
    final wrapper = _Inspection(lookup: (_) async => '/wrapper');
    expect(
      await _resolve('codex', wrapper, customCommand: true),
      'Custom ACP command has no verified association with the official '
      'native provider authentication.',
    );
    expect(wrapper.lookups, 0);
  });

  test("official Codex launcher uses its existing Node; Claude remains "
      'native-only', () async {
    expect(await _resolve('codex', _Inspection(isNative: false)), (
      '/fixture/codex',
      '0.163.0',
    ));
    expect(
      await _resolve('claude', _Inspection(isNative: false)),
      'The Claude collector requires the official native executable.',
    );
    expect(
      await _resolve(
        'codex',
        _Inspection(
          isNative: false,
          lookup: (name) async => name == 'node' ? null : '/fixture/codex',
        ),
      ),
      'The official npm Codex launcher requires an existing Node '
      'installation.',
    );
  });

  test(
    'another provider version resolves with the version it reports',
    () async {
      expect(
        await _resolve(
          'codex',
          _Inspection(version: () async => 'codex-cli 0.164.0'),
        ),
        ('/fixture/codex', '0.164.0'),
      );
      expect(
        await _resolve(
          'claude',
          _Inspection(
            lookup: (_) async => '/fixture/claude',
            version: () async => '2.1.312 (Claude Code)',
          ),
        ),
        ('/fixture/claude', '2.1.312'),
      );
    },
  );

  test('an unrecognised or empty version output is unavailable', () async {
    for (final provider in ['codex', 'claude']) {
      for (final output in [
        '',
        'unknown',
        'codex 0.164.0',
        'codex-cli ',
        ' (Claude Code)',
        if (provider == 'codex') '2.1.312 (Claude Code)',
        if (provider == 'claude') 'codex-cli 0.163.0',
      ]) {
        expect(
          await _resolve(provider, _Inspection(version: () async => output)),
          'Native provider version could not be read.',
          reason: '$provider $output',
        );
      }
    }
  });

  test('missing and unsupported targets are advisory', () async {
    expect(
      await _resolve('codex', _Inspection(lookup: (_) async => null)),
      'Official native provider executable is missing from PATH.',
    );
    for (final inspect in [
      _Inspection(platform: 'linux'),
      _Inspection(arch: 'x64'),
    ]) {
      expect(
        await _resolve('codex', inspect),
        'Resource collector compatibility is not verified on this platform.',
      );
    }
  });

  test('a version timeout or failure is unavailable, but cleanup failure is '
      'not swallowed', () async {
    for (final provider in ['codex', 'claude']) {
      for (final error in [
        const ResourceReadError('timeout', 'Version timeout.'),
        Exception('Fixture version failure.'),
      ]) {
        expect(
          await _resolve(
            provider,
            _Inspection(version: () async => throw error),
          ),
          'Official provider executable could not be verified.',
        );
      }
    }
    await expectLater(
      _resolve(
        'codex',
        _Inspection(
          version: () async => throw const ResourceReadError(
            'cleanup',
            'Owned group exit unverified.',
          ),
        ),
      ),
      throwsA(
        isA<ResourceReadError>().having((e) => e.kind, 'kind', 'cleanup'),
      ),
    );
  });

  group('the native check, as file-type 22.3.0 reads magic numbers', () {
    test('ELF and every thin Mach-O are native', () {
      for (final head in [
        [0x7F, 0x45, 0x4C, 0x46, 2, 1],
        [0xFE, 0xED, 0xFA, 0xCE, 0, 0],
        [0xFE, 0xED, 0xFA, 0xCF, 0, 0],
        [0xCE, 0xFA, 0xED, 0xFE, 0, 0],
        [0xCF, 0xFA, 0xED, 0xFE, 0, 0],
      ]) {
        expect(isNativeExecutable(head), isTrue, reason: '$head');
      }
    });

    test('a universal Mach-O is native by its architecture count, 1 to 30; '
        'a Java class file is not', () {
      List<int> fat(int count) => [
        0xCA, 0xFE, 0xBA, 0xBE, //
        count >> 24 & 0xFF, count >> 16 & 0xFF, count >> 8 & 0xFF,
        count & 0xFF,
      ];
      expect(isNativeExecutable(fat(1)), isTrue);
      expect(isNativeExecutable(fat(30)), isTrue);
      expect(isNativeExecutable(fat(0)), isFalse);
      expect(isNativeExecutable(fat(31)), isFalse);
      // A class file: its minor and major version, 0 and 52, read as 52.
      expect(isNativeExecutable(fat(52)), isFalse);
      expect(isNativeExecutable([0xCA, 0xFE, 0xBA, 0xBE]), isFalse);
    });

    test('a script, an empty file and short reads are not native', () {
      expect(isNativeExecutable('#!/bin/sh\n'.codeUnits), isFalse);
      expect(isNativeExecutable(const []), isFalse);
      expect(isNativeExecutable(const [0x7F, 0x45, 0x4C]), isFalse);
    });

    test("the machine's own Dart is native; a shell script is not", () async {
      expect(
        await machineInspection.native(Platform.resolvedExecutable),
        isTrue,
      );
      final dir = Directory.systemTemp.createTempSync('chord-native-');
      addTearDown(() => dir.deleteSync(recursive: true));
      final script = File(p.join(dir.path, 'codex'))
        ..writeAsStringSync('#!/bin/sh\necho hi\n');
      expect(await machineInspection.native(script.path), isFalse);
    }, testOn: 'posix');
  });

  group('the version read', () {
    late Directory dir;
    setUp(() {
      dir = Directory.systemTemp.createTempSync('chord-version-');
      addTearDown(() => dir.deleteSync(recursive: true));
    });

    String script(String body) {
      final file = File(p.join(dir.path, 'provider'))
        ..writeAsStringSync('#!/bin/sh\n$body\n');
      Process.runSync('chmod', ['+x', file.path]);
      return file.path;
    }

    test('says what the executable answers, trimmed', () async {
      expect(
        await readVersion(
          script('echo "codex-cli 0.163.0"'),
          dir.path,
          CancellationToken(),
        ),
        'codex-cli 0.163.0',
      );
    });

    test('a failed exit or more than 4096 bytes reads as nothing', () async {
      expect(
        await readVersion(
          script('echo "codex-cli 0.163.0"; exit 3'),
          dir.path,
          CancellationToken(),
        ),
        '',
      );
      expect(
        await readVersion(
          script('head -c 5000 /dev/zero | tr "\\0" x'),
          dir.path,
          CancellationToken(),
        ),
        '',
      );
    });

    test(
      'one that never ends is a timeout after 3 s, its group gone',
      () async {
        final started = DateTime.now();
        await expectLater(
          readVersion(script('exec sleep 60'), dir.path, CancellationToken()),
          throwsA(
            isA<ResourceReadError>().having((e) => e.kind, 'kind', 'timeout'),
          ),
        );
        expect(
          DateTime.now().difference(started),
          lessThan(const Duration(seconds: 6)),
        );
      },
    );
  }, testOn: 'posix');
}
