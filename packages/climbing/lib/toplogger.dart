// Reads a TopLogger session from its public link (the one TopLogger puts in the
// Strava description). TopLogger's GraphQL API is unofficial: if it changes,
// fetching fails and the paste sheet falls back to parsing the text.
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'climbing.dart';

/// The ids in a link like `app.toplogger.nu/en-us/users/<user>/sessions/<session>`.
class TopLoggerLink {
  const TopLoggerLink(this.userId, this.sessionId);
  final String userId, sessionId;
}

TopLoggerLink? findTopLoggerLink(String text) {
  final m = RegExp(r'toplogger\.nu/(?:[a-z]{2}(?:-[a-z]{2})?/)?users/([A-Za-z0-9]+)/sessions/([A-Za-z0-9]+)').firstMatch(text);
  return m == null ? null : TopLoggerLink(m.group(1)!, m.group(2)!);
}

/// A session as TopLogger knows it.
class TopLoggerSession {
  const TopLoggerSession({required this.id, required this.gym, required this.day, required this.tries, required this.climbs});

  final String id, gym;
  final DateTime? day;

  /// All attempts that day (TopLogger doesn't say which climb took how many).
  final int? tries;
  final List<Climb> climbs;

  /// From the `climbDay` object of the GraphQL response.
  factory TopLoggerSession.fromJson(Map<String, dynamic> d) {
    final climbs = <Climb>[];
    for (final e in (d['climbUserDays'] as List? ?? const [])) {
      final m = (e as Map).cast<String, dynamic>();
      final c = (m['climb'] as Map?)?.cast<String, dynamic>() ?? const {};
      if ((c['climbType'] ?? 'boulder') != 'boulder') continue;
      climbs.add(Climb(
        grade: topLoggerGrade((c['grade'] as num?)?.toDouble()),
        outcome: switch (m['tickType']) {
          2 => ClimbOutcome.flash,
          1 => ClimbOutcome.sent,
          _ => ClimbOutcome.tried,
        },
        repeat: m['wasRepeat'] == true,
        name: (c['label'] as String? ?? '').trim(),
        hold: ((c['holdColor'] as Map?)?['color'] as String? ?? '').trim(),
      ));
    }
    return TopLoggerSession(
      id: d['id'] as String? ?? '',
      gym: ((d['gym'] as Map?)?['name'] as String? ?? '').trim(),
      day: DateTime.tryParse(d['statsAtDate'] as String? ?? ''),
      tries: (d['bouldersTotalTries'] as num?)?.toInt(),
      climbs: climbs,
    );
  }
}

/// TopLogger stores Font grades as numbers: 500 = 5A, a third of a grade (one
/// half-grade step on our ladder) ≈ 16.7, so 600 = 6A and 650 = 6B+.
String topLoggerGrade(double? g) {
  if (g == null || g <= 0) return '';
  final i = ((g - 300) / (100 / 6)).round();
  return i >= 0 && i < kGradeLadder.length ? kGradeLadder[i] : '';
}

const _query = r'''
query($id: ID!, $userId: ID!) {
  climbDay(id: $id, userId: $userId) {
    id statsAtDate bouldersTotalTries
    gym { name }
    climbUserDays { tickType wasRepeat climb { climbType grade label holdColor { color } } }
  }
}''';

/// Widget tests put a fake client here (they can't reach the network).
http.Client? topLoggerTestClient;

/// Fetches a session. Throws on network or API errors.
Future<TopLoggerSession> fetchTopLoggerSession(TopLoggerLink link, {http.Client? client}) async {
  client ??= topLoggerTestClient;
  final c = client ?? http.Client();
  try {
    final r = await c
        .post(
          Uri.parse('https://app.toplogger.nu/graphql'),
          headers: {'content-type': 'application/json'},
          body: jsonEncode({'query': _query, 'variables': {'id': link.sessionId, 'userId': link.userId}}),
        )
        .timeout(const Duration(seconds: 15));
    if (r.statusCode != 200) throw Exception('TopLogger answered ${r.statusCode}');
    final j = jsonDecode(utf8.decode(r.bodyBytes)) as Map<String, dynamic>;
    final d = (j['data'] as Map?)?['climbDay'];
    if (d == null) throw Exception('TopLogger has no such session');
    return TopLoggerSession.fromJson((d as Map).cast<String, dynamic>());
  } finally {
    if (client == null) c.close();
  }
}
