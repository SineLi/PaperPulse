{{flutter_js}}
{{flutter_build_config}}

_flutter.loader.load({
  serviceWorkerSettings: {
    serviceWorkerVersion: flutter_service_worker_version,
  },
  config: {
    // Force local-only web assets; avoid runtime fallback to external CDNs.
    renderer: 'canvaskit',
    useLocalCanvasKit: true,
    canvasKitBaseUrl: 'canvaskit/',
  },
});
