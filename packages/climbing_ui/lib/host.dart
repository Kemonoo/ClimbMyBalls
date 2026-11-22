// What the climbing screens need from whoever runs them (climbing extraction,
// step 4): hibi provides one over its state, the standalone climbing app its
// own. Nothing in the screens knows which.
import 'package:flutter/material.dart';
import 'package:climbing/climbing.dart';
import 'package:climbing/store.dart';

export 'package:climbing/store.dart';

/// A workout from the phone's health data that a climbing session can link to.
abstract interface class ClimbWorkout {
  String get id;
  String get title;

  /// walk | run | ... | climb | workout
  String get type;
  DateTime get start;
  DateTime get end;
  int get seconds;

  /// The app that recorded it (a package name).
  String get source;
  String get notes;
}

/// The colours and text the screens use.
class ClimbTheme {
  const ClimbTheme({
    required this.ink,
    required this.muted,
    required this.line,
    required this.surface,
    required this.accent,
    required this.accentDeep,
    required this.onAccent,
    required this.calm,
    required this.textStyle,
    this.send = const Color(0xFFFF0A8C),
    this.sendDeep = const Color(0xFF9A0B5E),
  });
  final Color ink, muted, line, surface, accent, accentDeep, onAccent, calm;

  /// Sends, and the flashed part of them: TopLogger's magenta and wine unless
  /// the host has its own (hibi uses its Skills violet, #487).
  final Color send, sendDeep;
  final TextStyle Function(double size, bool bold, Color? color, double? height) textStyle;

  TextStyle text(double size, {bool bold = false, Color? color, double? height}) => textStyle(size, bold, color, height);
}

abstract class ClimbingHost {
  /// The host the screens use; set once by the app before showing them.
  static late ClimbingHost instance;

  ClimbingStore get store;

  /// Tells the screens to redraw when anything they show changes.
  Listenable get listenable;

  /// Health workouts a session could link to, and asking for fresh ones.
  Iterable<ClimbWorkout> get workouts;
  ClimbWorkout? workoutById(String? id);
  Future<void> refreshWorkouts();
  String sourceLabel(String source);

  void log(String event, [Map<String, Object?> data = const {}]);

  /// The clock and days (hibi's days start at 04:00; a standalone app may differ).
  DateTime now();
  String dayKey(DateTime t);
  String dayBefore(String day, [int n = 1]);
  String dayLabel(String day);

  ClimbTheme theme(BuildContext context);
}

ClimbingHost get host => ClimbingHost.instance;

/// A saved or used place by name, ignoring case.
ClimbPlace? climbPlaceIn(ClimbingStore store, String name) {
  final k = name.trim().toLowerCase();
  return store.places.where((p) => p.name.trim().toLowerCase() == k).firstOrNull;
}

/// Health sessions a climb could belong to: the last [days] days, climbing
/// ones first, then any generic workout, newest first; ones already linked are
/// left out, except the one [keep] links to.
List<ClimbWorkout> linkCandidatesOf(Iterable<ClimbWorkout> workouts, Iterable<ClimbSession> sessions, {required DateTime now, int days = 14, String? keep}) {
  final used = {for (final s in sessions) if (s.sourceId != null && s.sourceId != keep) s.sourceId!};
  final from = now.subtract(Duration(days: days));
  final out = [
    for (final w in workouts)
      if ((w.type == 'climb' || w.type == 'workout') && !used.contains(w.id) && w.start.isAfter(from) && !w.start.isAfter(now)) w,
  ];
  out.sort((a, b) {
    final ta = a.type == 'climb' ? 0 : 1, tb = b.type == 'climb' ? 0 : 1;
    return ta != tb ? ta.compareTo(tb) : b.start.compareTo(a.start);
  });
  return out;
}

String fmtClock(DateTime t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
