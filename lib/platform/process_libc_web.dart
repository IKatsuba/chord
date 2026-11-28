/// The web's stand-in for process_libc_ffi.dart: a browser has no processes
/// to signal and no libc to ask.
library;

/// `kill(2)`, which a browser cannot do.
int libcKill(int pid, int signal) =>
    throw UnsupportedError('kill(2) is not available on the web');

/// libc's words for [errno]; the web has none, so the number alone.
String strerror(int errno) => 'errno $errno';
