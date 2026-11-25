import 'package:chord/acp/schema.dart' as acp;
import 'package:chord/session/cycles.dart';
import 'package:test/test.dart';

acp.SessionUpdate _usage([Map<String, Object?>? meta]) =>
    acp.SessionUpdate.fromJson({
      'sessionUpdate': 'usage_update',
      'used': 1,
      'size': 2,
      '_meta': ?meta,
    });

void main() {
  test("Claude's cycle ends on a usage update of an autonomous origin, and "
      'no other', () {
    for (final kind in [
      'task-notification',
      'peer',
      'coordinator',
      'observer',
      'observer-activity',
    ]) {
      expect(
        cycleMark(
          _usage({
            '_claude/origin': {'kind': kind},
          }),
        ),
        CycleMark.end,
      );
    }
    for (final kind in [
      'human',
      'channel',
      'auto-continuation',
      'unclassified',
    ]) {
      expect(
        cycleMark(
          _usage({
            '_claude/origin': {'kind': kind},
          }),
        ),
        isNull,
      );
    }
    expect(cycleMark(_usage()), isNull);
    expect(cycleMark(_usage({'_claude/origin': 'task-notification'})), isNull);
  });

  test("codebuddy's unasked turn starts on its marker and ends on "
      'session_end', () {
    expect(
      cycleMark(
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'session_info_update',
          '_meta': {
            'codebuddy.ai/unsolicitedTurn': {
              'requestId': 'r',
              'reason': 'background_drain',
            },
          },
        }),
      ),
      CycleMark.start,
    );
    expect(
      cycleMark(
        acp.SessionUpdate.fromJson({'sessionUpdate': 'session_info_update'}),
      ),
      isNull,
    );
    expect(
      cycleMark(acp.SessionUpdate.fromJson({'sessionUpdate': 'session_end'})),
      CycleMark.end,
    );
    expect(
      cycleMark(
        acp.SessionUpdate.fromJson({
          'sessionUpdate': 'agent_message_chunk',
          'content': {'type': 'text', 'text': 'hi'},
        }),
      ),
      isNull,
    );
  });
}
