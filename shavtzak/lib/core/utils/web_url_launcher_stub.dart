/// Stub implementation for non-web platforms.
/// This file is used when dart:html is not available.
Future<bool> launchUrlWeb(String url) async {
  // This should never be called on non-web platforms
  // as the main function checks kIsWeb first
  return false;
}
