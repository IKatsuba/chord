/// The launcher an agent is started through, so it leads a process group of
/// its own: chord runs itself with [groupExecFlag], and that copy calls
/// `setsid` and `execv`s the agent in place, keeping the pid `Process.start`
/// returned along with its pipes and exit code.
///
/// ```text
/// --chord-group-exec <nonce> <path> -- <argv0> <args…>
/// ```
library;

import 'dart:io';

import 'group_exec_ffi.dart' if (dart.library.js_interop) 'group_exec_web.dart';

export 'group_exec_ffi.dart'
    if (dart.library.js_interop) 'group_exec_web.dart'
    show groupExec;

/// The first argument that turns chord into the launcher.
const groupExecFlag = '--chord-group-exec';

/// The JIT path's entry: `dart` runs this file directly as the launcher.
void main(List<String> args) => groupExec(args);

const _enoent = 2, _eacces = 13;

/// What a lookup of a path shows: there, proven not there, or neither,
/// as when a directory on the way may not be searched.
enum Lookup {
  /// It is there.
  found,

  /// A searchable directory holds no such name, or a directory on the way
  /// is itself missing.
  missing,

  /// The files cannot tell: a directory on the way that may not be
  /// searched, or a link that does not resolve.
  unknown,
}

/// How [path] looks up: [kind] stats it (a failure reads as not found,
/// as dart:io's does), and [searchable] says a directory may be searched.
Lookup lookup(
  String path, {
  required FileSystemEntityType Function(
    String path, {
    required bool followLinks,
  })
  kind,
  required bool Function(String dir) searchable,
}) {
  if (kind(path, followLinks: false) != FileSystemEntityType.notFound) {
    // A link that does not resolve may be dangling or a loop.
    return kind(path, followLinks: true) == FileSystemEntityType.notFound
        ? Lookup.unknown
        : Lookup.found;
  }
  final slash = path.lastIndexOf('/');
  if (slash < 0) return Lookup.unknown;
  final parent = slash == 0 ? '/' : path.substring(0, slash);
  if (parent == path) return Lookup.unknown;
  return switch (lookup(parent, kind: kind, searchable: searchable)) {
    Lookup.found =>
      kind(parent, followLinks: true) == FileSystemEntityType.directory &&
              searchable(parent)
          ? Lookup.missing
          : Lookup.unknown,
    Lookup.missing => Lookup.missing,
    Lookup.unknown => Lookup.unknown,
  };
}

/// Why an `execv` of [path] failed: [code] is 127 when the program, or a
/// script's `#!` interpreter, is not there (ENOENT, as CTUI-36 says), else
/// 126; [errno] is the one to report. Both come from the files where they
/// show it (not there; not a [runnable] file), and from [read], the errno
/// read after the call, where they cannot.
({int code, int errno}) execFailure(
  String path, {
  required int read,
  required FileSystemEntityType Function(
    String path, {
    required bool followLinks,
  })
  kind,
  required bool Function(String dir) searchable,
  required bool Function(String path) runnable,
  required String? Function(String path) firstLine,
}) {
  final fromErrno = (code: read == _enoent ? 127 : 126, errno: read);
  Lookup look(String path) => lookup(path, kind: kind, searchable: searchable);
  switch (look(path)) {
    case Lookup.missing:
      return (code: 127, errno: _enoent);
    case Lookup.unknown:
      return fromErrno;
    case Lookup.found:
  }
  if (!runnable(path)) return (code: 126, errno: _eacces);
  final line = firstLine(path);
  if (line == null || !line.startsWith('#!')) return fromErrno;
  final interpreter = line.substring(2).trim().split(RegExp(r'\s+')).first;
  if (interpreter.isEmpty) return fromErrno;
  return switch (look(interpreter)) {
    Lookup.missing => (code: 127, errno: _enoent),
    Lookup.unknown || Lookup.found => fromErrno,
  };
}
