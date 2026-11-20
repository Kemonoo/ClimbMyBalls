// Climbing: grades, a parser for TopLogger's Strava text, points and levels.
//
// Everything here is a pure function or a plain data class — no app state, no
// Flutter — so it can be tested on its own (see test/climb_test.dart). It lives
// in packages/climbing so hibi and the standalone climbing app share it
// (docs/architecture/climbing-extraction.md).


/// The Font (Fontainebleau) bouldering ladder, lowest first.
///
/// One rung per half grade from 3A to 8C+. The plan sketched the ladder as
/// "3, 4, 4+, 5A, 5A+, …", but a real TopLogger session already contains `3C`,
/// so the lettered rungs run all the way down and bare numbers are aliases
/// (see [kGradeAliases]).
const kGradeLadder = <String>[
  '3A', '3A+', '3B', '3B+', '3C', '3C+', //
  '4A', '4A+', '4B', '4B+', '4C', '4C+',
  '5A', '5A+', '5B', '5B+', '5C', '5C+',
  '6A', '6A+', '6B', '6B+', '6C', '6C+',
  '7A', '7A+', '7B', '7B+', '7C', '7C+',
  '8A', '8A+', '8B', '8B+', '8C', '8C+',
];

/// Grades written without a letter, mapped onto the rung they sit closest to.
/// A bare number is the bottom of its band; `+` lands mid-band.
const kGradeAliases = <String, String>{
  '3': '3A', '3+': '3B',
  '4': '4A', '4+': '4B',
  '5': '5A', '5+': '5B',
  '6': '6A', '6+': '6B',
  '7': '7A', '7+': '7B',
  '8': '8A', '8+': '8B',
};

/// TopLogger writes grades in small caps with a superscript plus.
const _fancyChars = <String, String>{
  'ᴀ': 'A', 'ʙ': 'B', 'ᴄ': 'C', 'ᴅ': 'D',
  'ᵃ': 'A', 'ᵇ': 'B', 'ᶜ': 'C',
  '⁺': '+', '＋': '+', '﹢': '+',
  '−': '-', '–': '-', '—': '-',
};

/// Turns `6ʙ⁺` into `6B+`. Returns '' for an ungraded climb (`?`).
String normaliseGrade(String raw) {
  final b = StringBuffer();
  // Emoji variation selectors and joiners (⚡️ is ⚡ + U+FE0F) are invisible; drop them.
  for (final ch in raw.replaceAll(RegExp('[\uFE0E\uFE0F\u200D\u200B]'), '').trim().split('')) {
    b.write(_fancyChars[ch] ?? ch);
  }
  var g = b.toString().toUpperCase().replaceAll(RegExp(r'\s+'), '');
  if (g == '?' || g.isEmpty) return '';
  // Font grades are sometimes written "6a+" / "F6A+" / "FB6A+".
  g = g.replaceFirst(RegExp(r'^(FB|F)'), '');
  return kGradeAliases[g] ?? g;
}

/// Position of a grade on [kGradeLadder], or null if it is not a grade we know.
int? gradeIndex(String grade) => _gradeIndexCache.putIfAbsent(grade, () {
      final g = normaliseGrade(grade);
      if (g.isEmpty) return null;
      final i = kGradeLadder.indexOf(g);
      return i < 0 ? null : i;
    });

/// [gradeIndex] per raw grade: normalising runs regexes, and the level and
/// its history ask for every climb's grade on each frame. Few distinct grades.
final _gradeIndexCache = <String, int?>{};

/// The grade `fraction` of the way up from the rung below, e.g. 18.4 → '6A'.
String gradeLabel(double index) {
  final i = index.round().clamp(0, kGradeLadder.length - 1);
  return kGradeLadder[i];
}

/// How a climb went.
enum ClimbOutcome {
  flash, // sent first try, this session
  sent, // sent after working it
  tried, // attempted, not sent
}

extension ClimbOutcomeX on ClimbOutcome {
  String get label => switch (this) {
        ClimbOutcome.flash => 'Flash',
        ClimbOutcome.sent => 'Sent',
        ClimbOutcome.tried => 'Tried',
      };

  bool get isSend => this != ClimbOutcome.tried;
}

/// Wall angle, which changes how much the upper body carries.
enum WallAngle { slab, vertical, overhang }

extension WallAngleX on WallAngle {
  String get label => switch (this) {
        WallAngle.slab => 'Slab',
        WallAngle.vertical => 'Vertical',
        WallAngle.overhang => 'Overhang',
      };

  /// Load multiplier for the body map: steeper walls move work to the hands.
  double get loadFactor => switch (this) {
        WallAngle.slab => 0.85,
        WallAngle.vertical => 1.0,
        WallAngle.overhang => 1.35,
      };
}

/// One climb (one boulder or route attempt-set) in a session.
class Climb {
  Climb({
    required this.grade,
    required this.outcome,
    this.name = '',
    this.repeat = false,
    this.angle = WallAngle.vertical,
    this.hold = '',
    this.attempts,
    this.problemId,
    this.gymGrade = '',
  });

  /// Normalised grade ('6A+'), or '' when the climb was ungraded (`?`).
  final String grade;
  final ClimbOutcome outcome;
  final String name;

  /// A boulder climbed before: it still counts, but for half the points.
  final bool repeat;
  final WallAngle angle;

  /// Hold colour as '#RRGGBB' when known (TopLogger), else ''.
  final String hold;

  /// Goes on this route in the session, counting the one that topped it.
  /// Null when nobody counted (pasted ✅ sends, older logs).
  final int? attempts;

  /// The problem this tick is on: a Place id (places/place.dart). Outdoor
  /// ticks; null when the climb isn't linked to a known problem.
  final String? problemId;

  /// The grade on the gym's own scale ('yellow', 'V3'), for indoor ticks.
  /// [grade] stays the Font grade (or '') so points don't change.
  final String gymGrade;

  /// The grade to show: Font outdoors, the gym's own scale indoors when known.
  String shownGrade({required bool outdoor}) => !outdoor && gymGrade.isNotEmpty ? gymGrade : grade;

  /// [attempts], or 1 for a flash, which is one try by definition.
  int? get tries => outcome == ClimbOutcome.flash ? 1 : attempts;

  bool get isGraded => grade.isNotEmpty;
  int? get index => gradeIndex(grade);

  /// Points, TopLogger's way: 6A is 600, 7A is 700, each half grade between
  /// adds a sixth of that (6B 633, 6C+ 683). A flash adds 10, a repeat scores
  /// half, and a climb that was tried but not sent scores nothing.
  ///
  /// The flash bonus is small: a flashed 6A (610) still ranks below a worked
  /// 6A+ (617). 8a.nu and theCrag give a flash about half a grade instead.
  double get points {
    final i = index;
    if (i == null || !outcome.isSend) return 0;
    var p = rungPoints(i).roundToDouble();
    if (outcome == ClimbOutcome.flash) p += kFlashBonus;
    if (repeat) p *= 0.5;
    return p;
  }

  Climb copyWith({String? grade, ClimbOutcome? outcome, String? name, bool? repeat, WallAngle? angle, String? hold, int? Function()? attempts, String? Function()? problemId, String? gymGrade}) => Climb(
        grade: grade ?? this.grade,
        outcome: outcome ?? this.outcome,
        name: name ?? this.name,
        repeat: repeat ?? this.repeat,
        angle: angle ?? this.angle,
        hold: hold ?? this.hold,
        attempts: attempts != null ? attempts() : this.attempts,
        problemId: problemId != null ? problemId() : this.problemId,
        gymGrade: gymGrade ?? this.gymGrade,
      );

  Map<String, dynamic> toJson() => {
        'grade': grade,
        'outcome': outcome.name,
        if (name.isNotEmpty) 'name': name,
        if (repeat) 'repeat': true,
        'angle': angle.name,
        if (hold.isNotEmpty) 'hold': hold,
        if (attempts != null) 'attempts': attempts,
        if (problemId != null) 'problem': problemId,
        if (gymGrade.isNotEmpty) 'gymGrade': gymGrade,
      };

  factory Climb.fromJson(Map<String, dynamic> j) => Climb(
        grade: normaliseGrade(j['grade'] as String? ?? ''),
        outcome: ClimbOutcome.values.byName(j['outcome'] as String? ?? 'sent'),
        name: j['name'] as String? ?? '',
        repeat: j['repeat'] as bool? ?? false,
        angle: WallAngle.values.byName(j['angle'] as String? ?? 'vertical'),
        hold: j['hold'] as String? ?? '',
        attempts: (j['attempts'] as num?)?.toInt(),
        problemId: j['problem'] as String?,
        gymGrade: j['gymGrade'] as String? ?? '',
      );
}

/// Points a flash adds on top of the send, as on TopLogger.
const kFlashBonus = 10.0;

/// TopLogger's points for a rung of [kGradeLadder]: 3A is 300 and each half
/// grade adds 50/3, so every grade number is 100 more (6A 600, 7A 700).
double rungPoints(num rung) => 300 + rung * 50 / 3;

/// The rung, with a fraction, that [points] sit on.
double pointsRung(double points) => (points - 300) * 3 / 50;

/// What kind of climbing a session was. The level and the statistics count
/// bouldering; the rope styles are logged and listed on their own.
enum ClimbStyle { boulder, lead, topRope, trad }

extension ClimbStyleX on ClimbStyle {
  String get label => switch (this) {
        ClimbStyle.boulder => 'Bouldering',
        ClimbStyle.lead => 'Lead',
        ClimbStyle.topRope => 'Top rope',
        ClimbStyle.trad => 'Trad',
      };

  /// "Bouldering session", "Outdoor lead", and so on.
  String title(bool outdoor) => switch (this) {
        ClimbStyle.boulder => outdoor ? 'Outdoor bouldering' : 'Bouldering session',
        ClimbStyle.lead => outdoor ? 'Outdoor lead' : 'Lead climbing',
        ClimbStyle.topRope => outdoor ? 'Outdoor top rope' : 'Top rope',
        ClimbStyle.trad => 'Trad climbing',
      };
}

/// A gym or an outdoor area, saved so it can be picked again. Only the name
/// is needed; the rest can be filled in later.
class ClimbPlace {
  ClimbPlace({required this.name, this.outdoor = false, this.address = '', this.maps = '', this.note = ''});

  final String name;
  final bool outdoor;
  final String address;

  /// A Google Maps link, pasted or found from the name.
  final String maps;
  final String note;

  ClimbPlace copyWith({String? name, bool? outdoor, String? address, String? maps, String? note}) => ClimbPlace(
        name: name ?? this.name,
        outdoor: outdoor ?? this.outdoor,
        address: address ?? this.address,
        maps: maps ?? this.maps,
        note: note ?? this.note,
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        if (outdoor) 'outdoor': true,
        if (address.isNotEmpty) 'address': address,
        if (maps.isNotEmpty) 'maps': maps,
        if (note.isNotEmpty) 'note': note,
      };

  factory ClimbPlace.fromJson(Map<String, dynamic> j) => ClimbPlace(
        name: j['name'] as String? ?? '',
        outdoor: j['outdoor'] as bool? ?? false,
        address: j['address'] as String? ?? '',
        maps: j['maps'] as String? ?? '',
        note: j['note'] as String? ?? '',
      );
}

/// Every place to pick from: the saved ones, then any name used in a session
/// that was never saved (so gyms from older sessions show up too), most used
/// first. Names match ignoring case.
List<ClimbPlace> placesFrom(Iterable<ClimbPlace> saved, Iterable<ClimbSession> sessions) {
  final uses = <String, int>{}, outdoor = <String, bool>{}, spelled = <String, String>{};
  for (final s in sessions) {
    final k = s.place.trim().toLowerCase();
    if (k.isEmpty) continue;
    uses[k] = (uses[k] ?? 0) + 1;
    outdoor[k] = s.outdoor;
    spelled.putIfAbsent(k, () => s.place.trim());
  }
  final out = [...saved];
  final have = {for (final p in saved) p.name.trim().toLowerCase()};
  for (final k in uses.keys) {
    if (!have.contains(k)) out.add(ClimbPlace(name: spelled[k]!, outdoor: outdoor[k]!));
  }
  out.sort((a, b) => (uses[b.name.trim().toLowerCase()] ?? 0).compareTo(uses[a.name.trim().toLowerCase()] ?? 0));
  return out;
}

/// A climbing session: one visit to a gym or a crag.
class ClimbSession {
  ClimbSession({
    required this.id,
    required this.start,
    this.end,
    this.place = '',
    this.outdoor = false,
    List<Climb>? climbs,
    this.source = 'manual', // manual | strava-text | health
    this.sourceId,
    this.note = '',
    this.topLoggerId,
    this.style = ClimbStyle.boulder,
  }) : climbs = climbs ?? <Climb>[];

  final String id;
  final DateTime start;
  final DateTime? end;

  /// Gym or crag name, when we know it.
  final String place;
  final bool outdoor;
  final List<Climb> climbs;
  final String source;
  final String? sourceId;
  final String note;

  /// The TopLogger session it came from, so the same one isn't added twice.
  final String? topLoggerId;

  final ClimbStyle style;

  int? get minutes => end?.difference(start).inMinutes;

  ClimbSession copyWith({
    DateTime? start,
    DateTime? Function()? end,
    String? place,
    bool? outdoor,
    List<Climb>? climbs,
    String? source,
    String? Function()? sourceId,
    String? note,
    ClimbStyle? style,
  }) =>
      ClimbSession(
        id: id,
        start: start ?? this.start,
        end: end != null ? end() : this.end,
        place: place ?? this.place,
        outdoor: outdoor ?? this.outdoor,
        climbs: climbs ?? [...this.climbs],
        source: source ?? this.source,
        sourceId: sourceId != null ? sourceId() : this.sourceId,
        note: note ?? this.note,
        topLoggerId: topLoggerId,
        style: style ?? this.style,
      );

  /// Points of every climb in the session.
  double get points => climbs.fold<double>(0, (a, c) => a + c.points);

  int get sends => climbs.where((c) => c.outcome.isSend).length;
  int get flashes => climbs.where((c) => c.outcome == ClimbOutcome.flash).length;

  /// Goes counted across the session's routes, or null when none were counted.
  int? get tries {
    final known = [for (final c in climbs) if (c.tries != null) c.tries!];
    return known.isEmpty ? null : known.fold<int>(0, (a, t) => a + t);
  }

  /// The session's top 10 average as a rung, or null when nothing was sent on a
  /// known grade. Like TopLogger, a session with fewer than ten sends is still
  /// divided by ten.
  double? get topGradeIndex => topTenAverageIndex(climbs);

  /// The top 10 average as a level, read like TopLogger's "6B +53%".
  ClimbLevel? get topLevel {
    final g = topGradeIndex;
    if (g == null) return null;
    final sends = climbs.where((c) => c.outcome.isSend && c.index != null).length;
    return ClimbLevel(g, sends < 10 ? sends : 10, sends);
  }

  String? get topGrade => topLevel?.grade;

  /// Share of the climbs that were flashed / repeats, 0–1 (TopLogger's session stats).
  double get flashShare => climbs.isEmpty ? 0 : flashes / climbs.length;
  double get repeatShare => climbs.isEmpty ? 0 : climbs.where((c) => c.repeat).length / climbs.length;

  Map<String, dynamic> toJson() => {
        'id': id,
        'start': start.toIso8601String(),
        if (end != null) 'end': end!.toIso8601String(),
        if (place.isNotEmpty) 'place': place,
        if (outdoor) 'outdoor': true,
        'climbs': [for (final c in climbs) c.toJson()],
        'source': source,
        if (sourceId != null) 'sourceId': sourceId,
        if (note.isNotEmpty) 'note': note,
        if (topLoggerId != null) 'topLoggerId': topLoggerId,
        if (style != ClimbStyle.boulder) 'style': style.name,
      };

  factory ClimbSession.fromJson(Map<String, dynamic> j) => ClimbSession(
        id: j['id'] as String,
        start: DateTime.parse(j['start'] as String),
        end: j['end'] == null ? null : DateTime.parse(j['end'] as String),
        place: j['place'] as String? ?? '',
        outdoor: j['outdoor'] as bool? ?? false,
        climbs: [
          for (final c in (j['climbs'] as List? ?? const [])) Climb.fromJson(Map<String, dynamic>.from(c as Map)),
        ],
        source: j['source'] as String? ?? 'manual',
        sourceId: j['sourceId'] as String?,
        note: j['note'] as String? ?? '',
        topLoggerId: j['topLoggerId'] as String?,
        style: ClimbStyle.values.asNameMap()[j['style']] ?? ClimbStyle.boulder,
      );
}

/// Where a session was, for the indoor and outdoor filters on the log and stats.
enum ClimbWhere {
  all,
  indoor,
  outdoor;

  bool has(ClimbSession s) => switch (this) {
        ClimbWhere.all => true,
        ClimbWhere.indoor => !s.outdoor,
        ClimbWhere.outdoor => s.outdoor,
      };
}

/// The ticks on one problem across [sessions], oldest first.
List<(Climb, ClimbSession)> ticksOn(String problemId, Iterable<ClimbSession> sessions) => [
      for (final s in sessions)
        for (final c in s.climbs)
          if (c.problemId == problemId) (c, s),
    ]..sort((a, b) => a.$2.start.compareTo(b.$2.start));

/// TopLogger's top 10 average: the points of the ten best sends in [climbs],
/// divided by ten even when there are fewer. Null when nothing graded was sent.
double? topTenAveragePoints(Iterable<Climb> climbs, {int top = 10}) {
  final sends = [
    for (final c in climbs)
      if (c.outcome.isSend && c.index != null) c,
  ]..sort((a, b) => b.points.compareTo(a.points));
  if (sends.isEmpty) return null;
  return sends.take(top).fold<double>(0, (a, c) => a + c.points) / top;
}

/// [topTenAveragePoints] as a rung (never below 3A).
///
/// Used for both [ClimbSession.topGradeIndex] and the level, so the two always
/// mean the same thing.
double? topTenAverageIndex(Iterable<Climb> climbs, {int top = 10}) {
  final p = topTenAveragePoints(climbs, top: top);
  return p == null ? null : pointsRung(p).clamp(0, kGradeLadder.length - 1).toDouble();
}

/// Where the climber is now: the top 10 average over the last [days] days, as
/// a grade plus how far it is to the next half grade ("6B +88%").
class ClimbLevel {
  const ClimbLevel(this.index, this.countedClimbs, this.gradedSends);

  /// The average as a rung, e.g. 20.88 for 648 points.
  final double index;

  /// The average in TopLogger points, e.g. 648.
  double get points => rungPoints(index);

  /// How many graded sends went into the average (at most ten).
  final int countedClimbs;

  /// Every graded send in the window, which is what "you sent N" means.
  final int gradedSends;

  /// The rung the average sits on. Like TopLogger, the average and each rung's
  /// points are whole numbers first (647.5 → 648, between 633 and 650).
  int get _rung {
    final p = points.round();
    var i = 0;
    while (i + 1 < kGradeLadder.length && rungPoints(i + 1).round() <= p) {
      i++;
    }
    return i;
  }

  String get grade => kGradeLadder[_rung];
  String? get next {
    final i = _rung + 1;
    return i < kGradeLadder.length ? kGradeLadder[i] : null;
  }

  /// 0–1 of the way from [grade] to [next].
  double get fraction {
    final i = _rung;
    if (i + 1 >= kGradeLadder.length) return 0;
    final lo = rungPoints(i).round(), hi = rungPoints(i + 1).round();
    return ((points.round() - lo) / (hi - lo)).clamp(0.0, 1.0);
  }

  /// '6B +88%', or just the grade at the top of the ladder.
  String get label => next == null ? grade : '$grade +${(fraction * 100).floor()}%';
}

/// The climbing level from [sessions], counting climbs in the [days] before
/// [now] (or since [since], when given). [flashOnly] counts flashes alone, for
/// the second line of the grade history. Null when nothing graded was sent.
ClimbLevel? levelFrom(Iterable<ClimbSession> sessions, {required DateTime now, int days = 60, DateTime? since, bool flashOnly = false}) {
  final from = since ?? now.subtract(Duration(days: days));
  final climbs = [
    for (final s in sessions)
      if (s.style == ClimbStyle.boulder && !s.start.isBefore(from) && !s.start.isAfter(now))
        for (final c in s.climbs)
          if (!flashOnly || c.outcome == ClimbOutcome.flash) c,
  ];
  final index = topTenAverageIndex(climbs);
  if (index == null) return null;
  final sends = climbs.where((c) => c.outcome.isSend && c.index != null).length;
  return ClimbLevel(index, sends < 10 ? sends : 10, sends);
}

/// The sends [levelFrom] averages, best first, with the session each is from.
List<(Climb, ClimbSession)> levelSends(Iterable<ClimbSession> sessions, {required DateTime now, int days = 60, DateTime? since, int top = 10}) {
  final from = since ?? now.subtract(Duration(days: days));
  final sends = [
    for (final s in sessions)
      if (s.style == ClimbStyle.boulder && !s.start.isBefore(from) && !s.start.isAfter(now))
        for (final c in s.climbs)
          if (c.outcome.isSend && c.index != null) (c, s),
  ]..sort((a, b) => b.$1.points.compareTo(a.$1.points));
  return sends.take(top).toList();
}

/// What [parseStravaClimbText] made of a session description.
class StravaClimbText {
  const StravaClimbText({required this.place, required this.climbs, required this.unknown, required this.ungraded});

  final String place;
  final List<Climb> climbs;

  /// Grade tokens we could not place on the ladder — worth showing, so a new
  /// gym's wording does not silently lose climbs.
  final List<String> unknown;

  /// Climbs logged as `?`: counted, but left out of grade stats.
  final int ungraded;

  bool get isEmpty => climbs.isEmpty && unknown.isEmpty;
}

final _placeRe = RegExp(r'I climbed at\s+(.+?)\s+with TopLogger', caseSensitive: false);
// A grade token: 3–9, an optional small-caps/plain letter, an optional plus.
final _gradeRe = RegExp(r'^[3-9](?:[ABCDabcdᴀʙᴄᴅ])?\+?$');

/// Reads a TopLogger-written Strava description:
///
///     Bouldering Session
///     I climbed at Sterk Spoor with TopLogger.
///     Boulders: ⚡ 6ʙ⁺, 6ʙ. ✅ 6ᴄ, 6ʙ⁺. <link>
///
/// `⚡` lists flashes, `✅` lists sends that were worked. Anything before the
/// first marker is prose, and `?` means the climb had no grade.
StravaClimbText parseStravaClimbText(String text, {WallAngle angle = WallAngle.vertical}) {
  final place = _placeRe.firstMatch(text)?.group(1)?.trim() ?? '';
  final climbs = <Climb>[];
  final unknown = <String>[];
  var ungraded = 0;

  // Cut the text into (marker, list) pieces. Everything before the first
  // marker — the headline and the "I climbed at …" line — is dropped.
  final markers = <(int, ClimbOutcome)>[];
  for (final m in RegExp(r'[⚡✅]').allMatches(text)) {
    markers.add((m.start, m.group(0) == '⚡' ? ClimbOutcome.flash : ClimbOutcome.sent));
  }
  for (var i = 0; i < markers.length; i++) {
    final (at, outcome) = markers[i];
    final to = i + 1 < markers.length ? markers[i + 1].$1 : text.length;
    var body = text.substring(at + 1, to);
    // The list ends at the sentence's full stop; a link may follow it.
    final stop = body.indexOf('.');
    // Grades never contain a full stop, so the first one ends the list and
    // anything after it (a link, more prose) is not ours.
    if (stop >= 0) body = body.substring(0, stop);
    for (final token in body.split(RegExp(r'[,;]'))) {
      final raw = token.trim();
      if (raw.isEmpty) continue;
      if (raw == '?') {
        ungraded++;
        climbs.add(Climb(grade: '', outcome: outcome, angle: angle));
        continue;
      }
      final g = normaliseGrade(raw);
      if (g.isNotEmpty && gradeIndex(g) != null) {
        climbs.add(Climb(grade: g, outcome: outcome, angle: angle));
      } else if (_gradeRe.hasMatch(raw) || g.isNotEmpty) {
        unknown.add(raw);
      }
    }
  }
  return StravaClimbText(place: place, climbs: climbs, unknown: unknown, ungraded: ungraded);
}

/// The level every [step] days for the last [weeks] weeks, oldest first, for
/// the grade history. A point with nothing sent in the 60 days before it is null.
List<(DateTime, ClimbLevel?)> levelHistory(Iterable<ClimbSession> sessions,
        {required DateTime now, int weeks = 12, int days = 60, int step = 7, bool flashOnly = false}) =>
    [
      for (var k = weeks * 7 ~/ step - 1; k >= 0; k--)
        (
          now.subtract(Duration(days: step * k)),
          levelFrom(sessions, now: now.subtract(Duration(days: step * k)), days: days, flashOnly: flashOnly),
        ),
    ];

/// Sends per rung for the grade pyramid: (flashed, worked). Tries and
/// ungraded climbs are left out, as in every grade stat.
Map<int, (int, int)> gradePyramid(Iterable<Climb> climbs) {
  final out = <int, (int, int)>{};
  for (final c in climbs) {
    final i = c.index;
    if (i == null || !c.outcome.isSend) continue;
    final (f, w) = out[i] ?? (0, 0);
    out[i] = c.outcome == ClimbOutcome.flash ? (f + 1, w) : (f, w + 1);
  }
  return out;
}

/// Ascents (flashes and sends, not tries) in each of the last [weeks] weeks,
/// Monday to Sunday, oldest first; the last is this week. Also this week's
/// share of flashes among its ascents (0 when there are none).
({List<int> perWeek, double flashShare}) weeklyAscents(Iterable<ClimbSession> sessions, {required DateTime now, int weeks = 24}) {
  final today = DateTime(now.year, now.month, now.day);
  final monday = today.subtract(Duration(days: today.weekday - 1));
  final first = DateTime(monday.year, monday.month, monday.day - 7 * (weeks - 1));
  final per = List.filled(weeks, 0);
  var flashes = 0;
  for (final s in sessions) {
    final d = DateTime(s.start.year, s.start.month, s.start.day);
    if (d.isBefore(first) || d.isAfter(today)) continue;
    final w = (DateTime.utc(d.year, d.month, d.day).difference(DateTime.utc(first.year, first.month, first.day)).inDays) ~/ 7;
    for (final c in s.climbs) {
      if (c.outcome == ClimbOutcome.tried) continue;
      per[w]++;
      if (w == weeks - 1 && c.outcome == ClimbOutcome.flash) flashes++;
    }
  }
  return (perWeek: per, flashShare: per.last == 0 ? 0 : flashes / per.last);
}
