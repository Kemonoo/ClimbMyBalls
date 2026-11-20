import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climbing/climbing.dart';
import 'package:climbing_ui/climbing_ui.dart';

/// A host with no hibi: an in-memory store, no health data, plain days.
class _Host extends ClimbingHost {
  _Host(this.store);
  @override
  final MemoryClimbingStore store;
  final _changes = ChangeNotifier();

  @override
  Listenable get listenable => _changes;
  @override
  Iterable<ClimbWorkout> get workouts => const [];
  @override
  ClimbWorkout? workoutById(String? id) => null;
  @override
  Future<void> refreshWorkouts() async {}
  @override
  String sourceLabel(String source) => source;
  @override
  void log(String event, [Map<String, Object?> data = const {}]) {}
  @override
  DateTime now() => DateTime(2026, 11, 17, 12);
  @override
  String dayKey(DateTime t) => t.toIso8601String().substring(0, 10);
  @override
  String dayBefore(String day, [int n = 1]) => DateTime.parse(day).subtract(Duration(days: n)).toIso8601String().substring(0, 10);
  @override
  String dayLabel(String day) => day;
  @override
  ClimbTheme theme(BuildContext context) => ClimbTheme(
        ink: Colors.black,
        muted: Colors.grey,
        line: Colors.black12,
        surface: Colors.white,
        accent: Colors.orange,
        accentDeep: Colors.deepOrange,
        onAccent: Colors.black,
        calm: Colors.teal,
        textStyle: (size, bold, color, height) => TextStyle(fontSize: size, fontWeight: bold ? FontWeight.w700 : FontWeight.w400, color: color, height: height),
      );
}

// Climbing extraction step 4: the screens need only a ClimbingHost, so they
// run without hibi, as the standalone climbing app will.
void main() {
  testWidgets('the climbing screen runs on its own store, with no hibi', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    final store = MemoryClimbingStore(sessions: [
      ClimbSession.fromJson({
        'id': 's1',
        'start': '2026-11-15T18:00:00.000',
        'place': 'Boulder Bar',
        'source': 'manual',
        'climbs': [
          {'grade': '6B', 'outcome': 'flash', 'angle': 'overhang'},
          {'grade': '6C', 'outcome': 'sent', 'angle': 'vertical'},
        ],
      }),
    ]);
    ClimbingHost.instance = _Host(store);
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: ClimbSection())));
    await tester.pump();
    expect(find.text('Boulder Bar'), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
