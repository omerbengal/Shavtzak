/// Stub implementation for geolocation on mobile/desktop platforms
class GeolocationService {
  static Future<Map<String, dynamic>> getCurrentPosition() async {
    throw UnsupportedError('Geolocation is only available on web platform');
  }
}
