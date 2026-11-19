// Where climbing keeps its sessions and places (climbing extraction, step 3).
// The climbing screens will talk only to this, so the same screens run inside
// hibi (over its state) and in the standalone climbing app (over its own store).
import 'dart:async';

import 'package:hibi_protocol/hibi_protocol.dart';

import 'climbing.dart';
import 'events.dart';

abstract interface class ClimbingStore {
  /// Every session, oldest first.
  List<ClimbSession> get sessions;

  /// Saved places plus names used in sessions, most used first.
  List<ClimbPlace> get places;

  String newId();
  void add(ClimbSession s);

  /// Replaces the session with the same id (adds it if there's none).
  void update(ClimbSession s);

  /// Removes a session and returns it, for undo.
  ClimbSession? remove(String id);

  /// Saves [p]; with [was], it replaces that place and renames it in its sessions.
  void savePlace(ClimbPlace p, {String? was});

  /// Fires after every change.
  Stream<void> get changes;
}

/// A store in memory: the standalone app's (with its own saving around it) and the tests'.
class MemoryClimbingStore implements ClimbingStore {
  MemoryClimbingStore({List<ClimbSession>? sessions, List<ClimbPlace>? places})
      : _sessions = [...?sessions]..sort((a, b) => a.start.compareTo(b.start)),
        _places = [...?places];

  final List<ClimbSession> _sessions;
  final List<ClimbPlace> _places;
  final _changes = StreamController<void>.broadcast();
  var _seq = 0;

  @override
  List<ClimbSession> get sessions => List.unmodifiable(_sessions);

  @override
  List<ClimbPlace> get places => placesFrom(_places, _sessions);

  @override
  String newId() => 'c${DateTime.now().microsecondsSinceEpoch}_${_seq++}';

  void _changed() {
    _sessions.sort((a, b) => a.start.compareTo(b.start));
    _changes.add(null);
  }

  @override
  void add(ClimbSession s) {
    _sessions.add(s);
    _changed();
  }

  @override
  void update(ClimbSession s) {
    final i = _sessions.indexWhere((x) => x.id == s.id);
    if (i < 0) return add(s);
    _sessions[i] = s;
    _changed();
  }

  @override
  ClimbSession? remove(String id) {
    final i = _sessions.indexWhere((x) => x.id == id);
    if (i < 0) return null;
    final s = _sessions.removeAt(i);
    _changed();
    return s;
  }

  @override
  void savePlace(ClimbPlace p, {String? was}) {
    final old = (was ?? p.name).trim().toLowerCase();
    _places.removeWhere((x) => x.name.trim().toLowerCase() == old || x.name.trim().toLowerCase() == p.name.trim().toLowerCase());
    _places.add(p);
    if (was != null && was.trim() != p.name.trim()) {
      for (var i = 0; i < _sessions.length; i++) {
        if (_sessions[i].place.trim().toLowerCase() == old) _sessions[i] = _sessions[i].copyWith(place: p.name.trim());
      }
    }
    _changed();
  }

  @override
  Stream<void> get changes => _changes.stream;

  /// Everything as protocol events, to save or to share with hibi.
  List<Event> toEvents({String device = 'climb-app', required DateTime recordedAt}) =>
      [...sessionsToEvents(_sessions, device: device, recordedAt: recordedAt), ...placesToEvents(_places, device: device, recordedAt: recordedAt)];

  /// A store from saved or shared events.
  factory MemoryClimbingStore.fromEvents(Iterable<Event> events) => MemoryClimbingStore(sessions: sessionsFromEvents(events), places: placesFromEvents(events));
}
