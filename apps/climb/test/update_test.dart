import 'dart:io';

import 'package:climb/climb_host.dart';
import 'package:climb/main.dart';
import 'package:climb/storage/text_box_io.dart';
import 'package:climb/shared_places.dart';
import 'package:climb/update/update.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:climbing_ui/climbing_ui.dart';

void main() {
  late Directory dir;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('climb_update');
    ClimbingHost.instance = ClimbAppHost(EventFile(FileBox(File('${dir.path}/empty.json'))));
  });
  tearDown(() => dir.deleteSync(recursive: true));

  test('versions compare by number, not by text', () {
    expect(isNewer('0.10.0', '0.9.1'), isTrue);
    expect(isNewer('v0.2.0', '0.2.0'), isFalse);
    expect(isNewer('0.2.1', '0.2.0+5'), isTrue);
    expect(isNewer('0.1.9', '0.2.0'), isFalse);
  });

  test('a newer release with an APK is offered; an older one or one without an APK is not', () {
    Map<String, dynamic> j(String tag, {bool apk = true}) => {
      'tag_name': tag,
      'body': 'Rights for friends.',
      'assets': [
        if (apk) {'name': 'climb-$tag.apk', 'browser_download_url': 'https://example.com/climb.apk'},
      ],
    };
    final r = releaseFrom(j('v0.3.0'), current: '0.2.0')!;
    expect((r.version, r.notes, r.apkUrl), ('0.3.0', 'Rights for friends.', 'https://example.com/climb.apk'));
    expect(releaseFrom(j('v0.2.0'), current: '0.2.0'), isNull);
    expect(releaseFrom(j('v0.3.0', apk: false), current: '0.2.0'), isNull);
  });

  testWidgets('on start a newer release is offered, Later closes it', (t) async {
    await t.pumpWidget(MaterialApp(
      home: ClimbHome(
        places: () async => SharedPlaces(bundled: const []),
        checkUpdate: () async => const Release('9.0.0', 'Faster map.', 'https://example.com/climb.apk'),
      ),
    ));
    await t.pump(const Duration(seconds: 4));
    await t.pumpAndSettle();
    expect(find.text('ClimbMyBalls 9.0.0 is out'), findsOneWidget);
    expect(find.text('Faster map.'), findsOneWidget);
    await t.tap(find.text('Later'));
    await t.pumpAndSettle();
    expect(find.text('ClimbMyBalls 9.0.0 is out'), findsNothing);
  });

  testWidgets('the button says when you have the newest', (t) async {
    await t.pumpWidget(MaterialApp(
      home: ClimbHome(places: () async => SharedPlaces(bundled: const []), checkUpdate: () async => null),
    ));
    await t.pump(const Duration(seconds: 4));
    await t.tap(find.byTooltip('Check for updates (Climb $kClimbVersion)'));
    await t.pumpAndSettle();
    expect(find.text('ClimbMyBalls $kClimbVersion is the newest.'), findsOneWidget);
  });
}
