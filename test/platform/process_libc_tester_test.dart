import 'dart:ffi' show Abi;
import 'dart:io';

import 'package:chord/platform/process.dart' show strerror;
import 'package:chord/platform/process_libc_ffi.dart' as native;
import 'package:chord/platform/resource_executable.dart';
import 'package:test/test.dart';

void main() {
  group('CHD-638 tester: native platform split', () {
    test('signal zero reaches libc without terminating the caller', () {
      expect(native.libcKill(pid, 0), 0);
    });

    test('public errors retain native libc wording', () {
      expect(strerror(2), native.strerror(2));
      expect(strerror(2), isNot('errno 2'));
      expect(strerror(2), isNotEmpty);
    });

    test('machine inspection retains the native architecture', () {
      final expected = switch (Abi.current()) {
        Abi.macosArm64 || Abi.linuxArm64 => 'arm64',
        Abi.macosX64 || Abi.linuxX64 => 'x64',
        final abi => '$abi',
      };
      expect(machineInspection.arch, expected);
    });
  });
}
