// The standalone climbing app's host (climbing extraction, step 5): its own
// store, saved on the device as hibi protocol events; no health data, no
// hibi. Days start at midnight here.
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:hibi_climbing_ui/climbing_ui.dart';
import 'package:hibi_protocol/hibi_protocol.dart';

import 'storage/text_box.dart';

/// Where the events live, and loading and saving them.
class EventFile {
    EventFile(this.box);
  final TextBox box;

  List<Event> load() {
    try {
      final j = jsonDecode(box.read() ?? '{}') as Map;
      return [for (final e in (j['events'] as List? ?? const []).cast<Map>()) Event.fromJson(e)];
    } catch (_) {
      return const [];
    }
  }

    void save(List<Event> events) => box.write(const JsonEncoder.withIndent(' ').convert({'protocol': 1, 'events': events.map((e) => e.toJson()).toList()}));
}

class ClimbAppHost extends ClimbingHost {
  ClimbAppHost(this.file) : store = MemoryClimbingStore.fromEvents(file.load()) {
    store.changes.listen((_) {
      file.save(store.toEvents(recordedAt: DateTime.now()));
      _changes.notify();
    });
  }

  final EventFile file;
  @override
  final MemoryClimbingStore store;
  final _changes = _Notifier();

  @override
  Listenable get listenable => _changes;

  // No health data in the standalone app (yet).
  @override
  Iterable<ClimbWorkout> get workouts => const [];
  @override
  ClimbWorkout? workoutById(String? id) => null;
  @override
  Future<void> refreshWorkouts() async {}
  @override
  String sourceLabel(String source) => source == 'climb-cloud' ? 'Logged on routes' : source;

  @override
  void log(String event, [Map<String, Object?> data = const {}]) {}

  @override
  DateTime now() => DateTime.now();

  @override
  String dayKey(DateTime t) => t.toIso8601String().substring(0, 10);

  @override
  String dayBefore(String day, [int n = 1]) => DateTime.parse(day).subtract(Duration(days: n)).toIso8601String().substring(0, 10);

  @override
  String dayLabel(String day) {
    final today = dayKey(now());
    if (day == today) return 'Today';
    if (day == dayBefore(today)) return 'Yesterday';
    final d = DateTime.parse(day);
    return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}';
  }

  @override
  ClimbTheme theme(BuildContext context) => ClimbTheme(
        ink: const Color(0xFFF2EEE8),
        muted: const Color(0xFF9AA3B2),
        line: const Color(0xFF2A3140),
        surface: const Color(0xFF161B26),
        accent: const Color(0xFFF2A65A),
        accentDeep: const Color(0xFFC9803A),
        onAccent: const Color(0xFF1A1206),
        calm: const Color(0xFF5FB3A1),
        textStyle: (size, bold, color, height) =>
            TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w500, color: color ?? const Color(0xFFF2EEE8), height: height),
      );
}

class _Notifier extends ChangeNotifier {
  void notify() => notifyListeners();
}
