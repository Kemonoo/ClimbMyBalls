// ClimbMyBalls offline (#464): keeps the app's own files so it opens
// without signal. Network first, so a new release shows as soon as there
// is signal; the kept copy when there is none (or it takes too long).
// Photos, map tiles and changes are kept by the app itself (IndexedDB,
// localStorage), not here.
const CACHE = 'climb-app-v1';
const FONTS = ['fonts.gstatic.com', 'fonts.googleapis.com'];

// The app itself, kept at the first visit so the next one works without
// signal; the rest (fonts, guides, icons) is kept as the app fetches it.
const SHELL = [
  './',
  'index.html',
  'flutter_bootstrap.js',
  'flutter.js',
  'main.dart.js',
  'manifest.json',
  'favicon.png',
  'canvaskit/canvaskit.js',
  'canvaskit/canvaskit.wasm',
  'canvaskit/chromium/canvaskit.js',
  'canvaskit/chromium/canvaskit.wasm',
  'assets/AssetManifest.bin.json',
  'assets/FontManifest.json',
  'assets/fonts/MaterialIcons-Regular.otf',
];

self.addEventListener('install', (event) => {
  self.skipWaiting();
  event.waitUntil(caches.open(CACHE).then((c) => Promise.allSettled(SHELL.map((u) => c.add(u)))));
});
self.addEventListener('activate', (event) => event.waitUntil(self.clients.claim()));

self.addEventListener('fetch', (event) => {
  const req = event.request;
  if (req.method !== 'GET') return;
  const url = new URL(req.url);
  if (FONTS.includes(url.hostname)) {
    // fonts never change: the kept copy first
    event.respondWith(caches.open(CACHE).then(async (c) => (await c.match(req)) || fetchAndKeep(c, req)));
    return;
  }
  if (url.origin !== self.location.origin) return; // the server, tiles: not ours
  event.respondWith(networkFirst(req));
});

async function fetchAndKeep(cache, req) {
  const res = await fetch(req);
  if (res.ok || res.type === 'opaque') await cache.put(req, res.clone());
  return res;
}

async function networkFirst(req) {
  const cache = await caches.open(CACHE);
  const kept = await cache.match(req, { ignoreSearch: true });
  const net = fetchAndKeep(cache, req);
  if (!kept) return net;
  // weak signal: don't wait more than 4 s when there is a copy
  const timeout = new Promise((resolve) => setTimeout(() => resolve(kept), 4000));
  try {
    return await Promise.race([net, timeout]);
  } catch (_) {
    return kept;
  }
}
