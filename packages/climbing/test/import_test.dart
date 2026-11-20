import 'package:climbing/places/import.dart';
import 'package:climbing/places/place.dart';
import 'package:climbing/places/place_tree.dart';
import 'package:test/test.dart';

void main() {
  test('Overpass: kinds, grades, outlines, and parents from relations or outlines', () {
    final elements = [
      // an area outline (closed way)
      {
        'type': 'way', 'id': 10, 'tags': {'climbing': 'area', 'name': 'Hrad Devín', 'sport': 'climbing'},
        'geometry': [
          {'lat': 48.170, 'lon': 16.970}, {'lat': 48.170, 'lon': 16.990}, {'lat': 48.180, 'lon': 16.990}, {'lat': 48.180, 'lon': 16.970}, {'lat': 48.170, 'lon': 16.970},
        ],
      },
      // a boulder inside it, no relation
      {'type': 'node', 'id': 1, 'lat': 48.175, 'lon': 16.980, 'tags': {'climbing': 'boulder', 'name': 'Veľký kameň'}},
      // a crag relation listing a problem
      {'type': 'relation', 'id': 20, 'tags': {'climbing': 'crag', 'name': 'Pod hradom'}, 'bounds': {'minlat': 48.171, 'minlon': 16.971, 'maxlat': 48.173, 'maxlon': 16.973},
        'members': [{'type': 'node', 'ref': 2, 'role': ''}]},
      {'type': 'node', 'id': 2, 'lat': 48.172, 'lon': 16.972, 'tags': {'climbing': 'route_bottom', 'name': 'Zlatá hrana', 'climbing:grade:font': '6b+'}},
      // far away, nothing around it
      {'type': 'node', 'id': 3, 'lat': 49.0, 'lon': 18.0, 'tags': {'climbing': 'boulder', 'name': 'Lone stone', 'climbing:grade:font': 'nonsense'}},
      // a gym
      {'type': 'way', 'id': 30, 'tags': {'sport': 'climbing', 'leisure': 'sports_centre', 'name': 'Boulder hall'}, 'center': {'lat': 48.15, 'lon': 17.12}},
      // not climbing, and an unnamed area: both skipped
      {'type': 'node', 'id': 4, 'lat': 48.0, 'lon': 17.0, 'tags': {'amenity': 'cafe', 'name': 'Café'}},
      {'type': 'node', 'id': 5, 'lat': 48.0, 'lon': 17.0, 'tags': {'climbing': 'area'}},
    ];
    final places = placesFromOverpass(elements, countryId: 'sk');
    final byId = {for (final p in places) p.id: p};
    expect(byId.keys, unorderedEquals(['osm-way-10', 'osm-node-1', 'osm-relation-20', 'osm-node-2', 'osm-node-3', 'osm-way-30']));
    expect(byId['osm-way-10']!.kind, PlaceKind.area);
    expect(byId['osm-way-10']!.geometry, isA<PolygonGeometry>());
    expect((byId['osm-way-10']!.geometry as PolygonGeometry).ring, hasLength(4));
    expect(byId['osm-way-10']!.parentId, 'sk');
    expect(byId['osm-node-1']!.parentId, 'osm-way-10'); // inside the outline
    expect(byId['osm-relation-20']!.kind, PlaceKind.sector);
    expect(byId['osm-relation-20']!.parentId, 'osm-way-10'); // its bounds' centre is inside
    expect(byId['osm-node-2']!.parentId, 'osm-relation-20'); // relation member
    expect(byId['osm-node-2']!.grade, '6B+');
    expect(byId['osm-node-3']!.parentId, 'sk');
    expect(byId['osm-node-3']!.grade, '');
    final gym = byId['osm-way-30']!;
    expect(gym.kind, PlaceKind.gymWall);
    expect(gym.indoor, isTrue);
    expect(gym.gradeSystem.isFont, isFalse);
    for (final p in places) {
      expect(p.licence, 'ODbL');
      expect(p.source, startsWith('osm:'));
    }
    final tree = PlaceTree([const Place(id: 'sk', kind: PlaceKind.country, name: 'Slovakia'), ...places]);
    expect(tree.pathLabel('osm-node-2'), 'Slovakia › Hrad Devín › Pod hradom › Zlatá hrana');
  });

  test('the Overpass query asks for climbing in the country', () {
    final q = overpassQuery('sk');
    expect(q, contains('"ISO3166-1"="SK"'));
    expect(q, contains('nwr["climbing"]'));
    expect(q, contains('out tags geom'));
  });

  test('OpenBeta: depth gives the kind, boulders and bouldering problems only, CC0', () {
    final area = {
      'uuid': 'c1', 'areaName': 'Slovakia', 'metadata': {'lat': 0, 'lng': 0, 'leaf': false, 'isBoulder': false},
      'children': [
        {
          'uuid': 'r1', 'areaName': 'Bratislava', 'metadata': {'lat': 48.15, 'lng': 17.1},
          'children': [
            {
              'uuid': 'a1', 'areaName': 'Sandberg', 'metadata': {'lat': 48.2, 'lng': 16.97},
              'children': [
                {
                  'uuid': 'b1', 'areaName': 'Pieskovec', 'metadata': {'lat': 48.201, 'lng': 16.974, 'leaf': true, 'isBoulder': true},
                  'climbs': [
                    {'uuid': 'k1', 'name': 'Mušľa', 'type': {'bouldering': true}, 'grades': {'font': '6c', 'vscale': 'V5'}},
                    {'uuid': 'k2', 'name': 'Sport route', 'type': {'bouldering': false}, 'grades': {'font': null}},
                  ],
                },
                {'uuid': 's1', 'areaName': 'Upper wall', 'metadata': {'lat': 48.202, 'lng': 16.975}},
              ],
            },
          ],
        },
      ],
    };
    final places = placesFromOpenBeta(area);
    final byId = {for (final p in places) p.id: p};
    expect(byId.keys, ['ob-c1', 'ob-r1', 'ob-a1', 'ob-b1', 'ob-k1', 'ob-s1']);
    expect(byId['ob-c1']!.kind, PlaceKind.country);
    expect(byId['ob-c1']!.geometry, isNull); // 0,0 is OpenBeta's "no location"
    expect(byId['ob-r1']!.kind, PlaceKind.region);
    expect(byId['ob-a1']!.kind, PlaceKind.area);
    expect(byId['ob-b1']!.kind, PlaceKind.boulder);
    expect(byId['ob-s1']!.kind, PlaceKind.sector);
    expect(byId['ob-k1']!.kind, PlaceKind.problem);
    expect(byId['ob-k1']!.grade, '6C');
    expect(byId['ob-k1']!.parentId, 'ob-b1');
    for (final p in places) {
      expect(p.licence, 'CC0');
    }
    expect(PlaceTree(places).pathLabel('ob-k1'), 'Slovakia › Bratislava › Sandberg › Pieskovec › Mušľa');
  });

  test('the OpenBeta query nests children and asks for Font grades', () {
    final q = openBetaQuery(depth: 2);
    expect('children'.allMatches(q).length, 2);
    expect(q, contains('grades { font vscale }'));
  });

  test('point in polygon', () {
    final sq = [const LatLng(0, 0), const LatLng(0, 1), const LatLng(1, 1), const LatLng(1, 0)];
    expect(pointInPolygon(const LatLng(0.5, 0.5), sq), isTrue);
    expect(pointInPolygon(const LatLng(1.5, 0.5), sq), isFalse);
  });

  test('source, licence and grade survive JSON', () {
    const p = Place(id: 'x', kind: PlaceKind.problem, name: 'X', grade: '7A', source: 'openbeta:x', licence: 'CC0');
    final back = Place.fromJson(p.toJson());
    expect((back.grade, back.source, back.licence), ('7A', 'openbeta:x', 'CC0'));
    expect(Place.fromJson({'id': 'y', 'kind': 'area', 'name': 'Y'}).source, 'manual');
  });
}
