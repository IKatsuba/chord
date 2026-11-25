/// ACP's framing over stdio, as the SDK's `ndJsonStream` does it: one JSON
/// message per line each way, with its cap and its answers to lines that are
/// not messages.
library;

import 'dart:convert';
import 'dart:typed_data';

/// The longest line read from an agent, as the SDK's
/// `DEFAULT_MAX_MESSAGE_BYTES`: 32 MiB.
const defaultMaxMessageBytes = 32 * 1024 * 1024;

/// A line from the agent past [maxMessageBytes]: the connection fails, and
/// nothing of the line is kept.
class MessageTooLargeError implements Exception {
  /// The cap that was passed.
  const MessageTooLargeError(this.maxMessageBytes);

  final int maxMessageBytes;

  @override
  String toString() =>
      'Incoming ACP data exceeds the configured $maxMessageBytes byte limit';
}

/// What one line from the agent turned into.
sealed class Framed {
  const Framed();
}

/// A JSON object: a message, routed on.
final class FramedMessage extends Framed {
  /// The decoded [message].
  const FramedMessage(this.message);

  final Map<String, Object?> message;
}

/// A line that is not a message, and the error the SDK answers it with,
/// which goes to the agent past the tap.
final class FramingReply extends Framed {
  /// The [reply] to write back.
  const FramingReply(this.reply);

  final Map<String, Object?> reply;
}

/// Splits what the agent writes into lines and decodes each: lines end at
/// `\n` with one `\r` before it dropped, blank lines are skipped, a last
/// line without a newline is taken at the end, and malformed UTF-8 reads as
/// U+FFFD.
class LineDecoder {
  /// A decoder whose lines may be at most [maxMessageBytes] long.
  LineDecoder({this.maxMessageBytes = defaultMaxMessageBytes});

  final int maxMessageBytes;

  final _pending = BytesBuilder();
  int? _pendingLast;

  /// Hands [emit] each line [chunk] completes, as it completes; throws
  /// [MessageTooLargeError] once the line being read passes the cap, after
  /// what came before it was emitted, keeping none of the line.
  void add(List<int> chunk, void Function(Framed framed) emit) {
    var start = 0;
    while (true) {
      final newline = chunk.indexOf(0x0A, start);
      if (newline < 0) break;
      _check(chunk, start, newline);
      final Uint8List line;
      if (_pending.isEmpty) {
        line = Uint8List.fromList(chunk.sublist(start, newline));
      } else {
        _pending.add(chunk.sublist(start, newline));
        line = _pending.takeBytes();
        _pendingLast = null;
      }
      _decode(line, emit);
      start = newline + 1;
    }
    if (start < chunk.length) {
      _check(chunk, start, chunk.length);
      _pending.add(chunk.sublist(start));
      _pendingLast = chunk.last;
    }
  }

  /// The input ended: hands [emit] what its last line, unterminated, holds.
  void close(void Function(Framed framed) emit) {
    if (_pending.isNotEmpty) {
      _pendingLast = null;
      _decode(_pending.takeBytes(), emit);
    }
  }

  void _check(List<int> chunk, int start, int end) {
    final last = end > start ? chunk[end - 1] : _pendingLast;
    final length = _pending.length + end - start - (last == 0x0D ? 1 : 0);
    if (length > maxMessageBytes) {
      _pending.clear();
      _pendingLast = null;
      throw MessageTooLargeError(maxMessageBytes);
    }
  }

  void _decode(Uint8List bytes, void Function(Framed framed) emit) {
    final line = bytes.isNotEmpty && bytes.last == 0x0D
        ? Uint8List.sublistView(bytes, 0, bytes.length - 1)
        : bytes;
    final text = utf8.decode(line, allowMalformed: true).trim();
    if (text.isEmpty) return;
    final Object? message;
    try {
      message = jsonDecode(text);
    } on FormatException {
      emit(FramingReply(_error(-32700, 'Parse error')));
      return;
    }
    // ACP has no batches: an array is answered once, unread.
    if (message is List) {
      emit(
        FramingReply(
          _error(-32600, 'Invalid request: JSON-RPC batches are not supported'),
        ),
      );
    } else if (message is Map<String, Object?>) {
      emit(FramedMessage(message));
    } else {
      emit(FramingReply(_error(-32600, 'Invalid request', data: (message,))));
    }
  }

  static Map<String, Object?> _error(
    int code,
    String message, {
    (Object?,)? data,
  }) => {
    'jsonrpc': '2.0',
    'id': null,
    'error': {
      'code': code,
      'message': message,
      if (data != null) 'data': data.$1,
    },
  };
}

/// [message] as the line written to the agent.
Uint8List encodeLine(Map<String, Object?> message) =>
    utf8.encode('${jsonEncode(message)}\n');
