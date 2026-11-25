import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/testing.dart';
import 'package:test/test.dart';

void main() {
  for (final count in [2000, 10000]) {
    testWidgets('Picker retains current extents and visible states for $count', (
      t,
    ) async {
      final probe = _LiveChoices();
      final observations = <Map<String, int>>[];
      await t.pumpWidget(
        Picker<int>(
          items: [
            for (var i = 0; i < count; i++)
              PickerItem(value: i, label: 'Choice $i'),
          ],
          initialValue: count ~/ 2,
          maxVisibleRows: 8,
          showNumbers: false,
          itemExtentVersion: 0,
          itemExtentBuilder: (_, positions, width) => width < 100 ? 2 : 1,
          itemBuilder: (_, item, positions) =>
              _TrackedChoice(probe, item.value),
          onSelected: (_) {},
          onCanceled: () {},
        ),
        size: const Size(120, 40),
      );
      ItemExtents? firstExtents;
      for (var cycle = 0; cycle < 8; cycle++) {
        for (final size in [
          const Size(120, 40),
          const Size(80, 24),
          const Size(32, 10),
        ]) {
          await t.resize(size);
          await t.press('down up');
          final viewports = <RenderListViewport>[];
          void visit(Element element) {
            if (element is RenderObjectElement &&
                element.renderObject is RenderListViewport) {
              viewports.add(element.renderObject as RenderListViewport);
            }
            element.visitChildren(visit);
          }

          visit(t.host.rootElement);
          expect(viewports, hasLength(1));
          final viewport = viewports.single;
          firstExtents ??= viewport.extents;
          expect(viewport.extents, same(firstExtents));
          expect(viewport.extents.length, count);
          expect(viewport.manager.builtIndices.length, lessThanOrEqualTo(8));
          expect(viewport.placedItems.length, lessThanOrEqualTo(8));
          expect(probe.alive.length, lessThanOrEqualTo(8));
          expect(viewport.extents.total, count * (size.width < 100 ? 2 : 1));
          observations.add({
            'cycle': cycle,
            'width': size.width,
            'height': size.height,
            'extentCount': viewport.extents.length,
            'mountedItems': viewport.manager.builtIndices.length,
            'placedItems': viewport.placedItems.length,
            'liveItemStates': probe.alive.length,
          });
        }
      }
      expect(probe.maximum, lessThanOrEqualTo(16));
      await t.pumpWidget(const SizedBox());
      expect(probe.alive, isEmpty);
      print(
        'RETENTION ${jsonEncode({'choices': count, 'observations': observations, 'peakLiveItemStates': probe.maximum, 'liveItemStatesAfterUnmount': probe.alive.length})}',
      );
    });
  }
}

class _LiveChoices {
  final alive = <int>{};
  var maximum = 0;
}

class _TrackedChoice extends StatefulWidget {
  const _TrackedChoice(this.probe, this.index);
  final _LiveChoices probe;
  final int index;
  @override
  State<_TrackedChoice> createState() => _TrackedChoiceState();
}

class _TrackedChoiceState extends State<_TrackedChoice> {
  @override
  void initState() {
    super.initState();
    widget.probe.alive.add(widget.index);
    if (widget.probe.alive.length > widget.probe.maximum) {
      widget.probe.maximum = widget.probe.alive.length;
    }
  }

  @override
  void dispose() {
    widget.probe.alive.remove(widget.index);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (_, room) => Text(
      'Choice ${widget.index}${room.maxWidth < 100 ? '\ncontinued' : ''}',
    ),
  );
}
