/// Codex's limits as its own app server says them: `codex app-server` over
/// newline-delimited JSON-RPC, through `json_rpc_2`'s client, the handshake,
/// the account read and, for a ChatGPT subscription, its rate limits. From
/// the original's `session/codex_resources.ts`.
library;

import 'dart:async';
import 'dart:convert';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:json_rpc_2/json_rpc_2.dart';
import 'package:stream_channel/stream_channel.dart';

import '../acp/wire.dart';
import '../platform/resource_process.dart';
import 'budgets.dart';
import 'resource_normalization.dart';

/// [lines] as `json_rpc_2` takes Codex's messages: Codex's app server sends
/// no `"jsonrpc": "2.0"`, which `json_rpc_2` drops a response for lacking,
/// so it is added to each message that comes and taken off each that goes,
/// as the original's client sends none. A line that is not a JSON object is
/// the stream's error.
StreamChannel<Object?> codexChannel(StreamChannel<String> lines) {
  final out = StreamController<Object?>(sync: true);
  out.stream.listen((message) {
    if (message is! Map) return;
    final sent = {
      for (final MapEntry(:key, :value) in message.entries)
        if (key != 'jsonrpc') key: value,
    };
    lines.sink.add(jsonEncode(sent));
  }, onDone: lines.sink.close);
  return StreamChannel.withCloseGuarantee(
    lines.stream.map((line) {
      final message = jsonDecode(line);
      if (message is! Map<String, Object?>) {
        throw const FormatException('A Codex message is not an object.');
      }
      return {'jsonrpc': '2.0', ...message};
    }),
    out.sink,
  );
}

/// [stdout] and [stdin] as lines: each message one line of UTF-8, what
/// comes framed as ACP's wire frames it, so a line past [maxLineBytes], or
/// one that grows past it with no end, is refused as it passes the cap and
/// nothing more of it is kept. A line that is not a JSON object is the
/// stream's error, as a refused one is.
StreamChannel<String> lineChannel(
  Stream<List<int>> stdout,
  StreamSink<List<int>> stdin, {
  int maxLineBytes = defaultMaxMessageBytes,
}) {
  final out = StreamController<String>(sync: true);
  out.stream.listen((line) {
    // A write after the reader closed its stdin goes nowhere.
    try {
      stdin.add(utf8.encode('$line\n'));
    } on StateError {
      return;
    }
  });
  final decoder = LineDecoder(maxMessageBytes: maxLineBytes);
  final lines = StreamController<String>(sync: true);
  late final StreamSubscription<List<int>> reading;
  void emit(Framed framed) => switch (framed) {
    FramedMessage(:final message) => lines.add(jsonEncode(message)),
    FramingReply() => lines.addError(
      const FormatException('A Codex line is not a JSON object.'),
    ),
  };
  void refuse(Object error) {
    reading.cancel().ignore();
    lines
      ..addError(error)
      ..close().ignore();
  }

  lines.onListen = () {
    reading = stdout.listen(
      (chunk) {
        try {
          decoder.add(chunk, emit);
        } on MessageTooLargeError catch (error) {
          refuse(error);
        }
      },
      onError: refuse,
      onDone: () {
        decoder.close(emit);
        lines.close().ignore();
      },
      cancelOnError: false,
    );
  };
  lines.onCancel = () => reading.cancel();
  return StreamChannel(lines.stream, out.sink);
}

/// Codex's limits, read by running [command] (its app server) in [cwd]
/// within [bounds]: the handshake, then the account, then, for a ChatGPT
/// subscription only, its rate limits; an account of any other kind never
/// asks for them. A line from it past [maxLineBytes] ends the read.

Future<ProviderLimits> collectCodexResources(
  List<String> command, {
  required String cwd,
  required CancellationToken cancelled,
  CollectorBounds bounds = collectorBounds,
  int maxLineBytes = defaultMaxMessageBytes,
}) => withResourceProcess(
  command,
  cwd: cwd,
  cancelled: cancelled,
  bounds: bounds,
  read: (group, within, onClose) async {
    final client = Client.withoutJson(
      codexChannel(
        lineChannel(group.stdout, group.stdin, maxLineBytes: maxLineBytes),
      ),
    );
    onClose(client.close);
    client.listen().ignore();
    await resourceStep(
      client.sendRequest('initialize', {
        'capabilities': null,
        'clientInfo': {
          'name': 'chord-resource-reader',
          'title': 'Chord resource facts',
          'version': '1',
        },
      }),
      within,
      bounds.initialize,
    );
    client.sendNotification('initialized');
    final account = await resourceStep(
      client.sendRequest('account/read', {'refreshToken': false}),
      within,
      bounds.request,
    );
    final kind = account is Map ? account['account'] : null;
    if (kind is! Map || kind['type'] != 'chatgpt') {
      return normalizeCodex(account, null);
    }
    final limits = await resourceStep(
      client.sendRequest('account/rateLimits/read'),
      within,
      bounds.request,
    );
    within.throwIfCancelled();
    return normalizeCodex(account, limits);
  },
);
