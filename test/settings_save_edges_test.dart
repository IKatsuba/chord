import 'dart:convert';
import 'dart:io';

import 'package:chord/settings.dart';
import 'package:test/test.dart';

import 'settings_save_test.dart' show place, beside;

final class _FailTemporary extends IOOverrides {
  _FailTemporary({required this.duringWrite});
  final bool duringWrite;
  bool attempted = false;

  @override
  File createFile(String path) {
    final file = super.createFile(path);
    return path.endsWith('.tmp') ? _FailFile(file, this) : file;
  }
}

class _FailFile implements File {
  _FailFile(this.file, this.owner);
  final File file;
  final _FailTemporary owner;

  @override
  Future<File> writeAsString(
    String contents, {
    FileMode mode = FileMode.write,
    Encoding encoding = utf8,
    bool flush = false,
  }) async {
    await file.writeAsString(
      contents,
      mode: mode,
      encoding: encoding,
      flush: flush,
    );
    if (owner.duringWrite) {
      owner.attempted = true;
      throw const FileSystemException('injected temporary write failure');
    }
    return this;
  }

  @override
  Future<File> rename(String newPath) async {
    owner.attempted = true;
    expect(await file.exists(), isTrue);
    throw const FileSystemException('injected rename failure');
  }

  @override
  Future<FileSystemEntity> delete({bool recursive = false}) =>
      file.delete(recursive: recursive);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('tester: settings writer filesystem boundaries', () {
    for (final duringWrite in [true, false]) {
      test(
        'temporary is cleaned after ${duringWrite ? 'write' : 'rename'} failure',
        () async {
          const raw = '{"theme":"dark","keep":[1,null]}';
          await place(user: raw, (home, _) async {
            final file = userSettingsFile(home)!;
            final failures = _FailTemporary(duringWrite: duringWrite);
            await expectLater(
              IOOverrides.runWithIOOverrides(
                () => saveTheme(file, 'light'),
                failures,
              ),
              throwsA(isA<FileSystemException>()),
            );
            expect(failures.attempted, isTrue);
            expect(await File(file).readAsString(), raw);
            expect(beside(file), ['settings.json']);
          });
        },
      );
    }

    test(
      'absent removal creates no directory and preserves existing bytes',
      () async {
        await place((home, _) async {
          final file = userSettingsFile(home)!;
          await saveSettingAt(file, ['missing', 'leaf'], const RemoveSetting());
          expect(await Directory(home).exists(), isFalse);
        });
        const raw = '{ "keep":  1 }\n';
        await place(user: raw, (home, _) async {
          final file = userSettingsFile(home)!;
          final before = await File(file).stat();
          await saveSettingAt(file, ['missing'], const RemoveSetting());
          expect(await File(file).readAsString(), raw);
          expect((await File(file).stat()).modified, before.modified);
          expect(beside(file), ['settings.json']);
        });
      },
    );

    test(
      'null removal prunes parents while preserving unrelated prototype names',
      () async {
        await place(
          user: '{"__proto__":{"kept":true},"nested":{"leaf":null}}',
          (home, _) async {
            final file = userSettingsFile(home)!;
            await saveSettingAt(file, [
              'nested',
              'leaf',
            ], const RemoveSetting());
            expect(await readSettingsObject(file), {
              '__proto__': {'kept': true},
            });
            await saveSettingAt(file, ['mouse'], const SetSetting(false));
            expect(await readSettingsObject(file), {
              '__proto__': {'kept': true},
              'mouse': false,
            });
          },
        );
        await place(user: '{"theme":null}', (home, _) async {
          final file = userSettingsFile(home)!;
          await saveSettingAt(file, ['theme'], const RemoveSetting());
          expect(await File(file).readAsString(), '{}\n');
        });
      },
    );

    test(
      'nonobject parents refuse set and removal without touching bytes',
      () async {
        for (final parent in [null, false, 3, 'value', <Object?>[]]) {
          final raw = jsonEncode({
            'agents': {'named': parent},
          });
          await place(user: raw, (home, _) async {
            final file = userSettingsFile(home)!;
            for (final change in const [SetSetting('model'), RemoveSetting()]) {
              await expectLater(
                saveSettingAt(file, ['agents', 'named', 'model'], change),
                throwsA(isA<SettingRefused>()),
              );
              expect(await File(file).readAsString(), raw);
              expect(beside(file), ['settings.json']);
            }
          });
        }
      },
    );

    test(
      'nested displayed values escape terminal controls and retain Unicode',
      () {
        final controls = String.fromCharCodes(List.generate(160, (i) => i));
        final value = {
          controls: ['🙂', '\u200d\u2066\u2029', '\u{e0001}', controls],
        };
        final shown = shownValue(value);
        expect(
          shown,
          isNot(matches(RegExp(r'[\p{Cc}\p{Cf}\p{Zl}\p{Zp}]', unicode: true))),
        );
        expect(jsonDecode(shown), value);
        expect(shown, contains('🙂'));
        expect(shown, contains(r'\udb40\udc01'));
        expect(
          shownSettingPath(['agents', '', 'my.agent', controls]),
          'agents.""."my.agent".${shownValue(controls)}',
        );
      },
    );
  });
}
