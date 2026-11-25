/// The startup splash on screen, from the original's `ui/splash/Splash.tsx`:
/// alone on the screen until the first session is up, the mark dim on the
/// terminal's own foreground, and its lines.
library;

import 'dart:async';

import 'package:chord_tui/chord_tui.dart';
import 'package:clock/clock.dart';

import '../header/mark_rows.dart';
import 'splash.dart';

/// The splash for [agent], filling what it is given and covering what is
/// under it. [armed] is an armed quit's question, which the first line says
/// instead; [closing] has it say the agent stops.
class Splash extends StatefulWidget {
  const Splash({
    super.key,
    required this.agent,
    this.armed,
    this.closing = false,
  });

  final String agent;
  final String? armed;
  final bool closing;

  @override
  State<Splash> createState() => _SplashState();
}

class _SplashState extends State<Splash> {
  final _opened = clock.now();
  var _step = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // One timer for the drift and the seconds, which draw only when it ticks.
    _timer = Timer.periodic(
      const Duration(milliseconds: splashStepMs),
      (_) => setState(() => _step++),
    );
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => DecoratedBox(
    background: Style.plain,
    child: LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth, rows = constraints.maxHeight;
        final grid = splashMarkFor(columns, rows);
        final box = grid == null
            ? null
            : [
                for (final row in markRows(
                  splashFrame(grid, _step),
                  const MarkPlain(),
                ))
                  row.map((segment) => segment.text).join(),
              ];
        final lines = splashLines(
          agent: widget.agent,
          elapsed: clock.now().difference(_opened).inMilliseconds,
          armed: widget.armed,
          closing: widget.closing,
        );
        final (:top, :markLeft, :lineLefts) = splashLayout(
          columns,
          rows,
          grid,
          lines,
        );
        Widget line(String text, int left) => Padding(
          padding: EdgeInsets.only(left: left),
          child: Text(
            text,
            style: Style.dim,
            softWrap: false,
            maxLines: 1,
            overflow: TextOverflow.clip,
          ),
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(height: top),
            if (box != null)
              Padding(
                padding: EdgeInsets.only(left: markLeft, bottom: 1),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final row in box)
                      Text(row, style: Style.dim, softWrap: false),
                  ],
                ),
              ),
            line(lines.$1, lineLefts.$1),
            line(lines.$2, lineLefts.$2),
          ],
        );
      },
    ),
  );
}
