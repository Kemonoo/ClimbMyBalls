// Climb: the standalone climbing app (docs/architecture/climbing-extraction.md,
// step 5). The same screens as hibi's climbing module (packages/climbing_ui),
// over its own store. "Export for hibi" writes the climbs as hibi protocol
// events, which hibi imports (step 6).
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:climbing_cloud/climbing_cloud.dart';
import 'package:climbing_map/climbing_map.dart';
import 'package:climbing_ui/climbing_ui.dart';


import 'package:connectivity_plus/connectivity_plus.dart';

import 'climb_host.dart';
import 'outbox.dart';
import 'storage/map_store.dart';
import 'storage/photo_box.dart';
import 'guide_preview.dart';
import 'shared_places.dart';
import 'upload_button.dart';
import 'storage/text_box.dart';
import 'update/update.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (const String.fromEnvironment('CLIMB_PREVIEW').isNotEmpty) {
    // a bundled guide's sections without the server, for checking screens
    final g = await GuidePreview.load();
    runApp(MaterialApp(debugShowCheckedModeBanner: false, theme: climbTheme,
        locale: const Locale('en', 'GB'), // dates as DD/MM/YYYY
        supportedLocales: const [Locale('en', 'GB')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates, home: g.screen()));
    return;
  }
    ClimbingHost.instance = ClimbAppHost(EventFile(await openTextBox('climb_events.json')));
  final cloud = await ClimbCloud.start(CloudConfig.fromEnvironment());
  runApp(ClimbApp(cloud: cloud, placesCache: await openTextBox('shared_places.json'), outboxFile: await openTextBox('outbox.json')));
}

final climbTheme = ThemeData(
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFFF2A65A),
  scaffoldBackgroundColor: const Color(0xFF0E121A),
  useMaterial3: true,
);

class ClimbApp extends StatelessWidget {
  const ClimbApp({super.key, this.cloud, this.placesCache, this.outboxFile});

  /// Null when the build has no server keys: nothing is shared.
  final ClimbCloud? cloud;
    final TextBox? placesCache;

  /// Changes waiting for signal (#460).
  final TextBox? outboxFile;

  static Future<bool> _onWifi() async => (await Connectivity().checkConnectivity()).any((c) => c == ConnectivityResult.wifi || c == ConnectivityResult.ethernet);

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'ClimbMyBalls',
    debugShowCheckedModeBanner: false,
    theme: climbTheme,
        locale: const Locale('en', 'GB'), // dates as DD/MM/YYYY
        supportedLocales: const [Locale('en', 'GB')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: ClimbHome(
      cloud: cloud,
      places: () async {
        final p = await SharedPlaces.load(
          cloud: cloud,
          cacheFile: placesCache,
          store: ClimbingHost.instance.store,
          photos: await openPhotoBox(),
          outbox: Outbox.load(outboxFile),
          onWifi: _onWifi,
        );
        // back online (or onto Wi-Fi): send what waited, fetch what's new
        Connectivity().onConnectivityChanged.listen((c) {
          if (c.any((x) => x != ConnectivityResult.none)) p.refresh();
        });
        return p;
      },
      checkUpdate: updatesWork ? checkForUpdate : null,
    ),
  );
}

/// Three tabs: your climbs, the map, and friends (your account for now).
/// The map isn't built (and loads no tiles) until its tab is opened.
class ClimbHome extends StatefulWidget {
  const ClimbHome({super.key, this.places, this.cloud, this.tiles, this.checkUpdate, this.initialTab = const int.fromEnvironment('CLIMB_TAB')});

  /// Asks for a newer release (Android); null where updates don't apply.
  final Future<Release?> Function()? checkUpdate;

  /// The map's places, loaded the first time the map opens.
  final Future<SharedPlaces> Function()? places;
  final ClimbCloud? cloud;
  final MapTiles? tiles;

  /// 0 climbs, 1 map, 2 friends (`--dart-define=CLIMB_TAB=1` opens on the map).
  final int initialTab;

  @override
  State<ClimbHome> createState() => _ClimbHomeState();
}

class _ClimbHomeState extends State<ClimbHome> {
  late var _tab = widget.initialTab.clamp(0, 2);
    Future<SharedPlaces>? _places; // loaded at start: ascents sync onto the Climbs tab
  var _mapOpened = false; // the map (and its tiles) waits for its tab
  CloudPlaceEditor? _editor;
  SharedPlaces? _shared; // for the places an edit right can cover
  Future<OsmMap>? _osm; // the map's style, once

  @override
  void initState() {
    super.initState();
    _loadPlaces();
    if (widget.checkUpdate != null) Future<void>.delayed(const Duration(seconds: 3), () => _checkUpdate(quiet: true));
  }

  /// On start quietly; from the button it also says when you're up to date.
  Future<void> _checkUpdate({bool quiet = false}) async {
    final r = await widget.checkUpdate!();
    if (!mounted) return;
    if (r != null) return offerUpdate(context, r, installUpdate);
    if (!quiet) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('ClimbMyBalls $kClimbVersion is the newest.')));
  }

  Future<SharedPlaces> _loadPlaces() => _places ??= (widget.places ?? () async => SharedPlaces(bundled: const []))().then((p) {
    _shared = p;
    p.refresh();
    return p;
  });

  Future<void> _export(BuildContext context) async {
    final h = ClimbingHost.instance as ClimbAppHost;
    final events = h.store.toEvents(recordedAt: DateTime.now());
    final bytes = Uint8List.fromList(
      utf8.encode(const JsonEncoder.withIndent(' ').convert({'protocol': 1, 'module': 'climbing', 'events': events.map((e) => e.toJson()).toList()})),
    );
    final where = await FilePicker.saveFile(fileName: 'climbs-for-hibi.json', bytes: bytes, dialogTitle: 'Export for hibi');
    if (!context.mounted || where == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Exported ${h.store.sessions.length} sessions. In hibi: Climbing → Import.')));
  }

  Widget _map() {
        _loadPlaces();
    return FutureBuilder<SharedPlaces>(
      future: _places,
      builder: (context, snap) => switch (snap) {
        AsyncSnapshot(:final data?) => ListenableBuilder(
          listenable: data,
          builder: (context, _) => ClimbMapScreen(
            osm: _osm ??= openMapStore().then(OsmMap.load),
            places: data.tree,
            tiles: widget.tiles ?? MapTiles.fromEnvironment(),
            editor: data.cloud == null ? null : (_editor ??= CloudPlaceEditor(data)),
            notice: data.problem ?? data.waitingNote,
          ),
        ),
        AsyncSnapshot(:final error?) => Center(child: Text('Could not load places: $error')),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: _tab == 0
        ? AppBar(
            title: const Text('ClimbMyBalls'),
            actions: [
              if (widget.checkUpdate != null)
                IconButton(tooltip: 'Check for updates (Climb $kClimbVersion)', onPressed: _checkUpdate, icon: const Icon(Icons.system_update_outlined)),
              IconButton(tooltip: 'Export for hibi', onPressed: () => _export(context), icon: const Icon(Icons.ios_share_rounded)),
              if (_shared case final s? when s.cloud != null) UploadButton(places: s),
            ],
          )
        : null,
    body: IndexedStack(
      index: _tab,
      children: [
        const SafeArea(child: ClimbSection()),
        if (_tab == 1 || _mapOpened) _map() else const SizedBox.shrink(),
        SafeArea(child: AccountPanel(cloud: widget.cloud, places: () => _shared?.scopePlaces ?? const [])),
      ],
    ),
    bottomNavigationBar: NavigationBar(
      selectedIndex: _tab,
      onDestinationSelected: (i) {
                setState(() {
          _tab = i;
          if (i == 1) _mapOpened = true;
        });
        if (i != 2) _places?.then((p) => p.refresh()); // new places and your ascents, e.g. after signing in
      },
      destinations: const [
        NavigationDestination(icon: Icon(Icons.format_list_bulleted), label: 'Climbs'),
        NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'Map'),
        NavigationDestination(icon: Icon(Icons.group_outlined), selectedIcon: Icon(Icons.group), label: 'Friends'),
      ],
    ),
  );
}
