// Ask ids are UUIDs at their source, as the original's randomUUID(), so a
// task's asks relayed into its parent never collide with the parent's own
// or another task's.
import 'package:cancellation_token/cancellation_token.dart';
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/elicitations.dart';
import 'package:chord/session/permissions.dart';
import 'package:test/test.dart';

final _uuidV4 = RegExp(
  r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
);

String _firstPermission() {
  final bridge = PermissionBridge();
  late String id;
  bridge.subscribe((pending) => id = pending.id);
  bridge
      .handler(
        acp.RequestPermissionRequest.fromJson({
          'sessionId': 's',
          'toolCall': {'toolCallId': 't'},
          'options': [
            {'optionId': 'yes', 'name': 'Yes', 'kind': 'allow_once'},
          ],
        }),
        CancellationToken(),
      )
      .ignore();
  return id;
}

String _firstElicitation() {
  final bridge = ElicitationBridge();
  late String id;
  bridge.subscribe((pending) => id = pending.id);
  bridge.handler({
    'mode': 'form',
    'message': 'Name?',
    'requestedSchema': {'type': 'object', 'properties': {}},
  }, CancellationToken()).ignore();
  return id;
}

void main() {
  testerAskIdentityTests();
  test("two sources' first permissions have distinct UUID ids", () {
    final a = _firstPermission();
    final b = _firstPermission();
    expect(a, matches(_uuidV4));
    expect(b, matches(_uuidV4));
    expect(a, isNot(b));
  });

  test("two sources' first elicitations have distinct UUID ids", () {
    final a = _firstElicitation();
    final b = _firstElicitation();
    expect(a, matches(_uuidV4));
    expect(b, matches(_uuidV4));
    expect(a, isNot(b));
  });
}

void testerAskIdentityTests() {
  group('tester: UUID ask identity isolation', () {
    test(
      'mixed asks across three sources share no ids and settle independently',
      () async {
        final permissions = [for (var i = 0; i < 3; i++) PermissionBridge()];
        final forms = [for (var i = 0; i < 3; i++) ElicitationBridge()];
        final pendingPermissions = <PendingPermission>[];
        final pendingForms = <PendingElicitation>[];
        final permissionAnswers = <Future<acp.RequestPermissionResponse>>[];
        final formAnswers = <Future<Map<String, Object?>>>[];
        final tokens = <CancellationToken>[];
        addTearDown(() {
          for (final bridge in permissions) {
            bridge.close();
          }
          for (final bridge in forms) {
            bridge.close();
          }
        });
        for (var source = 0; source < 3; source++) {
          permissions[source].subscribe(pendingPermissions.add);
          forms[source].subscribe(pendingForms.add);
          for (var ask = 0; ask < 2; ask++) {
            final token = CancellationToken();
            tokens.add(token);
            permissionAnswers.add(
              permissions[source].handler(
                acp.RequestPermissionRequest.fromJson({
                  'sessionId': 'source-$source',
                  'toolCall': {'toolCallId': 'same-tool'},
                  'options': [
                    {'optionId': 'yes', 'name': 'Yes', 'kind': 'allow_once'},
                  ],
                }),
                token,
              ),
            );
            formAnswers.add(
              forms[source].handler({
                'mode': 'form',
                'message': 'Name?',
                'requestedSchema': {'type': 'object', 'properties': {}},
              }, token),
            );
          }
        }
        final ids = [
          ...pendingPermissions.map((request) => request.id),
          ...pendingForms.map((request) => request.id),
        ];
        expect(ids, everyElement(matches(_uuidV4)));
        expect(ids.toSet(), hasLength(12));
        tokens.first.cancel();
        expect((await permissionAnswers.first).toJson(), {
          'outcome': {'outcome': 'cancelled'},
        });
        expect(await formAnswers.first, {'action': 'cancel'});
        pendingPermissions.first.resolve('yes');
        pendingForms.first.answer(const AcceptReply({'stale': true}));
        for (var i = 1; i < 6; i++) {
          expect(pendingPermissions[i].withdrawn.isCancelled, isFalse);
          expect(pendingForms[i].withdrawn.isCancelled, isFalse);
          pendingPermissions[i].resolve('yes');
          pendingForms[i].answer(AcceptReply({'index': i}));
          expect((await permissionAnswers[i]).toJson(), {
            'outcome': {'outcome': 'selected', 'optionId': 'yes'},
          });
          expect(await formAnswers[i], {
            'action': 'accept',
            'content': {'index': i},
          });
        }
        expect(permissions.expand((bridge) => bridge.pending()), isEmpty);
      },
    );
  });
}
