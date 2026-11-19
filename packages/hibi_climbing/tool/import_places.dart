// One-off import of climbing places from open data (docs/climb/plan.md, step 5).
// Not part of any app. Writes a JSON list of places with source and licence.
//
//   dart run tool/import_places.dart --osm SK --osm CZ --out places.json
//   dart run tool/import_places.dart --openbeta <area uuid> --out places.json
//
// OSM data is ODbL: attribution, and a database built from it stays ODbL.
// OpenBeta data is CC0. No other sources (see the plan's licence table).
import 'dart:convert';
import 'dart:io';

import 'package:hibi_climbing/places/import.dart';
import 'package:hibi_climbing/places/place.dart';
import 'package:http/http.dart' as http;

const _countries = {'SK': 'Slovakia', 'CZ': 'Czechia'};
const _agent = 'climb-import/0.1 (one-off open data import)';

Future<void> main(List<String> args) async {
  final osm = <String>[], openBeta = <String>[];
  var outPath = 'places.json';
  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--osm':
        osm.add(args[++i].toUpperCase());
      case '--openbeta':
        openBeta.add(args[++i]);
      case '--out':
        outPath = args[++i];
      default:
        stderr.writeln('Unknown argument ${args[i]}');
        exit(64);
    }
  }
  if (osm.isEmpty && openBeta.isEmpty) {
    stderr.writeln('Nothing to import. Use --osm SK and/or --openbeta <uuid>.');
    exit(64);
  }
  final places = <Place>[];
  for (final iso in osm) {
    final countryId = 'country-${iso.toLowerCase()}';
    places.add(Place(id: countryId, kind: PlaceKind.country, name: _countries[iso] ?? iso, source: 'manual'));
    final r = await _withBackoff(() => http.post(Uri.parse('https://overpass-api.de/api/interpreter'),
        headers: {'User-Agent': _agent}, body: {'data': overpassQuery(iso)}));
    if (r.statusCode != 200) throw HttpException('Overpass ${r.statusCode}: ${r.body.substring(0, r.body.length.clamp(0, 200))}');
    final got = placesFromOverpass((jsonDecode(r.body) as Map)['elements'] as List, countryId: countryId);
    stderr.writeln('OSM $iso: ${got.length} places');
    places.addAll(got);
  }
  for (final uuid in openBeta) {
    final r = await http.post(Uri.parse('https://api.openbeta.io'),
        headers: {'Content-Type': 'application/json', 'User-Agent': _agent},
        body: jsonEncode({'query': openBetaQuery(), 'variables': {'uuid': uuid}}));
    if (r.statusCode != 200) throw HttpException('OpenBeta ${r.statusCode}');
    final area = ((jsonDecode(r.body) as Map)['data'] as Map?)?['area'] as Map?;
    if (area == null) throw StateError('OpenBeta has no area $uuid');
    final got = placesFromOpenBeta(area.cast<String, dynamic>());
    stderr.writeln('OpenBeta $uuid: ${got.length} places');
    places.addAll(got);
  }
  await File(outPath).writeAsString(const JsonEncoder.withIndent(' ').convert([for (final p in places) p.toJson()]));
  stderr.writeln('Wrote ${places.length} places to $outPath');
}

/// Overpass answers 429, 502 or 504 when busy and asks for exponential backoff.
Future<http.Response> _withBackoff(Future<http.Response> Function() send) async {
  var wait = const Duration(seconds: 15);
  for (var i = 0;; i++) {
    final r = await send();
    if ((r.statusCode != 429 && r.statusCode != 502 && r.statusCode != 504) || i == 3) return r;
    stderr.writeln('Busy (${r.statusCode}), retrying in ${wait.inSeconds} s');
    await Future<void>.delayed(wait);
    wait *= 2;
  }
}
