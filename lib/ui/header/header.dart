import '../status/status.dart' show MarkTones;
import 'mark_rows.dart';

/// Uses a theme's gradient, then its one tone, else no explicit colour.
MarkColour markColour(MarkTones? tones) {
  if (tones?.stops case final stops?) return MarkGradient(stops);
  if (tones?.tone case final tone?) return MarkTone(tone);
  return const MarkPlain();
}
