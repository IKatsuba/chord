import 'dart:async';

import '../foundation/geometry.dart';
import 'terminal.dart';

/// A [Terminal] over a host given as functions and streams: a web terminal
/// on a page, or anything else that draws escape sequences and sends keys.
///
/// It owns the modes the app draws in, as the process's own terminal does:
/// the alternate screen, a hidden cursor, bracketed paste, and with [mouse]
/// SGR pointer reports. [leave] undoes them. There is no process to lend
/// the terminal to, so [suspend] and [runEditor] are refused.
class HostTerminal extends Terminal {
  /// Writes through [write], reads keys from [input], and asks [size] for
  /// the window, which [resizes] reports each time it changes. Without
  /// [mouse] the host keeps the pointer for its own selection.
  HostTerminal({
    required void Function(String data) write,
    required Stream<String> input,
    required Size Function() size,
    required Stream<Size> resizes,
    this.mouse = false,
  }) : _write = write,
       _input = input,
       _size = size,
       _resizes = resizes;

  /// Whether the app asks for pointer reports while it owns the terminal.
  final bool mouse;

  final void Function(String data) _write;
  final Stream<String> _input;
  final Size Function() _size;
  final Stream<Size> _resizes;
  var _entered = false;

  @override
  Size get size => _size();

  @override
  Stream<String> get input => _input;

  @override
  Stream<Size> get resizes => _resizes;

  @override
  void write(String data) => _write(data);

  @override
  void enter() {
    if (_entered) return;
    _entered = true;
    write('\x1b[?1049h\x1b[?25l\x1b[?2004h');
    if (mouse) write('\x1b[?1000h\x1b[?1002h\x1b[?1006h');
  }

  @override
  Future<void> leave() async {
    if (!_entered) return;
    _entered = false;
    if (mouse) write('\x1b[?1000l\x1b[?1002l\x1b[?1006l');
    write('\x1b[?2004l\x1b[0m\x1b[0 q\x1b[?25h\x1b[?1049l');
  }

  @override
  Future<T> suspend<T>(Future<T> Function() action) => Future.error(
    StateError('A host terminal has no process to lend the terminal to.'),
  );

  @override
  Future<int> runEditor(
    String path, {
    String? command,
    String? workingDirectory,
  }) => Future.error(
    StateError('A host terminal has no process to run an editor in.'),
  );
}
