import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/input/wheel.dart';
import 'package:test/test.dart';

MouseEvent _wheel(
  int dy, {
  int x = 3,
  int y = 4,
  int dx = 0,
  bool ctrl = false,
}) => MouseEvent(
  MouseEventKind.wheel,
  position: Offset(x, y),
  scrollDelta: Offset(dx, dy),
  ctrl: ctrl,
);

String _describe(InputEvent e) => switch (e) {
  MouseEvent() =>
    '${e.kind.name}@${e.position.x},${e.position.y}'
        ' ${e.scrollDelta.x},${e.scrollDelta.y}${e.ctrl ? ' ctrl' : ''}',
  KeyEvent() => 'key ${e.combo}',
  _ => '$e',
};

void main() {
  test('a run of same-cell same-direction wheel reports becomes one', () {
    final merged = coalesceWheel([_wheel(1), _wheel(1), _wheel(1)]);
    expect(merged.map(_describe), ['wheel@3,4 0,3']);
    expect(coalesceWheel([_wheel(-1), _wheel(-1)]).map(_describe), [
      'wheel@3,4 0,-2',
    ]);
    expect(coalesceWheel([_wheel(0, dx: 1), _wheel(0, dx: 1)]).map(_describe), [
      'wheel@3,4 2,0',
    ]);
  });

  test(
    'cell, modifiers, direction and anything between keep reports apart',
    () {
      final events = <InputEvent>[
        _wheel(1),
        _wheel(-1),
        _wheel(-1, x: 5),
        _wheel(-1, x: 5, ctrl: true),
        _wheel(0, x: 5, ctrl: true, dx: -1),
        _wheel(1),
        KeyEvent('a'),
        _wheel(1),
        const MouseEvent(
          MouseEventKind.press,
          position: Offset(3, 4),
          button: MouseButton.primary,
        ),
        _wheel(1),
        _wheel(1),
      ];
      expect(coalesceWheel(events).map(_describe), [
        'wheel@3,4 0,1',
        'wheel@3,4 0,-1',
        'wheel@5,4 0,-1',
        'wheel@5,4 0,-1 ctrl',
        'wheel@5,4 -1,0 ctrl',
        'wheel@3,4 0,1',
        'key a',
        'wheel@3,4 0,1',
        'press@3,4 0,0',
        'wheel@3,4 0,2',
      ]);
    },
  );

  test('nothing to merge returns the same list', () {
    final events = <InputEvent>[_wheel(1), KeyEvent('a'), _wheel(1)];
    expect(coalesceWheel(events), same(events));
    final one = <InputEvent>[_wheel(1)];
    expect(coalesceWheel(one), same(one));
  });
}
