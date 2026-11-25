/// Actual ResumePicker scale measurements, without filesystem or agent IO.
/// --count=20|2000|10000 --corpus=baseline|wrapped --runtime=aot --source=commit.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:chord/session/sessions.dart';
import 'package:chord/ui/pickers/picker.dart';
import 'package:chord/ui/pickers/pickers.dart';
import 'package:chord/ui/pickers/state.dart';
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
  final corpus = option('corpus', 'baseline');
  if (count < 8 ||
      samples < 2 ||
      repetitions < 1 ||
      !['baseline', 'wrapped'].contains(corpus)) {
    throw ArgumentError(
      'Use count >=8, samples >=2, repetitions >=1 and a known corpus.',
    );
  }
  final setup = Stopwatch()..start();
  final sessions = earlierSessions([
    for (var i = 0; i < count; i++)
      SessionRecord(
        path: 'fixture-records/$i.jsonl',
        sessionId: 'session-$i',
        agent: 'fake',
        cwd: '.',
        lastUsedAt: i + .25,
        prompt: corpus == 'baseline'
            ? 'Saved request $i 界😀'
            : 'Saved request $i 界😀 café é ${'wrapped title words ' * (i % 4 + 2)}'
                  '${i % 113 == 0 ? '\n${'tall title\n' * 12}last line' : ''}',
      ),
  ], agent: 'fake');
  final snapshot = ResumePickerState(
    sessions: sessions,
    cwd: '.',
    opening: 'benchmark',
    openedAt: count,
  );
  final setupMs = setup.elapsedMicroseconds / 1000;
  final reports = <Object>[];
  var disposed = 0;
  for (var repetition = 0; repetition < repetitions; repetition++) {
    AppHost? ownedHost;
    AppHost host() => ownedHost ?? (throw StateError('Host not constructed'));
    var selected = 0;
    var size = const Size(120, 40);
    final stages = <Object>[];
    Map<String, Object> census() {
      final views = <RenderListViewport>[];
      void visit(Element element) {
        if (element is RenderObjectElement &&
            element.renderObject is RenderListViewport) {
          views.add(element.renderObject as RenderListViewport);
        }
        element.visitChildren(visit);
      }

      visit(host().rootElement);
      if (views.length != 1) {
        throw StateError('Expected one actual resume list.');
      }
      final view = views.single;
      return {
        'extentCount': view.extents.length,
        'mountedItems': view.manager.builtIndices.length,
        'placedItems': view.placedItems.length,
      };
    }

    Map<String, Object> deliver(int step, Stopwatch scheduled) {
      final before = selected;
      final dispatch = Stopwatch()..start();
      final moved = host().handleKey(KeyEvent(step > 0 ? 'down' : 'up'));
      final dispatchMs = dispatch.elapsedMicroseconds / 1000;
      final drawing = Stopwatch()..start();
      final shown = host().drawFrame(size);
      final redrawMs = drawing.elapsedMicroseconds / 1000;
      final accepting = Stopwatch()..start();
      final accepted = host().handleKey(const KeyEvent('enter'));
      final elapsed = scheduled.elapsedMicroseconds / 1000;
      if (!moved ||
          !accepted ||
          !shown.toString().contains('Resume a session') ||
          selected < 0 ||
          selected >= count ||
          (selected - before).abs() > 1) {
        throw StateError('Current resume navigation/acceptance failed.');
      }
      if (corpus == 'baseline' &&
          selected != (before + step).clamp(0, count - 1)) {
        throw StateError('Baseline navigation did not reach the adjacent row.');
      }
      return {
        'dispatchMs': dispatchMs,
        'redrawMs': redrawMs,
        'enterDispatchMs': accepting.elapsedMicroseconds / 1000,
        'scheduledToAcceptanceMs': elapsed,
        'afterRequestedDelayMs': math.max(0, elapsed - 16),
        'beforeIndex': before,
        'afterIndex': selected,
      };
    }

    Future<void> stage(String name, Map<String, Object> Function() body) async {
      resetResumePickerWorkDiagnostics();
      final watch = Stopwatch()..start();
      final done = Completer<Map<String, Object>>();
      final trigger = Timer(const Duration(milliseconds: 16), () {
        try {
          done.complete(deliver(1, watch));
        } catch (error, stack) {
          done.completeError(error, stack);
        }
      });
      try {
        final bodyWatch = Stopwatch()..start();
        final details = body();
        final bodyMs = bodyWatch.elapsedMicroseconds / 1000;
        final bodyWork = _work();
        resetResumePickerWorkDiagnostics();
        final input = await done.future;
        stages.add({
          'stage': name,
          'bodyMs': bodyMs,
          ...details,
          'bodyWork': bodyWork,
          'scheduledInput': input,
          'inputWork': _work(),
          'surface': census(),
          'rssBytes': ProcessInfo.currentRss,
        });
        _requireNoWork();
      } finally {
        trigger.cancel();
      }
    }

    try {
      await stage('firstConstructAndLayout120x40', () {
        final construction = Stopwatch()..start();
        ownedHost = AppHost(
          ResumePicker(
            picker: snapshot,
            agent: 'fake',
            rows: 10,
            room: 40,
            onToggleScope: () {},
            onCanceled: () {},
            onSelected: (choice) {
              selected =
                  count - 1 - int.parse(choice.resume.sessionId.substring(8));
            },
          ),
        );
        final constructMs = construction.elapsedMicroseconds / 1000;
        final draw = Stopwatch()..start();
        host().drawFrame(size);
        return {
          'constructionMs': constructMs,
          'layoutPaintMs': draw.elapsedMicroseconds / 1000,
        };
      });
      await stage('coldResize80x24', () {
        size = const Size(80, 24);
        host().drawFrame(size);
        return {};
      });
      await stage('returnResize120x40', () {
        size = const Size(120, 40);
        host().drawFrame(size);
        return {};
      });
      final unchanged = <double>[];
      await stage('unchangedFrames', () {
        for (var i = 0; i < samples; i++) {
          final watch = Stopwatch()..start();
          host().drawFrame(size);
          unchanged.add(watch.elapsedMicroseconds / 1000);
        }
        return {'frameMs': _distribution(unchanged)};
      });
      for (final target in [0, count ~/ 2, count - 1]) {
        final preparing = Stopwatch()..start();
        var keys = 0;
        while (selected != target) {
          if (++keys > count * 40) {
            throw StateError('Position setup exceeded corpus row bound.');
          }
          host().handleKey(KeyEvent(selected < target ? 'down' : 'up'));
          host().handleKey(const KeyEvent('enter'));
        }
        host().drawFrame(size);
        final setupPositionMs = preparing.elapsedMicroseconds / 1000;
        resetResumePickerWorkDiagnostics();
        final dispatch = <double>[], redraw = <double>[], delay = <double>[];
        for (var i = 0; i < samples; i++) {
          final done = Completer<Map<String, Object>>();
          final scheduled = Stopwatch()..start();
          final direction = target == count - 1 ? -1 : 1;
          Timer(const Duration(milliseconds: 16), () {
            try {
              done.complete(
                deliver(i.isEven ? direction : -direction, scheduled),
              );
            } catch (error, stack) {
              done.completeError(error, stack);
            }
          });
          final result = await done.future;
          dispatch.add(result['dispatchMs']! as double);
          redraw.add(result['redrawMs']! as double);
          delay.add(result['scheduledToAcceptanceMs']! as double);
        }
        _requireNoWork();
        stages.add({
          'stage': 'navigation',
          'targetIndex': target,
          'setupKeys': keys,
          'positionSetupMs': setupPositionMs,
          'dispatchMs': _distribution(dispatch),
          'redrawMs': _distribution(redraw),
          'scheduledToAcceptanceMs': _distribution(delay),
          'work': _work(),
          'surface': census(),
          'rssBytes': ProcessInfo.currentRss,
        });
      }
    } finally {
      ownedHost?.dispose();
      disposed++;
    }
    reports.add({'repetition': repetition, 'stages': stages});
  }
  print(
    const JsonEncoder.withIndent('  ').convert({
      'sourceCommit': option('source', 'unspecified'),
      'runtimeLabel': option('runtime', 'unspecified'),
      'dartVersion': Platform.version.split(' ').first,
      'choices': count,
      'corpus': corpus,
      'samples': samples,
      'repetitions': repetitions,
      'rowLimit': 10,
      'corpusSetupMs': setupMs,
      'scheduledDelayMs': 16,
      'limits':
          'Actual ResumePicker with in-memory summaries. Baseline corpus matches CTUI-26 titles/order/numeric times; fixture paths are not read. '
          'First paint reports construction separately and inclusively because choices now freeze at mount. '
          'Scheduled stage input begins before the synchronous body; afterRequestedDelayMs subtracts requested16ms like CTUI-26. '
          'Stable input groups include requested16ms; position setup uses actual keys and is timed separately. '
          'Numeric counters are AOT-active and add observational overhead. Cold width may perform no-edge, edge and exact scalar shaping passes O(N). '
          'RSS/peak RSS are process observations, not retained heap proof; no scan/disk/agent/PTY/display timing.',
      'reports': reports,
      'maxRssBytes': ProcessInfo.maxRss,
      'cleanup': {
        'hostsDisposed': disposed,
        'pendingTimers': 0,
        'externalProcessesStarted': 0,
        'fixtureRootsCreated': 0,
      },
    }),
  );
}

Map<String, int> _work() {
  final work = resumePickerWorkDiagnostics;
  return {
    'choiceCalls': work.choiceCalls,
    'projectedChoices': work.projectedChoices,
    'noEdgePasses': work.linePasses,
    'edgePasses': work.overflowPasses,
    'sharedRowShapes': work.rowShapes,
  };
}

void _requireNoWork() {
  if (_work().values.any((count) => count != 0)) {
    throw StateError(
      'Stable actual resume input repeated projection or shaping.',
    );
  }
}

Map<String, Object> _distribution(List<double> values) {
  final sorted = [...values]..sort();
  double at(double q) => sorted[((sorted.length - 1) * q).round()];
  return {
    'samples': values,
    'min': sorted.first,
    'median': at(.5),
    'p95': at(.95),
    'max': sorted.last,
  };
}
