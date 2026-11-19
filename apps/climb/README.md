# Climb

The standalone climbing app (docs/architecture/climbing-extraction.md, step 5; docs/climb/plan.md). The same climbing screens as hibi's module (`packages/hibi_climbing_ui`) plus the map (`packages/hibi_climbing_map`). Climbs are saved on the device as hibi protocol events (`climb_events.json`, docs/protocol/v0.1.md).

- **Climbs** tab: sessions, logging, stats. "Export for hibi" (top right) writes the climbs as events; hibi imports them.
- **Friends** tab: sign in or make an account (email and password) to share places with friends. The feed comes later.
- **Map** tab: Mapy.com outdoor map, your position, the "near me" list, outdoor / indoor / grade filters, search, and the place hierarchy. Built only when you open it. Places come from the OpenStreetMap import (`assets/places/sk.json`, ODbL).

## Shared database

Supabase, in a project of its own (ADR 0021). The tables and their rules are in `supabase/schema.sql`: paste it into Supabase → SQL Editor → Run. It is safe to run again after changes. In Auth settings, "Confirm email" is off, because the free email sender allows only a few emails an hour.

## Keys

The map needs a Mapy.com API key. It is a public client key, but it stays out of git: keep it in `~/.hibi/climb-keys.json` and pass the file at build time.

```json
{
  "MAPY_API_KEY": "...",
  "SUPABASE_URL": "https://<project>.supabase.co",
  "SUPABASE_PUBLISHABLE_KEY": "sb_publishable_...",
  "GOOGLE_WEB_CLIENT_ID": "...apps.googleusercontent.com"
}
```

Only public keys go in that file. Never the Supabase service key or the Google client secret.

Sign-in: email and password, or "Continue with Google" on Android (Google Cloud project in Testing mode: only listed test users can sign in). New accounts wait for an admin to let them in (`supabase/002_approval.sql`).

Admins change and delete anything; others only what they added (`supabase/003_admin_sections.sql`, run after 002).

## Sections and guides

A boulder's photos are its sections ("lúčka 01"): routes are drawn on them and a route can be on several. A section can keep a second photo, such as a printed guide's page. `assets/guides/devin/` can hold a guide (photos plus `guide.json`) that an admin adds to a boulder; this repository ships it empty, since guide photos belong to their authors.

With a guide in that folder, `flutter run -d windows --dart-define=CLIMB_PREVIEW=devin` opens its sections without the server, to check the screens.

Release builds are signed with Climb's own key from `~/.hibi/climb-keystore.properties` (its SHA-1 is registered in Google Cloud for sign-in).

Mapy.com's terms forbid storing or pre-downloading tiles, so there are no offline maps: tiles are kept only for the server's own cache time (one day). The Mapy.com logo and copyright must stay on the map.

```bash
cd apps/climb
flutter test
flutter run --dart-define-from-file=$HOME/.hibi/climb-keys.json
```

Without the file the map still works, just with no background map.

## Web

The same app runs in a browser (iPhones, any phone, PCs): `flutter build web --base-href /ClimbMyBalls/ --dart-define-from-file=<keys>`. Its storage is the browser's (`lib/storage/`); Google sign-in there goes through Google's page and back (Supabase → Authentication → URL Configuration must list the site's address).

