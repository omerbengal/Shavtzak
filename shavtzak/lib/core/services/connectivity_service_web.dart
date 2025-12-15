import 'dart:async';
import 'dart:html' as html;

/// Web implementation using browser's navigator.onLine API

/// Get current online status from browser
bool getOnlineStatus() {
  return html.window.navigator.onLine ?? true;
}

/// Stream of connectivity changes using browser events
Stream<bool> onConnectivityChanged() {
  final controller = StreamController<bool>.broadcast();

  // Listen to online event
  html.window.onOnline.listen((_) {
    controller.add(true);
  });

  // Listen to offline event
  html.window.onOffline.listen((_) {
    controller.add(false);
  });

  return controller.stream;
}
