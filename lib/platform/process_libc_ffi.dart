/// libc's kill, errno and strerror through dart:ffi, for the native build;
/// process_libc_web.dart stands in under Wasm.
library;

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';

final _libc = DynamicLibrary.process();

final _killFn = _libc
    .lookupFunction<Int32 Function(Int32, Int32), int Function(int, int)>(
      'kill',
    );

final _errnoLocation = _libc
    .lookupFunction<Pointer<Int32> Function(), Pointer<Int32> Function()>(
      Platform.isMacOS ? '__error' : '__errno_location',
    );

final _strerror = _libc
    .lookupFunction<
      Pointer<Uint8> Function(Int32),
      Pointer<Uint8> Function(int)
    >('strerror');

/// `kill(2)`: 0, or the errno it failed with. A failure is never 0,
/// whatever errno reads by then.
int libcKill(int pid, int signal) {
  if (_killFn(pid, signal) == 0) return 0;
  final errno = _errnoLocation().value;
  return errno == 0 ? -1 : errno;
}

/// libc's words for [errno], as `No such file or directory`.
String strerror(int errno) {
  final text = _strerror(errno);
  var length = 0;
  while (text[length] != 0) {
    length++;
  }
  return utf8.decode(text.asTypedList(length));
}
