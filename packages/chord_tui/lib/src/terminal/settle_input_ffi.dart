import 'dart:ffi';

import 'package:ffi/ffi.dart';

/// Asks the tty how much input is pending, which settles a read the kernel
/// still holds for the process; native builds only.
void settlePendingInput() {
  final libc = DynamicLibrary.process();
  final open = libc
      .lookupFunction<
        Int32 Function(Pointer<Utf8>, Int32),
        int Function(Pointer<Utf8>, int)
      >('open');
  final ioctl = libc
      .lookupFunction<
        Int32 Function(Int32, Uint64, VarArgs<(Pointer<Int32>,)>),
        int Function(int, int, Pointer<Int32>)
      >('ioctl');
  final close = libc.lookupFunction<Int32 Function(Int32), int Function(int)>(
    'close',
  );
  using((arena) {
    final path = '/dev/tty'.toNativeUtf8(allocator: arena);
    final fd = open(path, 0);
    if (fd < 0) return;
    try {
      ioctl(fd, 0x4004667f, arena<Int32>()); // FIONREAD on Darwin.
    } finally {
      close(fd);
    }
  });
}
