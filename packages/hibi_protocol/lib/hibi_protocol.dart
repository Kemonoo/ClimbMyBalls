// The hibi protocol v0.1 (docs/protocol/v0.1.md): the smallest shared shape
// for events, module manifests, sources, goals and progress metrics. Kept to
// what climbing, the reference module, needs; more comes when a module needs it.
library;

/// Who wrote an event: a connector or app, on a device.
class SourceRef {
  const SourceRef(this.id, {this.device = '', this.app = ''});
  final String id, device, app;

  Map<String, Object?> toJson() => {'id': id, if (device.isNotEmpty) 'device': device, if (app.isNotEmpty) 'app': app};
  factory SourceRef.fromJson(Map j) => SourceRef('${j['id']}', device: '${j['device'] ?? ''}', app: '${j['app'] ?? ''}');
}

/// One thing recorded, by any module. Append-only: a correction is a new
/// event that [replaces] the old one; a deletion is an event with [deleted].
class Event {
  const Event({
    required this.id,
    required this.module,
    required this.type,
    required this.at,
    this.end,
    this.data = const {},
    required this.source,
    required this.recordedAt,
    this.replaces,
    this.deleted = false,
  });

  static const version = 1;

  final String id, module, type;

  /// When it happened, with its offset kept as written.
  final DateTime at;
  final DateTime? end;
  final Map<String, Object?> data;
  final SourceRef source;
  final DateTime recordedAt;
  final String? replaces;
  final bool deleted;

  Map<String, Object?> toJson() => {
        'v': version,
        'id': id,
        'module': module,
        'type': type,
        'at': at.toIso8601String(),
        'end': end?.toIso8601String(),
        'data': data,
        'source': source.toJson(),
        'recordedAt': recordedAt.toIso8601String(),
        'replaces': replaces,
        'deleted': deleted,
      };

  factory Event.fromJson(Map j) => Event(
        id: '${j['id']}',
        module: '${j['module']}',
        type: '${j['type']}',
        at: DateTime.parse('${j['at']}'),
        end: DateTime.tryParse('${j['end'] ?? ''}'),
        data: ((j['data'] as Map?) ?? const {}).cast<String, Object?>(),
        source: SourceRef.fromJson((j['source'] as Map?) ?? const {'id': 'unknown'}),
        recordedAt: DateTime.parse('${j['recordedAt']}'),
        replaces: j['replaces'] as String?,
        deleted: j['deleted'] == true,
      );
}

/// The live events: a replacement wins over what it replaces, deletions drop out.
List<Event> current(Iterable<Event> events) {
  final replaced = {for (final e in events) if (e.replaces != null) e.replaces!};
  final out = <Event>[];
  for (final e in events) {
    if (replaced.contains(e.id) || e.deleted) continue;
    out.add(e);
  }
  return out;
}

/// What a module is about. Levels apply to [skill] only (ADR 0020).
enum ModuleKind { skill, routine, abstain, maintenance, consumption, measurement }

class EventType {
  const EventType(this.type, this.fields, {this.span = false});
  final String type;

  /// Field name -> its type (protocol v0.1 section 2), e.g. 'int', 'enum:a,b', 'ref:climbing.session'.
  final Map<String, String> fields;
  final bool span;

  Map<String, Object?> toJson() => {'type': type, if (span) 'span': true, 'fields': fields};
  factory EventType.fromJson(Map j) => EventType('${j['type']}', ((j['fields'] as Map?) ?? const {}).cast<String, String>(), span: j['span'] == true);
}

/// How a metric is judged (ADR 0018): more up to a target, a range, a cap, or just a trend.
class Judge {
  const Judge(this.kind, {this.min, this.max, this.target});
  final String kind; // more | range | cap | trend
  final num? min, max, target;

  Map<String, Object?> toJson() => {'kind': kind, 'min': ?min, 'max': ?max, 'target': ?target};
  factory Judge.fromJson(Map? j) => j == null ? const Judge('trend') : Judge('${j['kind']}', min: j['min'] as num?, max: j['max'] as num?, target: j['target'] as num?);
}

/// A progress metric, computed from events, never stored.
class MetricDef {
  const MetricDef(this.id, {required this.of, required this.agg, this.field, this.per, this.window, this.judge = const Judge('trend'), this.levels});
  final String id, of, agg; // agg: count | sum | avg | max | latest | fn:<name>
  final String? field, per, window, levels; // per: day | week; window: e.g. 60d; levels: dreyfus
  final Judge judge;

  Map<String, Object?> toJson() => {'id': id, 'of': of, 'agg': agg, 'field': ?field, 'per': ?per, 'window': ?window, 'judge': judge.toJson(), 'levels': ?levels};
  factory MetricDef.fromJson(Map j) => MetricDef('${j['id']}',
      of: '${j['of']}', agg: '${j['agg']}', field: j['field'] as String?, per: j['per'] as String?, window: j['window'] as String?, judge: Judge.fromJson(j['judge'] as Map?), levels: j['levels'] as String?);
}

/// A goal the person picked: a metric reaching a target, maybe by a date.
class Goal {
  const Goal({required this.id, required this.module, required this.title, required this.metric, required this.op, required this.value, this.by});
  final String id, module, title, metric, op; // op: >= | <= | ==
  final Object value;
  final DateTime? by;

  Map<String, Object?> toJson() => {'id': id, 'module': module, 'title': title, 'metric': metric, 'target': {'op': op, 'value': value}, 'by': by?.toIso8601String().substring(0, 10)};
  factory Goal.fromJson(Map j) => Goal(
        id: '${j['id']}',
        module: '${j['module']}',
        title: '${j['title']}',
        metric: '${j['metric']}',
        op: '${(j['target'] as Map)['op']}',
        value: (j['target'] as Map)['value'] as Object,
        by: DateTime.tryParse('${j['by'] ?? ''}'),
      );
}

/// The Dreyfus stages, for skill modules only.
const kDreyfus = ['novice', 'advanced beginner', 'competent', 'proficient', 'expert'];

class ModuleManifest {
  const ModuleManifest({required this.id, required this.name, required this.version, required this.kind, this.events = const [], this.metrics = const [], this.goals = const []});
  static const protocol = 1;
  final String id, name, version;
  final ModuleKind kind;
  final List<EventType> events;
  final List<MetricDef> metrics;

  /// Goal templates the person can pick from.
  final List<Goal> goals;

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'version': version,
        'protocol': protocol,
        'kind': kind.name,
        'events': events.map((e) => e.toJson()).toList(),
        'metrics': metrics.map((m) => m.toJson()).toList(),
        'goals': goals.map((g) => g.toJson()).toList(),
      };

  factory ModuleManifest.fromJson(Map j) => ModuleManifest(
        id: '${j['id']}',
        name: '${j['name']}',
        version: '${j['version']}',
        kind: ModuleKind.values.asNameMap()['${j['kind']}'] ?? ModuleKind.routine,
        events: [for (final e in (j['events'] as List? ?? const []).cast<Map>()) EventType.fromJson(e)],
        metrics: [for (final m in (j['metrics'] as List? ?? const []).cast<Map>()) MetricDef.fromJson(m)],
        goals: [for (final g in (j['goals'] as List? ?? const []).cast<Map>()) Goal.fromJson(g)],
      );
}
