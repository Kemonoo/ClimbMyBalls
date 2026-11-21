// Changes made on the phone wait here until they reach the server (#460):
// logging climbs, grade votes and stars, comments, new places and sections.
// Each change goes out at once when there is signal (or only on Wi-Fi, if
// you want); without it, it is kept and sent later, in order. Until then the
// app shows it as if it were already there: what the server last said, with
// the waiting changes on top.
import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:climbing_cloud/climbing_cloud.dart';

import 'storage/text_box.dart';

/// One waiting change: what it is ('tick.add', 'opinion', ...) and its data.
typedef PendingOp = ({String kind, Map<String, dynamic> data});

/// Whether [e] means "no connection" (then the change waits) rather than
/// "the server said no" (then it is dropped and reported).
bool isNoConnection(Object e) {
  if (e is TimeoutException) return true; // the rest by name: dart:io isn't on the web
  final s = e.toString();
  return s.contains('SocketException') ||
      s.contains('ClientException') ||
      s.contains('Failed host lookup') ||
      s.contains('Connection refused') ||
      s.contains('Connection closed') ||
      s.contains('Network is unreachable') ||
      s.contains('XMLHttpRequest error') ||
      s.contains('Failed to fetch');
}

/// A random UUID (v4), for rows made on the phone.
String newUuid([Random? random]) {
  final r = random ?? Random.secure();
  final b = List.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = [for (final x in b) x.toRadixString(16).padLeft(2, '0')].join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}

/// The waiting changes, the last answers from the server (to show without
/// signal), and the Wi-Fi-only choice; kept in one file.
class Outbox extends ChangeNotifier {
  Outbox({this.file, List<PendingOp>? ops, Map<String, dynamic>? answers, this.wifiOnly = false}) : ops = ops ?? [], answers = answers ?? {};

  final TextBox? file;
  final List<PendingOp> ops;

  /// The server's last answer per question (`ticks:<problem id>`, `mine`, ...).
  final Map<String, dynamic> answers;

  /// Send only on Wi-Fi; on mobile data changes wait.
  bool wifiOnly;

  /// What the last sending dropped because the server refused it.
  String? refused;

  static Outbox load(TextBox? file) {
    try {
      final text = file?.read();
      if (text != null) {
        final j = jsonDecode(text) as Map<String, dynamic>;
        return Outbox(
          file: file,
          ops: [for (final o in (j['ops'] as List? ?? const []).cast<Map>()) (kind: o['kind'] as String, data: (o['data'] as Map).cast<String, dynamic>())],
          answers: (j['answers'] as Map? ?? const {}).cast<String, dynamic>(),
          wifiOnly: j['wifiOnly'] == true,
        );
      }
    } catch (_) {} // a broken file starts empty
    return Outbox(file: file);
  }

  void save() => file?.write(
    jsonEncode({
      'wifiOnly': wifiOnly,
      'ops': [
        for (final o in ops) {'kind': o.kind, 'data': o.data},
      ],
      'answers': answers,
    }),
  );

  void add(String kind, Map<String, dynamic> data) {
    ops.add((kind: kind, data: data));
    save();
    notifyListeners();
  }

  void setWifiOnly(bool v) {
    wifiOnly = v;
    save();
    notifyListeners();
  }

  void remember(String key, Object? answer) {
    answers[key] = answer;
    save();
  }

  /// Sends the waiting changes in order. Stops at the first one that finds
  /// no connection (the rest wait); drops one the server refuses. Returns how
  /// many went out.
  Future<int> flush(Future<void> Function(PendingOp op) send) async {
    var sent = 0;
    refused = null;
    while (ops.isNotEmpty) {
      final op = ops.first;
      try {
        await send(op);
      } catch (e) {
        if (isNoConnection(e)) break;
        refused = 'A change could not be saved and was dropped (${op.kind}): $e';
      }
      ops.removeAt(0);
      sent++;
      save();
    }
    if (sent > 0 || refused != null) notifyListeners();
    return sent;
  }

  // ---- the waiting changes laid over the server's answers ----

  List<CloudTick> overTicks(List<CloudTick> ticks, {String? problemId, String? userId}) {
    var out = [...ticks];
    for (final o in ops) {
      final d = o.data;
      switch (o.kind) {
        case 'tick.add' when (problemId == null || d['problem_id'] == problemId) && (userId == null || d['user_id'] == userId):
          out.removeWhere((t) => t.id == d['id']);
          out.add(CloudTick.fromRow(d));
        case 'tick.remove':
          out.removeWhere((t) => t.id == d['id']);
        case 'tick.day':
          out = [for (final t in out) t.id == d['id'] ? t.copyWith(day: DateTime.parse(d['day'] as String)) : t];
      }
    }
    return out;
  }

  List<CloudOpinion> overOpinions(List<CloudOpinion> opinions, Set<String> problemIds) {
    final out = [...opinions];
    for (final o in ops) {
      if (o.kind != 'opinion' || !problemIds.contains(o.data['problem_id'])) continue;
      out.removeWhere((x) => x.problemId == o.data['problem_id'] && x.userId == o.data['user_id']);
      out.add(CloudOpinion.fromRow(o.data));
    }
    return out;
  }

  List<CloudComment> overComments(List<CloudComment> comments, String problemId) {
    final out = [...comments];
    for (final o in ops) {
      if (o.kind == 'comment.add' && o.data['problem_id'] == problemId) {
        out.removeWhere((c) => c.id == o.data['id']);
        out.add(CloudComment.fromRow(o.data));
      } else if (o.kind == 'comment.remove') {
        out.removeWhere((c) => c.id == o.data['id']);
      }
    }
    return out;
  }
}
