import 'package:chord/platform/group_exec.dart';
import 'package:chord/platform/process.dart' show strerror;
import 'package:chord/platform/process_libc_ffi.dart'
    if (dart.library.js_interop) 'package:chord/platform/process_libc_web.dart'
    show libcKill;
import 'package:chord/platform/resource_executable.dart';

void main() {
  if (strerror(2) != 'errno 2' || strerror(13) != 'errno 13') {
    throw StateError('web error numbers were lost');
  }
  refuses('signal', () => libcKill(1, 0));
  refuses('launcher', () => groupExec([]));
  refuses('architecture', () => machineInspection.arch);
  print('web platform refusals passed');
}

void refuses(String operation, Object? Function() action) {
  try {
    action();
  } on UnsupportedError {
    return;
  }
  throw StateError('$operation did not refuse a native operation');
}
