// Climb: the standalone climbing app (docs/architecture/climbing-extraction.md,
// step 5). The same screens as hibi's climbing module (packages/hibi_climbing_ui),
// over its own store. "Export for hibi" writes the climbs as hibi protocol
// events, which hibi imports (step 6).
import 'dart:convert';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:hibi_climbing_cloud/climbing_cloud.dart';
import 'package:hibi_climbing_map/climbing_map.dart';
import 'package:hibi_climbing_ui/climbing_ui.dart';


import 'climb_host.dart';
import 'guide_preview.dart';
import 'shared_places.dart';
import 'storage/text_box.dart';

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
  runApp(ClimbApp(cloud: cloud, placesCache: await openTextBox('shared_places.json')));
}

final climbTheme = ThemeData(
  brightness: Brightness.dark,
  colorSchemeSeed: const Color(0xFFF2A65A),
  scaffoldBackgroundColor: const Color(0xFF0E121A),
  useMaterial3: true,
);

class ClimbApp extends StatelessWidget {
  const ClimbApp({super.key, this.cloud, this.placesCache});

  /// Null when the build has no server keys: nothing is shared.
  final ClimbCloud? cloud;
    final TextBox? placesCache;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Climb',
    debugShowCheckedModeBanner: false,
    theme: climbTheme,
        locale: const Locale('en', 'GB'), // dates as DD/MM/YYYY
        supportedLocales: const [Locale('en', 'GB')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
    home: ClimbHome(
      cloud: cloud,
      places: () => SharedPlaces.load(cloud: cloud, cacheFile: placesCache, store: ClimbingHost.instance.store),
    ),
  );
}

/// Three tabs: your climbs, the map, and friends (your account for now).
/// The map isn't built (and loads no tiles) until its tab is opened.
class ClimbHome extends StatefulWidget {
  const ClimbHome({super.key, this.places, this.cloud, this.tiles, this.initialTab = const int.fromEnvironment('CLIMB_TAB')});

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

  @override
  void initState() {
    super.initState();
    _loadPlaces();
  }

  Future<SharedPlaces> _loadPlaces() => _places ??= (widget.places ?? () async => SharedPlaces(bundled: const []))().then((p) {
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
            places: data.tree,
            tiles: widget.tiles ?? MapTiles.fromEnvironment(),
            editor: data.cloud == null ? null : (_editor ??= CloudPlaceEditor(data)),
            notice: data.problem,
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
            title: const Text('Climb'),
            actions: [IconButton(tooltip: 'Export for hibi', onPressed: () => _export(context), icon: const Icon(Icons.ios_share_rounded))],
          )
        : null,
    body: IndexedStack(
      index: _tab,
      children: [
        const SafeArea(child: ClimbSection()),
        if (_tab == 1 || _mapOpened) _map() else const SizedBox.shrink(),
        SafeArea(child: AccountPanel(cloud: widget.cloud)),
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
