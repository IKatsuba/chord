/// The web's stand-in for group_exec_ffi.dart: a browser starts no process
/// groups.
library;

/// The launcher, which a browser cannot be.
Never groupExec(List<String> args) =>
    throw UnsupportedError('the group launcher is not available on the web');
