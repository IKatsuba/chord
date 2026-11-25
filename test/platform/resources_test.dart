// The window's limits read, as the original's tests/platform/resources_test.ts
// reads it, but for the real process group's close, which comes with the
// readers.
import 'dart:async';

import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/platform/resources.dart';
import 'package:chord/session/budgets.dart';
import 'package:chord/session/resource_access.dart';
import 'package:test/test.dart';

const LimitsPlace _place = (cwd: '/fixture/project', commandOf: _none);

Object? _none(String _) => null;

typedef _Read =
    Future<ProviderLimits> Function(
      String provider,
      String path,
      String cwd,
      CancellationToken cancelled,
    );

final class _Readers implements ResourceCollectors {
  _Readers(this.calls, [_Read? read])
    : _read =
          read ??
          ((provider, _, _, _) => Future.value(
            ProviderWindows(provider, const [
              (
                name: 'primary',
                usedPercent: 0,
                windowSeconds: 18000,
                resetsAt: null,
                models: null,
              ),
            ]),
          ));

  final List<String> calls;
  final _Read _read;

  @override
  Future<ResourceExecutable> resolve(
    String provider,
    String cwd,
    bool customCommand,
    CancellationToken cancelled,
  ) {
    calls.add('resolve:$provider:$cwd');
    return Future.value(
      customCommand
          ? const ExecutableUnavailable(
              'Custom command association is unverified.',
            )
          : const ExecutableFound('/fixture/provider', '1'),
    );
  }

  @override
  Future<ProviderLimits> read(
    String provider,
    String path,
    String cwd,
    CancellationToken cancelled,
  ) {
    calls.add('read:$provider:$cwd');
    return _read(provider, path, cwd, cancelled);
  }
}

/// A future that settles only once [cancelled] is.
Future<T> _untilCancelled<T>(CancellationToken cancelled) =>
    Completer<T>().future.asCancellable(cancelled);

void main() {
  group('CTUI-37 tester: independent resource ownership', () {
    test(
      'cancelling one concurrent read leaves the other independent',
      () async {
        final callers = [CancellationToken(), CancellationToken()];
        final tokens = <CancellationToken>[];
        final answers = <Completer<ProviderLimits>>[];
        final resources = createResources(
          GivenCollectors(
            _Readers([], (_, _, _, token) {
              tokens.add(token);
              final answer = Completer<ProviderLimits>();
              answers.add(answer);
              return answer.future;
            }),
          ),
        );
        addTearDown(() async {
          for (final answer in answers) {
            if (!answer.isCompleted) {
              answer.complete(const ProviderWindows('codex', []));
            }
          }
          await resources.close();
        });
        final first = resources.read(['codex'], _place, callers[0]);
        final second = resources.read(['codex'], _place, callers[1]);
        for (var i = 0; i < 100 && answers.length < 2; i++) {
          await Future<void>.delayed(const Duration(milliseconds: 1));
        }
        expect(answers, hasLength(2));
        final rejected = expectLater(first, throwsA(isA<CancelledException>()));
        callers[0].cancel();
        await rejected;
        expect(tokens[0].isCancelled, isTrue);
        expect(tokens[1].isCancelled, isFalse);
        answers[1].complete(const ProviderWindows('codex', []));
        expect((await second).providers.single, isA<ProviderWindows>());
        answers[0].complete(const ProviderUnavailable('codex', 'late answer'));
        expect(await resources.close(), isEmpty);
      },
    );

    test('close also waits for a read admitted during older cleanup', () async {
      final answers = <Completer<ProviderLimits>>[];
      final resources = createResources(
        GivenCollectors(
          _Readers([], (_, _, _, _) {
            final answer = Completer<ProviderLimits>();
            answers.add(answer);
            return answer.future;
          }),
        ),
        timeout: const Duration(milliseconds: 50),
      );
      addTearDown(() async {
        for (final answer in answers) {
          if (!answer.isCompleted) {
            answer.complete(const ProviderWindows('codex', []));
          }
        }
        await resources.close();
      });
      await resources.read(['codex'], _place, CancellationToken());
      var closed = false;
      final closing = resources.close().then((value) {
        closed = true;
        return value;
      });
      final next = resources.read(['codex'], _place, CancellationToken());
      for (var i = 0; i < 100 && answers.length < 2; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      expect(answers, hasLength(2));
      answers.first.completeError(
        const ResourceReadError('cleanup', 'first cleanup'),
      );
      await Future<void>.delayed(Duration.zero);
      expect(closed, isFalse);
      answers.last.complete(const ProviderWindows('codex', []));
      await next;
      expect(await closing, ['first cleanup']);
    });
  });

  test('omitted agents read claude and codex in parallel, each in the '
      'place', () async {
    final calls = <String>[];
    final read = createResources(GivenCollectors(_Readers(calls))).read;
    final answer = await read(null, _place, CancellationToken());
    expect(DateTime.tryParse(answer.readAt), isNotNull);
    expect(answer.readAt, matches(RegExp(r'\.\d{3}Z$')));
    expect([for (final p in answer.providers) p.agent], ['claude', 'codex']);
    expect(answer.providers[1].toJson(), {
      'agent': 'codex',
      'windows': [
        {
          'name': 'primary',
          'usedPercent': 0,
          'windowSeconds': 18000,
          'resetsAt': null,
          'models': null,
        },
      ],
    });
    expect(calls..sort(), [
      'read:claude:/fixture/project',
      'read:codex:/fixture/project',
      'resolve:claude:/fixture/project',
      'resolve:codex:/fixture/project',
    ]);
  });

  test('a filter reads only its agents once each; [] reads none; others '
      'have no reader', () async {
    final calls = <String>[];
    final read = createResources(GivenCollectors(_Readers(calls))).read;
    expect((await read([], _place, CancellationToken())).providers, isEmpty);
    final answer = await read(
      ['other', 'codex', 'codex'],
      _place,
      CancellationToken(),
    );
    expect(
      [
        for (final p in answer.providers)
          switch (p) {
            ProviderUnavailable(:final agent, :final unavailable) => [
              agent,
              unavailable,
            ],
            ProviderWindows(:final agent) => [agent],
          },
      ],
      [
        ['other', 'No limits reader for this runtime.'],
        ['codex'],
      ],
    );
    expect(calls, [
      'resolve:codex:/fixture/project',
      'read:codex:/fixture/project',
    ]);
  });

  test('a custom ACP command is unavailable without a provider read', () async {
    final calls = <String>[];
    final read = createResources(GivenCollectors(_Readers(calls))).read;
    final answer = await read(
      ['codex'],
      (cwd: '/fixture/project', commandOf: (_) => ['custom-acp']),
      CancellationToken(),
    );
    expect(
      [for (final p in answer.providers) p.toJson()],
      [
        {
          'agent': 'codex',
          'unavailable': 'Custom command association is unverified.',
        },
      ],
    );
    expect(calls, ['resolve:codex:/fixture/project']);
  });

  test('a provider past the timeout is reported and the others still '
      'answer', () async {
    final read = createResources(
      GivenCollectors(
        _Readers(
          [],
          (provider, _, _, cancelled) => provider == 'claude'
              ? _untilCancelled(cancelled)
              : Future.value(const ProviderWindows('codex', [])),
        ),
      ),
      timeout: const Duration(milliseconds: 50),
    ).read;
    final answer = await read(null, _place, CancellationToken());
    expect(
      [for (final p in answer.providers) p.toJson()],
      [
        {'agent': 'claude', 'unavailable': 'Timed out after 0.05 s.'},
        {'agent': 'codex', 'windows': <Object?>[]},
      ],
    );
  });

  test('a reader failure says its fixed reason; anything else a plain '
      'one', () async {
    final read = createResources(
      GivenCollectors(
        _Readers(
          [],
          (provider, _, _, _) => Future.error(
            provider == 'claude'
                ? const ResourceReadError('protocol', 'The worker failed.')
                : StateError('private detail'),
          ),
        ),
      ),
    ).read;
    final answer = await read(null, _place, CancellationToken());
    expect(
      [for (final p in answer.providers) p.toJson()],
      [
        {'agent': 'claude', 'unavailable': 'The worker failed.'},
        {'agent': 'codex', 'unavailable': 'The limits could not be read.'},
      ],
    );
  });

  test("the caller's cancellation rejects the read", () async {
    final caller = CancellationToken();
    final read = createResources(
      GivenCollectors(
        _Readers([], (_, _, _, cancelled) {
          caller.cancel(const CancelledException(cancellationReason: 'x'));
          return _untilCancelled(cancelled);
        }),
      ),
    ).read;
    await expectLater(
      read(['codex'], _place, caller),
      throwsA(isA<CancelledException>()),
    );
  });

  test('fixture mode never resolves installed providers, even for claude '
      'and codex', () async {
    final read = createResources(const FixtureCollectors()).read;
    final answer = await read(null, (
      cwd: '/fixture/project',
      commandOf: (_) => 'never-launch-this-wrapper',
    ), CancellationToken());
    expect(
      [
        for (final p in answer.providers)
          (p as ProviderWindows).windows.first.usedPercent,
      ],
      [12.345, 12.345],
    );
  });

  test('close waits for a reader still cleaning up past its timeout, and '
      'reports its cleanup failure', () async {
    final cleaned = Completer<void>();
    var closed = false;
    final resources = createResources(
      GivenCollectors(
        _Readers([], (_, _, _, cancelled) {
          final done = Completer<ProviderLimits>();
          // Past its deadline, it still cleans up before it settles.
          Timer.periodic(const Duration(milliseconds: 5), (timer) {
            if (!cancelled.isCancelled) return;
            timer.cancel();
            cleaned.future.then(
              (_) => done.completeError(
                const ResourceReadError(
                  'cleanup',
                  'Owned group exit unverified.',
                ),
              ),
            );
          });
          return done.future;
        }),
      ),
      timeout: const Duration(milliseconds: 50),
    );
    expect(
      [
        for (final p in (await resources.read(
          ['codex'],
          _place,
          CancellationToken(),
        )).providers)
          p.toJson(),
      ],
      [
        {'agent': 'codex', 'unavailable': 'Timed out after 0.05 s.'},
      ],
    );
    final closing = resources.close().then((failures) {
      closed = true;
      return failures;
    });
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(closed, isFalse);
    cleaned.complete();
    expect(await closing, ['Owned group exit unverified.']);
  });

  test('the official readers are reached only by an official window', () async {
    final calls = <String>[];
    final before = officialCollectors;
    officialCollectors = _Readers(calls);
    addTearDown(() => officialCollectors = before);
    await createResources(
      const FixtureCollectors(),
    ).read(null, _place, CancellationToken());
    expect(calls, isEmpty);
    await createResources(
      const OfficialCollectors(),
    ).read(['codex'], _place, CancellationToken());
    expect(calls, [
      'resolve:codex:/fixture/project',
      'read:codex:/fixture/project',
    ]);
  });

  test('a launch built for captures reads the fixture case its '
      'environment names; any other launch the official readers', () {
    expect(
      launchCollectors('true', const {'CHORD_FAKE_RESOURCE_CASE': 'partial'}),
      isA<FixtureCollectors>().having((c) => c.fixtureCase, 'case', 'partial'),
    );
    expect(
      launchCollectors('true', const {}),
      isA<FixtureCollectors>().having((c) => c.fixtureCase, 'case', 'normal'),
    );
    expect(
      launchCollectors('', const {'CHORD_FAKE_RESOURCE_CASE': 'partial'}),
      isA<OfficialCollectors>(),
    );
  });
}
