{{flutter_js}}
{{flutter_build_config}}

// Our own service worker keeps the app for days without signal (#464);
// Flutter's own is deprecated, so the loader registers none.
if ('serviceWorker' in navigator) {
  navigator.serviceWorker.register('climb_sw.js').catch((e) => console.warn('No offline app:', e));
}

_flutter.loader.load({
  // canvaskit from this site, not Google's CDN, so it is kept for offline too
  config: { canvasKitBaseUrl: 'canvaskit/' },
});
