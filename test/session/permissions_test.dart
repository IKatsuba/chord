// The original's permissions_test.ts, the bridge, Esc's answer and the wait
// the transcript keeps. Left for later: allowing everything
// (`--dangerously-skip-permissions`) and chord's own save box.
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/permissions.dart';
import 'package:test/test.dart';

import 'transcript/fold.dart' show describedWait;

final _options = [
  for (final (id, name, kind) in [
    ('yes', 'Yes', 'allow_once'),
    ('always', 'Always', 'allow_always'),
    ('no', 'No', 'reject_once'),
  ])
    {'optionId': id, 'name': name, 'kind': kind},
];

acp.RequestPermissionRequest _request({
  Map<String, Object?> toolCall = const {'toolCallId': 't'},
  List<Map<String, Object?>>? options,
  Map<String, Object?>? meta,
}) => acp.RequestPermissionRequest.fromJson({
  'sessionId': 's',
  'toolCall': toolCall,
  'options': options ?? _options,
  '_meta': ?meta,
});

Future<acp.RequestPermissionResponse> _ask(
  PermissionBridge bridge, [
  CancellationToken? token,
  acp.RequestPermissionRequest? request,
]) => bridge.handler(request ?? _request(), token ?? CancellationToken());

/// The pending request [request] makes, as a bridge hands it out.
PendingPermission _pending(acp.RequestPermissionRequest request) {
  final bridge = PermissionBridge();
  late PendingPermission seen;

  bridge.subscribe((each) => seen = each);
  _ask(bridge, null, request).ignore();

  return seen;
}

const _cancelled = {
  'outcome': {'outcome': 'cancelled'},
};

void main() {
  test('an answer names the option by its id, never one the agent did not '
      'offer', () async {
    final bridge = PermissionBridge();
    late PendingPermission seen;

    bridge.subscribe((request) => seen = request);

    final decision = _ask(bridge);

    expect(() => seen.resolve('maybe'), throwsArgumentError);
    seen.resolve('always');
    expect((await decision).toJson(), {
      'outcome': {'outcome': 'selected', 'optionId': 'always'},
    });
  });

  test('Esc picks the reject option, reject once before always, else '
      'cancels', () {
    Map<String, Object?> reject(List<Map<String, Object?>> options) =>
        rejection([
          for (final each in options) acp.PermissionOption.fromJson(each),
        ]).toJson();

    expect(reject(_options), {
      'outcome': {'outcome': 'selected', 'optionId': 'no'},
    });
    expect(
      reject([
        ..._options.take(2),
        {'optionId': 'never', 'name': 'Never', 'kind': 'reject_always'},
        {'optionId': 'no', 'name': 'No', 'kind': 'reject_once'},
      ]),
      {
        'outcome': {'outcome': 'selected', 'optionId': 'no'},
      },
    );
    expect(
      reject([
        ..._options.take(2),
        {'optionId': 'never', 'name': 'Never', 'kind': 'reject_always'},
      ]),
      {
        'outcome': {'outcome': 'selected', 'optionId': 'never'},
      },
    );
    expect(reject(_options.take(2).toList()), _cancelled);
  });

  test('a request waits until the window answers it, and only the first '
      'answer counts', () async {
    final bridge = PermissionBridge();
    late PendingPermission seen;

    bridge.subscribe((request) => seen = request);

    final decision = _ask(bridge);

    expect(bridge.pending(), hasLength(1));
    expect(bridge.pending().single.id, seen.id);
    seen.resolve('yes');
    seen.reject();
    expect((await decision).toJson(), {
      'outcome': {'outcome': 'selected', 'optionId': 'yes'},
    });
    expect(bridge.pending(), isEmpty);
  });

  test('Esc answers the reject option, and the request is gone', () async {
    final bridge = PermissionBridge();
    late PendingPermission seen;

    bridge.subscribe((request) => seen = request);

    final decision = _ask(bridge);

    seen.reject();
    expect((await decision).toJson(), {
      'outcome': {'outcome': 'selected', 'optionId': 'no'},
    });
    expect(bridge.pending(), isEmpty);
  });

  test('a withdrawn request is cancelled, gone, and marked withdrawn for '
      'the window', () async {
    final bridge = PermissionBridge();
    final turn = CancellationToken();
    late PendingPermission seen;

    bridge.subscribe((request) => seen = request);

    final decision = _ask(bridge, turn);

    expect(seen.withdrawn.isCancelled, isFalse);
    turn.cancel();
    expect((await decision).toJson(), _cancelled);
    expect(bridge.pending(), isEmpty);
    expect(seen.withdrawn.isCancelled, isTrue);
    // An answer after the withdrawal goes nowhere.
    seen.resolve('yes');
  });

  test(
    'a request already withdrawn is answered cancelled and never shown',
    () async {
      final bridge = PermissionBridge();
      final seen = <PendingPermission>[];

      bridge.subscribe(seen.add);

      expect(
        (await _ask(bridge, CancellationToken()..cancel())).toJson(),
        _cancelled,
      );
      expect(seen, isEmpty);
      expect(bridge.pending(), isEmpty);
    },
  );

  test('closing the bridge cancels every waiting request', () async {
    final bridge = PermissionBridge();
    final decisions = [_ask(bridge), _ask(bridge)];

    expect(bridge.pending().map((p) => p.id).toSet(), hasLength(2));
    bridge.close();
    expect(
      [for (final each in await Future.wait(decisions)) each.toJson()],
      [_cancelled, _cancelled],
    );
    expect(bridge.pending(), isEmpty);
    // After the close, a new request is withdrawn at once.
    expect((await _ask(bridge)).toJson(), _cancelled);
  });

  test('an unsubscribed listener hears no new request', () {
    final bridge = PermissionBridge();
    final seen = <PendingPermission>[];
    final stop = bridge.subscribe(seen.add);

    _ask(bridge).ignore();
    stop();
    _ask(bridge).ignore();

    expect(seen, hasLength(1));
    expect(bridge.pending(), hasLength(2));
  });

  test('a request with no content keeps its raw input to be shown', () {
    const rawInput = {'command': 'tail -f dev.log'};

    expect(
      waitFor(
        _pending(
          _request(
            toolCall: {
              'toolCallId': 't',
              'title': 'mcp__chord__monitor',
              'rawInput': rawInput,
            },
          ),
        ),
      ).rawInput,
      rawInput,
    );
    expect(
      waitFor(
        _pending(
          _request(
            toolCall: {
              'toolCallId': 't',
              'content': <Object?>[],
              'rawInput': rawInput,
            },
          ),
        ),
      ).rawInput,
      rawInput,
    );
  });

  test('a request with content of its own keeps no raw input', () {
    final diff = {'type': 'diff', 'path': 'notes.txt', 'newText': 'hi'};
    final wait = waitFor(
      _pending(
        _request(
          toolCall: {
            'toolCallId': 't',
            'content': [diff],
            'rawInput': {'file_path': 'notes.txt', 'content': 'hi'},
          },
        ),
      ),
    );

    expect(wait.rawInput, isNull);
    expect(describedWait(wait)['content'], [diff]);
  });

  test("the wait keeps the call's facts, the agent's options and the "
      "review and deadline it carried, under the bridge's id", () {
    final request = _pending(
      _request(
        toolCall: {
          'toolCallId': 'write-4',
          'title': 'Write notes.txt',
          'kind': 'edit',
          'locations': [
            {'path': 'notes.txt', 'line': 2},
          ],
        },
        meta: {
          'chord/permission': {
            'review': {'outcome': 'caution', 'reason': 'writes outside'},
            'deadlineAt': 310000.5,
          },
        },
      ),
    );

    expect(describedWait(waitFor(request)), {
      'id': request.id,
      'toolCallId': 'write-4',
      'title': 'Write notes.txt',
      'kind': 'edit',
      'locations': [
        {'path': 'notes.txt', 'line': 2},
      ],
      'options': _options,
      'review': {'outcome': 'caution', 'reason': 'writes outside'},
      'deadlineAt': 310000.5,
    });
  });

  test('a field the agent sent malformed is left out of the wait, which '
      'can still be answered', () {
    final wait = waitFor(
      _pending(
        _request(
          toolCall: {
            'toolCallId': 't',
            'title': 3,
            'kind': '',
            'locations': [
              {'line': 1},
            ],
            'content': [
              {'type': 'diff', 'newText': 'n'},
            ],
            'rawInput': {'a': 1},
          },
        ),
      ),
    );

    expect(describedWait(wait), {
      'id': wait.id,
      'toolCallId': 't',
      'rawInput': {'a': 1},
      'options': _options,
    });
  });

  group('tester: permission bridge boundaries', () {
    test(
      'cancelling one concurrent request leaves the other answerable',
      () async {
        final bridge = PermissionBridge();
        addTearDown(bridge.close);
        final firstToken = CancellationToken();
        final seen = <PendingPermission>[];
        bridge.subscribe(seen.add);
        final first = _ask(bridge, firstToken);
        final second = _ask(bridge);
        final snapshot = bridge.pending();
        expect(snapshot.map((p) => p.id), seen.map((p) => p.id));
        firstToken.cancel();
        expect((await first).toJson(), _cancelled);
        expect(bridge.pending().single, same(seen[1]));
        expect(seen[0].withdrawn.isCancelled, isTrue);
        expect(seen[1].withdrawn.isCancelled, isFalse);
        seen[0].resolve('yes');
        seen[1].resolve('always');
        expect((await second).toJson(), {
          'outcome': {'outcome': 'selected', 'optionId': 'always'},
        });
        expect(bridge.pending(), isEmpty);
        expect(snapshot, hasLength(2));
      },
    );

    test(
      'a synchronous subscriber can answer before handler returns',
      () async {
        final bridge = PermissionBridge();
        addTearDown(bridge.close);
        bridge.subscribe((pending) {
          expect(bridge.pending().single, same(pending));
          pending.resolve('yes');
        });
        final token = CancellationToken();
        final result = _ask(bridge, token);
        expect(bridge.pending(), isEmpty);
        token.cancel();
        expect((await result).toJson(), {
          'outcome': {'outcome': 'selected', 'optionId': 'yes'},
        });
      },
    );

    test(
      'malformed optional content leaves valid locations and options answerable',
      () async {
        final bridge = PermissionBridge();
        addTearDown(bridge.close);
        final result = _ask(
          bridge,
          null,
          _request(
            toolCall: {
              'toolCallId': 'c',
              'title': '界 e\u0301 👩‍💻',
              'locations': [
                {'path': 'notes.txt', 'line': 1},
              ],
              'content': [
                {
                  'type': 'content',
                  'content': {'type': 'text', 'text': 'valid'},
                },
                {'type': 'diff', 'path': 'a', 'newText': 7},
              ],
              'rawInput': {'keep': true},
            },
          ),
        );
        final pending = bridge.pending().single;
        final wait = waitFor(pending);
        expect(wait.content, isNull);
        expect(wait.locations!.single.path, 'notes.txt');
        expect(wait.title, '界 e\u0301 👩‍💻');
        expect(wait.rawInput, {'keep': true});
        expect(wait.options.map((p) => p.optionId), ['yes', 'always', 'no']);
        expect(() => wait.options.clear(), throwsUnsupportedError);
        expect(() => wait.locations!.clear(), throwsUnsupportedError);
        pending.resolve('yes');
        expect((await result).toJson(), {
          'outcome': {'outcome': 'selected', 'optionId': 'yes'},
        });
      },
    );
  });
}
