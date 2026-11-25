import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/transcript/types.dart';
import 'package:chord/ui/dialogs/permission.dart';
import 'package:test/test.dart';

void main() {
  group('tester U4 settled permissions', () {
    test('unknown options reject without echoing their name', () {
      final result = permissionOutcome(
        PermissionEntry(
          'a',
          title: '',
          option: acp.PermissionOption.fromJson({
            'optionId': 'future',
            'kind': 'future_kind',
            'name': 'Unknown choice',
          }),
        ),
      );
      expect(result, (text: 'Rejected ', allowed: false));
    });

    test(
      'allow without a title uses fallback and keeps Unicode option name',
      () {
        final entry = PermissionEntry(
          'a',
          option: acp.PermissionOption.fromJson({
            'optionId': 'once',
            'kind': 'allow_once',
            'name': 'Allow 👩‍💻 e\u0301',
          }),
        );
        expect(permissionOutcome(entry), (
          text: 'Allowed the tool call · Allow 👩‍💻 e\u0301',
          allowed: true,
        ));
        expect(entry.title, isNull);
        expect(entry.option!.name, 'Allow 👩‍💻 e\u0301');
      },
    );
  });
}
