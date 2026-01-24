import 'dart:async';
import 'package:web/web.dart' as web;
import 'dart:js_interop';

/// Web-specific geolocation implementation
class GeolocationService {
  static Future<Map<String, dynamic>> getCurrentPosition() async {
    final geolocation = web.window.navigator.geolocation;
    final completer = Completer<web.GeolocationPosition>();

    geolocation.getCurrentPosition(
      ((web.GeolocationPosition position) {
        completer.complete(position);
      }).toJS,
      ((web.GeolocationPositionError error) {
        completer.completeError(error.message);
      }).toJS,
    );

    final position = await completer.future;
    final coords = position.coords;

    return {
      'latitude': coords.latitude,
      'longitude': coords.longitude,
    };
  }
}

