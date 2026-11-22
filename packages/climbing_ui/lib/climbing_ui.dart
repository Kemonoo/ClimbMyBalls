// The climbing screens (climbing extraction, step 4): level and statistics,
// sessions, logging, the TopLogger paste, places and the calendar. They talk
// only to a ClimbingHost, so the same screens run inside hibi and in the
// standalone climbing app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:climbing/climbing.dart';
import 'package:climbing/toplogger.dart';
import 'package:url_launcher/url_launcher.dart';

import 'host.dart';

export 'host.dart';

part 'src/progress.dart';
part 'src/sessions.dart';
part 'src/log.dart';
part 'src/paste.dart';
part 'src/places.dart';
part 'src/calendar.dart';

// Grade colours by band, like the coloured holds at most gyms. Picked to stay
// apart from each other and readable as small marks on the light background.
const _bandColors = <String, Color>{
  '3': Color(0xFF8AA98F),
  '4': Color(0xFF2F9461),
  '5': Color(0xFF3770C4),
  '6': Color(0xFFE07020),
  '7': Color(0xFFC23B22),
  '8': Color(0xFF6A3C9C),
};
const _ungraded = Color(0xFFB5ADA3);

Color gradeColor(String grade) => grade.isEmpty ? _ungraded : _bandColors[grade[0]] ?? _ungraded;

/// '#RRGGBB' → a colour, or null.
Color? holdColor(String hex) {
  final h = hex.replaceFirst('#', '');
  final v = h.length == 6 ? int.tryParse(h, radix: 16) : null;
  return v == null ? null : Color(0xFF000000 | v);
}

String _fmtMinutes(int m) => m >= 60 ? '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m' : '$m min';

String _plural(int n, String one, [String? many]) => '$n ${n == 1 ? one : many ?? '${one}s'}';


String _ddmmyy(DateTime t) =>
    '${t.day.toString().padLeft(2, '0')}/${t.month.toString().padLeft(2, '0')}/${(t.year % 100).toString().padLeft(2, '0')}';

const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
const _months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/// What the statistics below the level cover.
enum _Period { twoMonths, year, all }

extension on _Period {
  String get label => switch (this) {
        _Period.twoMonths => '2 months',
        _Period.year => 'This year',
        _Period.all => 'All time',
      };
}
