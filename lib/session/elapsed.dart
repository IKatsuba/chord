import 'dart:math' as math;

/// Elapsed milliseconds as seconds, minutes and seconds, or hours and minutes.
String formatElapsed(num milliseconds) {
  final seconds = math.max(0, (milliseconds / 1000).floor());
  if (seconds < 60) return '${seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m ${seconds % 60}s';
  return '${minutes ~/ 60}h ${minutes % 60}m';
}
