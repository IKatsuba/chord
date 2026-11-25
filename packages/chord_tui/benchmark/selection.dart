/// Selection/source work measured separately from current app-owned history.
/// Run compiled under the team's exclusive heavy slot for timing evidence.
library;

import 'dart:convert';

import 'package:chord_tui/chord_tui.dart';
import 'package:chord_tui/src/foundation/selection_controller.dart'
    show selectionDiagnostics;
import 'package:chord_tui/src/foundation/selection_diagnostics.dart';
import 'package:chord_tui/src/text/markdown.dart';

class _Counts {
  int builders = 0, builds = 0, mounted = 0, peak = 0, resolutions = 0;
}

class _Entry extends StatefulWidget {
  const _Entry(this.source, this.counts);
  final SelectionSource source;
  final _Counts counts;
  @override
  State<_Entry> createState() => _EntryState();
}

class _EntryState extends State<_Entry> {
  @override
  void initState() {
    super.initState();
    final counts = widget.counts;
    counts.mounted++;
    if (counts.mounted > counts.peak) counts.peak = counts.mounted;
  }

  @override
  void dispose() {
    widget.counts.mounted--;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    widget.counts.builds++;
    return Markdown.fromSelectionSource(widget.source);
  }
}

/// One independent current history; no benchmark keeps old source revisions.
class SelectionBenchmark {
  SelectionBenchmark(this.count, this.size) {
    resetMarkdownParseDiagnostics();
    resetSelectionWorkDiagnostics();
    sources = [
      for (var i = 0; i < count; i++)
        SelectionSource.markdown(
          id: i,
          revision: 0,
          text: 'Entry $i\n\nbody $i with 日本語 and e\u0301',
        ),
    ];
    print(
      jsonEncode({
        'phase': 'factory',
        'entries': count,
        'size': '$size',
        'authoritativeCurrentSources': sources.length,
        ..._parse(),
        ..._work(),
      }),
    );
    host = AppHost(
      ListenableBuilder(
        listenable: changed,
        builder: (_) {
          final delegate = SelectionChildDelegate(
            itemCount: sources.length,
            idAt: (i) => i,
            indexOfId: (id) =>
                id is int && id >= 0 && id < sources.length ? id : null,
            sourceAt: (i) {
              counts.resolutions++;
              return current(i);
            },
          );
          return SelectionArea(
            controller: selection,
            selectionStyle: Style.inverse,
            child: Column(
              children: [
                Text('header'),
                Expanded(
                  child: ListView.builder(
                    controller: scroll,
                    itemCount: sources.length,
                    selectionDelegate: delegate,
                    itemVersion: (i) => i == count - 1 ? revision : 0,
                    itemBuilder: (_, i) {
                      counts.builders++;
                      return _Entry(current(i), counts);
                    },
                  ),
                ),
                Text('footer'),
              ],
            ),
          );
        },
      ),
    );
  }
  final int count;
  final Size size;
  final counts = _Counts();
  final selection = SelectionController();
  final scroll = ScrollController();
  final changed = ValueNotifier(0);
  late final AppHost host;
  late final List<SelectionSource> sources;
  int revision = 0;
  SelectionSource current(int i) {
    if (i == count - 1 && sources[i].revision != revision) {
      sources[i] = SelectionSource.markdown(
        id: i,
        revision: revision,
        text: 'Entry $i\n\nupdated body $revision',
        previous: sources[i],
      );
    }
    return sources[i];
  }

  Map<String, int> _parse() {
    final value = markdownParseDiagnostics;
    return {
      'parserUpdates': value.updates,
      'changedUpdates': value.changedUpdates,
      'parseTail': value.tailParses,
    };
  }

  Map<String, int> _work() {
    final value = selectionWorkDiagnostics;
    return {
      'sceneCollections': value.sceneCollections,
      'rangeCompositions': value.rangeCompositions,
    };
  }

  Map<String, int> refs() {
    final value = selectionDiagnostics(selection);
    return {
      'logicalSlots': value.logicalSlots,
      'visibleRoots': value.visibleRoots,
      'resolvedRoots': value.resolvedRoots,
      'extraOffscreenRootCaches': value.offscreenResolvedRoots,
      'cachedFragments': value.cachedFragments,
      'selectedRootLeases': value.selectedRoots,
      'rangeLeases': value.selectedRanges,
    };
  }

  void measure(String phase, int frames, {void Function()? before}) {
    resetMarkdownParseDiagnostics();
    resetSelectionWorkDiagnostics();
    final builders = counts.builders,
        builds = counts.builds,
        resolutions = counts.resolutions;
    final micros = <int>[];
    before?.call();
    for (var i = 0; i < frames; i++) {
      final watch = Stopwatch()..start();
      host.drawFrame(size);
      micros.add(watch.elapsedMicroseconds);
    }
    micros.sort();
    var viewportMounted = 0;
    void visit(Element element) {
      if (element is ListViewportElement) {
        viewportMounted += element.builtIndices.length;
      }
      element.visitChildren(visit);
    }

    visit(host.rootElement);
    print(
      jsonEncode({
        'phase': phase,
        'entries': count,
        'size': '$size',
        'frames': frames,
        'builders': counts.builders - builders,
        'stateBuilds': counts.builds - builds,
        'mountedStates': counts.mounted,
        'viewportMounted': viewportMounted,
        'peakStates': counts.peak,
        'delegateResolutions': counts.resolutions - resolutions,
        ..._parse(),
        ..._work(),
        ...refs(),
        'medianMs': micros[micros.length ~/ 2] / 1000,
        'p95Ms': micros[((micros.length - 1) * .95).round()] / 1000,
        'maxMs': micros.last / 1000,
      }),
    );
    if (counts.mounted != viewportMounted || counts.mounted > count) {
      throw StateError('Selection retained an offscreen entry state');
    }
    if (phase.endsWith('.steady') &&
        (counts.builders != builders ||
            counts.builds != builds ||
            counts.resolutions != resolutions ||
            markdownParseDiagnostics.tailParses != 0 ||
            selectionWorkDiagnostics.sceneCollections != 0 ||
            selectionWorkDiagnostics.rangeCompositions != 0)) {
      throw StateError(
        'Unchanged selection performed builder/source/parser/composition work',
      );
    }
    if (phase.endsWith('.burst1000') &&
        (markdownParseDiagnostics.changedUpdates != 1 ||
            markdownParseDiagnostics.tailParses != 1)) {
      throw StateError(
        'The current burst was not coalesced into one source parse',
      );
    }
    if (phase == 'clear.next-frame') _checkClear();
  }

  void _checkClear() {
    final value = selectionDiagnostics(selection);
    if (value.selectedRoots != 0 ||
        value.selectedRanges != 0 ||
        value.offscreenResolvedRoots != 0) {
      throw StateError('Clear retained selection-only sources or ranges');
    }
  }

  void pointer(MouseEventKind kind, int y) => host.handleMouse(
    MouseEvent(kind, position: Offset(0, y), button: MouseButton.primary),
  );
  void burst() {
    for (var i = 0; i < 1000; i++) {
      revision++;
      changed.value++;
    }
  }

  void run(int frames) {
    measure('first-layout', 1);
    measure('none.steady', frames);
    measure('none.burst1000', 1, before: burst);
    pointer(MouseEventKind.press, 0);
    pointer(MouseEventKind.move, size.height - 1);
    measure('held.steady', frames);
    measure('held.burst1000', 1, before: burst);
    pointer(MouseEventKind.release, size.height - 1);
    measure('shown.steady', frames);
    measure('shown.burst1000', 1, before: burst);
    resetSelectionWorkDiagnostics();
    selection.clear();
    _checkClear();
    print(
      jsonEncode({
        'phase': 'clear.immediate',
        ..._work(),
        'entries': count,
        'size': '$size',
        ...refs(),
      }),
    );
    measure('clear.next-frame', 1);
    host.dispose();
    selection.dispose();
    scroll.dispose();
    changed.dispose();
    if (counts.mounted != 0) {
      throw StateError('Mounted state survived disposal');
    }
  }
}

void main(List<String> args) {
  int option(String name, int fallback) =>
      int.tryParse(
        args
                .where((a) => a.startsWith('$name='))
                .firstOrNull
                ?.split('=')
                .last ??
            '',
      ) ??
      fallback;
  final only = option('--entries', 0), frames = option('--frames', 20);
  if (frames < 1) throw ArgumentError('frames must be positive');
  for (final count in only > 0 ? [only] : [600, 10000]) {
    for (final size in [const Size(120, 40), const Size(80, 24)]) {
      SelectionBenchmark(count, size).run(frames);
    }
  }
}
