import 'update.dart';

/// The web app is always the newest: the page itself updates.
bool get updatesWork => false;

Future<Release?> checkForUpdate() async => null;

Future<String?> installUpdate(Release r, void Function(double) progress) async => 'Updates come with the page itself.';
