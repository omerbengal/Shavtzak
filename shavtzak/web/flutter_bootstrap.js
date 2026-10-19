{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: Flutter's own worker is deprecated and only
// self-destructs now. index.html registers sw.js, which caches the app.
_flutter.loader.load();
