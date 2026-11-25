// Original permission_test.ts: settled permissionOutcome cases only.
// Active requests, choices, reviews and request rows belong to CTUI-18.
import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/permission.dart';
import 'package:test/test.dart';

void main() {
  test('settled permissions name the call and chosen allow option', () {
    for (final kind in [
      'allow_once',
      'allow_always',
      'reject_once',
      'reject_always',
    ]) {
      final option = acp.PermissionOption.fromJson({
        'optionId': 'x',
        'name': 'choice',
        'kind': kind,
      });
      final result = permissionOutcome(
        PermissionEntry('a', title: 'Run', option: option),
      );
      expect(result.allowed, kind.startsWith('allow'));
      expect(
        result.text,
        kind.startsWith('allow') ? 'Allowed Run · choice' : 'Rejected Run',
      );
    }
    expect(
      permissionOutcome(const PermissionEntry('a')).text,
      'Rejected the tool call',
    );
  });
}
