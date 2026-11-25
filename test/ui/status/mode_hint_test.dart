import 'package:chord/ui/status/status.dart';
import 'package:test/test.dart';

void main() {
  test('mode wins over shortcut hint and names the active cycle key', () {
    final line = statusLine(
      const StatusFacts(
        mode: 'acceptEdits',
        hint: '? for shortcuts',
        cycleKey: 'shift+tab',
      ),
      120,
    );
    expect(line.left.map((part) => part.text), [
      '⏵⏵ accept edits on',
      '(shift+tab to cycle)',
    ]);
    expect(line.left.first.tone, StatusTone.edits);
    expect(
      statusLine(
        const StatusFacts(
          mode: 'default',
          hint: '? for shortcuts',
          cycleKey: 'shift+tab',
        ),
        120,
      ).left.single.text,
      '? for shortcuts',
    );
  });
  test(
    'cycle hint drops before cutting a model and real notices still win',
    () {
      final model = 'm' * 60;
      final line = statusLine(
        StatusFacts(
          mode: 'plan',
          model: model,
          hint: '? for shortcuts',
          cycleKey: 'shift+tab',
        ),
        90,
      );
      expect(line.left.map((part) => part.text), ['⏸ plan mode on']);
      expect(line.right.single.text, model);
      final notice = statusLine(
        const StatusFacts(
          mode: 'plan',
          notice: 'press ctrl+c again',
          hint: '? for shortcuts',
          cycleKey: 'shift+tab',
        ),
        120,
      );
      expect(notice.left.single.text, 'press ctrl+c again');
      expect(
        statusLine(const StatusFacts(mode: 'plan'), 120).left,
        hasLength(1),
      );
    },
  );
}
