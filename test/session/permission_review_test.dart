import 'package:chord/session/permission_review.dart';
import 'package:test/test.dart';

Map<String, Object?> _described(PermissionPresentation p) => {
  if (p.review case final review?)
    'review': {'outcome': review.outcome, 'reason': review.reason},
  'deadlineAt': ?p.deadlineAt,
};

void main() {
  test('permission presentation validates independent optional fields for '
      'any agent', () {
    expect(
      _described(
        permissionPresentation({
          'chord/permission': {
            'review': {'outcome': 'caution', 'reason': 'rationale'},
            'deadlineAt': 1234,
          },
        }),
      ),
      {
        'review': {'outcome': 'caution', 'reason': 'rationale'},
        'deadlineAt': 1234,
      },
    );
    expect(
      _described(
        permissionPresentation({
          'chord/permission': {
            'review': {'outcome': 'invented', 'reason': 'rationale'},
            'deadlineAt': 1234,
          },
        }),
      ),
      {'deadlineAt': 1234},
    );
    expect(
      _described(
        permissionPresentation({
          'chord/permission': {
            'review': {'outcome': 'failed', 'reason': 'unavailable'},
            'deadlineAt': -1,
          },
        }),
      ),
      {
        'review': {'outcome': 'failed', 'reason': 'unavailable'},
      },
    );

    for (final meta in [
      null,
      <String, Object?>{},
      {'chord/permission': 'invalid'},
    ]) {
      expect(_described(permissionPresentation(meta)), isEmpty);
    }
  });

  test('a review missing its reason, or a deadline that is no finite '
      'number, is none', () {
    for (final value in <Object?>[
      {
        'review': {'outcome': 'caution'},
        'deadlineAt': 'soon',
      },
      {
        'review': {'outcome': 'caution', 'reason': 3},
        'deadlineAt': double.infinity,
      },
      {'review': 'caution', 'deadlineAt': double.nan},
    ]) {
      expect(
        _described(permissionPresentation({'chord/permission': value})),
        isEmpty,
      );
    }
  });

  test("a deadline is carried as the agent's number, fractions and floats "
      'included', () {
    for (final deadline in <num>[1700000000000.5, 1700000000000.0, 1e300, 0]) {
      final read = permissionPresentation({
        'chord/permission': {'deadlineAt': deadline},
      }).deadlineAt;

      expect(read, deadline);
      expect(read.runtimeType, deadline.runtimeType);
    }
  });

  group('tester: permission presentation boundaries', () {
    test(
      'finite numeric extremes are preserved without integer conversion',
      () {
        for (final deadline in <num>[
          0.0,
          0.5,
          double.minPositive,
          1700000000000.5,
          1e300,
          double.maxFinite,
        ]) {
          final result = permissionPresentation({
            'chord/permission': {'deadlineAt': deadline},
          });
          expect(result.deadlineAt, deadline);
          expect(result.deadlineAt.runtimeType, deadline.runtimeType);
        }
      },
    );
    test(
      'all review outcomes preserve literal reasons and a zero deadline',
      () {
        for (final outcome in ['caution', 'incomplete', 'failed']) {
          for (final reason in ['', '界 e\u0301 👩‍💻\n\x1b[31mreason']) {
            final result = permissionPresentation({
              'chord/permission': {
                'review': {'outcome': outcome, 'reason': reason, 'extra': true},
                'deadlineAt': 0,
              },
            });
            expect(result.review!.outcome, outcome);
            expect(result.review!.reason, reason);
            expect(result.deadlineAt, 0);
          }
        }
      },
    );

    test('invalid deadlines do not discard an otherwise valid review', () {
      for (final deadline in <Object?>[
        null,
        -1,
        double.negativeInfinity,
        double.nan,
        true,
        '0',
        [],
        {},
      ]) {
        final result = permissionPresentation({
          'chord/permission': {
            'review': {'outcome': 'incomplete', 'reason': 'kept'},
            'deadlineAt': deadline,
          },
        });
        expect(result.deadlineAt, isNull);
        expect(result.review!.reason, 'kept');
      }
    });
  });
}
