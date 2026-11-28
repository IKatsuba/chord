/// The machine's architecture as Node names it, from dart:ffi's [Abi];
/// resource_arch_web.dart stands in under Wasm.
library;

import 'dart:ffi' show Abi;

/// This machine's architecture as `process.arch` says it in Node.
String nodeArch() => switch (Abi.current()) {
  Abi.macosArm64 || Abi.linuxArm64 => 'arm64',
  Abi.macosX64 || Abi.linuxX64 => 'x64',
  final abi => '$abi',
};
