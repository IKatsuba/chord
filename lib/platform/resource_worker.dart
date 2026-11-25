/// Claude's limits as its own SDK's experimental usage getter reads them,
/// spoken from Dart: the verified native `claude`, in a group of its own,
/// is sent the two stream-json control requests SDK 0.3.325 sends for the
/// getter (`initialize`, then `get_usage` with `skip_behaviors`), on the
/// SDK's argv and environment, and never an inference prompt. The original
/// runs the SDK in a worker re-exec of chord; with no Agent SDK in Dart the
/// port speaks its wire itself (the owner's Q1), its failures in the
/// original's words, and its output bound on all of `claude`'s stdout. From
/// the original's `platform/resource_worker.ts`.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:cancellation_token/cancellation_token.dart';

import '../session/budgets.dart';
import '../session/resource_normalization.dart';
import 'resource_process.dart';

/// The SDK version whose wire this speaks.
const claudeSdkVersion = '0.3.325';

/// What `claude` is run with: the SDK's stream-json flags and the worker's
/// options, no tools, no settings sources, no MCP servers, no session kept
/// and no hooks.
const claudeUsageArgs = [
  '--output-format',
  'stream-json',
  '--verbose',
  '--input-format',
  'stream-json',
  '--tools=',
  '--setting-sources=',
  '--strict-mcp-config',
  '--no-session-persistence',
  '--settings',
  '{"disableAllHooks":true}',
];

/// The most of `claude`'s stdout read, in total, before the read is
/// refused.
const claudeOutputBound = 256 * 1024;

/// [base] as the SDK hands it to `claude`: its entry point named unless
/// already set, its version, that it reads session state unless a variable
/// of that name in any case is set, and `NODE_OPTIONS` and `DEBUG` left
/// out.
Map<String, String> claudeUsageEnvironment(Map<String, String> base) {
  const readsState = 'CLAUDE_CODE_SDK_READS_SESSION_STATE';
  final entryPoint = base['CLAUDE_CODE_ENTRYPOINT'] ?? '';
  return {
    for (final MapEntry(:key, :value) in base.entries)
      if (key != 'NODE_OPTIONS' && key != 'DEBUG') key: value,
    'CLAUDE_CODE_ENTRYPOINT': entryPoint.isEmpty ? 'sdk-ts' : entryPoint,
    'CLAUDE_AGENT_SDK_VERSION': claudeSdkVersion,
    if (!base.keys.any((key) => key.toUpperCase() == readsState))
      readsState: '1',
  };
}

final _random = Random.secure();

/// A request id as the SDK makes one: random letters and digits.
String _requestId() => [
  for (var i = 0; i < 13; i++)
    '0123456789abcdefghijklmnopqrstuvwxyz'[_random.nextInt(36)],
].join();

const _deadline = ProviderUnavailable(
  'claude',
  'The isolated usage read exceeded its deadline.',
);
const _unsupported = ProviderUnavailable(
  'claude',
  'The experimental usage getter is unavailable or unsupported.',
);

/// Why a control request got no answer it can use.
final class _Unsupported implements Exception {
  const _Unsupported();
}

/// Claude's limits, read with the native `claude` at [path] in [cwd]
/// within [bounds]: its initialization answered within the bound's
/// initialize step, then the usage within its request step, normalized.
/// [environment] is the one laid out for `claude`, chord's own unless given.
Future<ProviderLimits> collectClaudeResources(
  String path, {
  required String cwd,
  required CancellationToken cancelled,
  CollectorBounds bounds = collectorBounds,
  Map<String, String>? environment,
}) => withResourceProcess(
  [path, ...claudeUsageArgs],
  cwd: cwd,
  cancelled: cancelled,
  bounds: bounds,
  env: claudeUsageEnvironment(environment ?? Platform.environment),
  ownEnvironment: true,
  read: (group, within, _) async {
    final pending = <String, Completer<Object?>>{};
    var bytes = 0;
    Object? failure;
    void fail(Object error) {
      failure ??= error;
      for (final waiting in pending.values) {
        if (!waiting.isCompleted) waiting.completeError(error);
      }
      pending.clear();
    }

    void heard(String line) {
      final Object? message;
      try {
        message = jsonDecode(line);
      } on FormatException {
        return fail(const _Unsupported());
      }
      if (message is! Map ||
          message['type'] != 'control_response' ||
          message['response'] is! Map) {
        return;
      }
      final response = message['response'] as Map;
      final waiting = pending.remove(response['request_id']);
      if (waiting == null) return;
      if (response['subtype'] == 'success') {
        waiting.complete(response['response']);
      } else {
        waiting.completeError(const _Unsupported());
      }
    }

    final lines = StreamController<List<int>>(sync: true);
    lines.stream
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(heard, onError: (_) => fail(const _Unsupported()));
    group.stdout.listen(
      (chunk) {
        bytes += chunk.length;
        // Every byte counts, of any line, so a flood of short lines trips
        // it as one long line does.
        if (bytes > claudeOutputBound) {
          fail(
            const ResourceReadError(
              'protocol',
              'The isolated worker result exceeds its output bound.',
            ),
          );
          lines.close().ignore();
          return;
        }
        lines.add(chunk);
      },
      onDone: () {
        lines.close().ignore();
        fail(const _Unsupported());
      },
      onError: (_) {},
      cancelOnError: false,
    );

    Future<Object?> ask(Map<String, Object?> request, Duration limit) {
      final id = _requestId();
      final answer = Completer<Object?>();
      if (failure != null) return Future.error(failure!);
      pending[id] = answer;
      try {
        group.stdin.add(
          utf8.encode(
            '${jsonEncode({'request_id': id, 'type': 'control_request', 'request': request})}\n',
          ),
        );
      } on StateError {
        fail(const _Unsupported());
      }
      return resourceStep(answer.future, within, limit);
    }

    try {
      await ask({
        'subtype': 'initialize',
        'systemPrompt': [''],
      }, bounds.initialize);
      final usage = await ask({
        'subtype': 'get_usage',
        'skip_behaviors': true,
      }, bounds.request);
      return normalizeClaude(usage);
    } on ResourceReadError {
      rethrow;
    } on TimeoutException {
      return _deadline;
    } on _Unsupported {
      return _unsupported;
    }
  },
);
