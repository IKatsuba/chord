/// Measures Picker geometry and input without a terminal or external process.
/// Run with --count=2000 or --count=10000, --kind=default|exact|fallback,
/// --runtime=jit|aot and `--source=<commit>`. Fallback is a labelled control.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:chord_tui/chord_tui.dart';

Future<void> main(List<String> args) async {
  String option(String name, String fallback) =>
      args
          .where((arg) => arg.startsWith('--$name='))
          .map((arg) => arg.substring(name.length + 3))
          .firstOrNull ??
      fallback;
  final count = int.parse(option('count', '2000'));
  final samples = int.parse(option('samples', '50'));
  final repetitions = int.parse(option('repetitions', '3'));
  final kind = option('kind', 'exact');
  if (count < 2 ||
      samples < 2 ||
      repetitions < 1 ||
      !['default', 'exact', 'fallback'].contains(kind)) {
    throw ArgumentError(
      'Use count/samples >= 2 and kind default, exact or fallback.',
    );
  }
  final counters = _Counters();
  final items = _Items([
    for (var i = 0; i < count; i++)
      PickerItem(
        value: i,
        label: kind == 'default'
            ? 'Choice $i'
            : 'Choice $i 界 café ${'wrapped words ' * (i % 4 + 2)}'
                  '${i % 17 == 0 ? '\n${'tall choice\n' * 12}last line' : ''}',
      ),
  ], counters);
  final reports = <Object>[];
  for (final (repetition, initial) in [
    for (var repeat = 0; repeat < repetitions; repeat++)
      for (final initial in [0, count ~/ 2, count - 1]) (repeat, initial),
  ]) {
    var accepted = -1;
    final filter = _Filter(counters);
    final host = AppHost(
      Picker<int>(
        items: items,
        initialValue: initial,
        maxVisibleRows: 8,
        searchable: true,
        filter: filter,
        itemExtentVersion: kind == 'exact' ? 0 : null,
        itemExtentBuilder: kind == 'exact'
            ? (item, positions, width) {
                counters.projections++;
                return TextLayout.compute(
                  TextSpan(item.label),
                  maxWidth: width,
                ).height;
              }
            : null,
        itemBuilder: kind == 'default'
            ? null
            : (_, item, positions) {
                counters.builds++;
                return _LayoutProbe(counters, child: Text(item.label));
              },
        onSelected: (value) {
          accepted = value;
        },
        onCanceled: () {},
      ),
    );
    var size = const Size(120, 40);
    Map<String, Object> stage(String name, void Function() action) {
      counters.clear();
      final watch = Stopwatch()..start();
      action();
      return {
        'stage': name,
        'ms': watch.elapsedMicroseconds / 1000,
        'counters': counters.json(),
        'rssBytes': ProcessInfo.currentRss,
      };
    }

    final stages = <Object>[];
    try {
      stages.add(
        stage('first120x40', () {
          host.drawFrame(size);
        }),
      );
      stages.add(
        stage('coldResize80x24', () {
          size = const Size(80, 24);
          host.drawFrame(size);
        }),
      );
      stages.add(
        stage('returnResize120x40', () {
          size = const Size(120, 40);
          host.drawFrame(size);
        }),
      );
      counters.clear();
      final unchanged = <double>[];
      for (var i = 0; i < samples; i++) {
        final watch = Stopwatch()..start();
        host.drawFrame(size);
        unchanged.add(watch.elapsedMicroseconds / 1000);
      }
      stages.add({
        'stage': 'unchanged',
        'timingMs': _distribution(unchanged),
        'counters': counters.json(),
      });
      final dispatch = <double>[], redraw = <double>[], delays = <double>[];
      counters.clear();
      final beforeInputRss = ProcessInfo.currentRss;
      for (var i = 0; i < samples; i++) {
        // Schedule before yielding; delay includes the requested 16 ms wait.
        final scheduled = Stopwatch()..start();
        final done = Completer<void>();
        Timer(const Duration(milliseconds: 16), () {
          try {
            final direction = initial == count - 1 ? -1 : 1;
            final step = i.isEven ? direction : -direction;
            final watch = Stopwatch()..start();
            host.handleKey(KeyEvent(step > 0 ? 'down' : 'up'));
            dispatch.add(watch.elapsedMicroseconds / 1000);
            watch.reset();
            host.drawFrame(size);
            redraw.add(watch.elapsedMicroseconds / 1000);
            accepted = -1;
            host.handleKey(const KeyEvent('enter'));
            delays.add(scheduled.elapsedMicroseconds / 1000);
            if (accepted < 0 || accepted >= count) {
              throw StateError('Input did not accept a current choice.');
            }
            done.complete();
          } catch (error, stack) {
            done.completeError(error, stack);
          }
        });
        await done.future;
      }
      if (kind != 'fallback' &&
          (counters.projections != 0 || counters.filters != 0)) {
        throw StateError(
          'Stable navigation repeated scalar projection or filtering.',
        );
      }
      stages.add({
        'stage': 'navigation',
        'dispatchMs': _distribution(dispatch),
        'redrawMs': _distribution(redraw),
        'scheduledToAcceptanceMs': _distribution(delays),
        'counters': counters.json(),
        'beforeRssBytes': beforeInputRss,
        'afterRssBytes': ProcessInfo.currentRss,
      });
    } finally {
      host.dispose();
    }
    reports.add({
      'repetition': repetition,
      'initialIndex': initial,
      'stages': stages,
    });
  }
  print(
    const JsonEncoder.withIndent('  ').convert({
      'sourceCommit': option('source', 'unspecified'),
      'runtimeLabel': option('runtime', 'unspecified'),
      'dartVersion': Platform.version.split(' ').first,
      'kind': kind,
      'choices': count,
      'samples': samples,
      'repetitions': repetitions,
      'maxVisibleRows': 8,
      'scheduledDelayMs': 16,
      'limits':
          'In-memory framework Picker; no scan, disk, agent, PTY or display. '
          'Cold width projects exact scalar heights O(N); widget work is viewport bounded. '
          'Default rows have no custom build/layout counters. Fallback retains full exact widget measurement. '
          'RSS and peak RSS are process observations, not isolated retained-heap measurements.',
      'reports': reports,
      'maxRssBytes': ProcessInfo.maxRss,
      'cleanup': {
        'hostsDisposed': reports.length,
        'pendingTimers': 0,
        'externalProcessesStarted': 0,
      },
    }),
  );
}

Map<String, Object> _distribution(List<double> samples) {
  final sorted = [...samples]..sort();
  double at(double q) => sorted[((sorted.length - 1) * q).round()];
  return {
    'samples': samples,
    'min': sorted.first,
    'median': at(.5),
    'p95': at(.95),
    'max': sorted.last,
  };
}

class _Counters {
  var projections = 0, builds = 0, layouts = 0, filters = 0, itemReads = 0;
  void clear() {
    projections = 0;
    builds = 0;
    layouts = 0;
    filters = 0;
    itemReads = 0;
  }

  Map<String, int> json() => {
    'projections': projections,
    'builds': builds,
    'layouts': layouts,
    'filters': filters,
    'itemReads': itemReads,
  };
}

class _Items extends ListBase<PickerItem<int>> {
  _Items(this.data, this.counters);
  final List<PickerItem<int>> data;
  final _Counters counters;
  @override
  int get length => data.length;
  @override
  set length(int value) => throw UnsupportedError('Immutable corpus');
  @override
  PickerItem<int> operator [](int index) {
    counters.itemReads++;
    return data[index];
  }

  @override
  void operator []=(int index, PickerItem<int> value) =>
      throw UnsupportedError('Immutable corpus');
}

class _Filter implements PickerFilter {
  _Filter(this.counters);
  final _Counters counters;
  @override
  List<PickerMatch> match(String query, List<String> labels) {
    counters.filters++;
    return const FzfPickerFilter().match(query, labels);
  }
}

class _LayoutProbe extends SingleChildRenderObjectWidget {
  const _LayoutProbe(this.counters, {required super.child});
  final _Counters counters;
  @override
  RenderBox createRenderObject(BuildContext context) => _LayoutBox(counters);
}

class _LayoutBox extends RenderBox with RenderWithChild {
  _LayoutBox(this.counters);
  final _Counters counters;
  @override
  void performLayout() {
    counters.layouts++;
    child!.layout(constraints);
    size = child!.size;
  }

  @override
  void paint(Canvas canvas, Offset origin) => paintChildren(canvas, origin);
}
