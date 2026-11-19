# ClimbMyBalls

A climbing app for a small group of friends: a map of crags and boulders, topo photos with the routes drawn on them, ascents, and who climbed what.

- **Map**: Mapy.com outdoor, road and aerial maps; boulders drawn as shapes; tap the map to add a place.
- **Boulders and sections**: each boulder has photos of its sides ("sections") with lines, letters and numbers. Tap a line to read the route, tap a letter to see every route through it. Boulders and rope routes are kept apart.
- **Routes**: grade (Font for boulders, UIAA for rope), sit or stand start, how it goes, and everyone's ascents.
- **Climbs**: your sessions, levels and grades, logged by hand or from the routes you tick.
- **Friends**: accounts with Google or email; new accounts wait for an admin to let them in (a small group, at most 30).

## Use it

- **Any phone or computer**: open the web app at https://kemonoo.github.io/ClimbMyBalls/ (on an iPhone: Share → Add to Home Screen).
- **Android**: the APK from [Releases](../../releases).

## Build it

Flutter app in `apps/climb`, with its packages in `packages/`. The shared data lives in a Supabase project (`apps/climb/supabase/*.sql`, run in order); keys go in a JSON file outside the repository and are passed with `--dart-define-from-file` (see `apps/climb/README.md`).

```
cd apps/climb
flutter run --dart-define-from-file=<your keys file>
flutter build web --base-href /ClimbMyBalls/ --dart-define-from-file=<your keys file>
```
