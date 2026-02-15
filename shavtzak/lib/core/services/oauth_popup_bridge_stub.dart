import 'dart:developer' as developer;

String getOAuthCurrentOrigin() {
  throw UnsupportedError('OAuth popup flow is only available in dart:html builds.');
}

Future<String?> openOAuthPopupAndWaitForCode(String authUrl) async {
  developer.log(
    'OAuth popup flow unavailable on this web runtime (dart:html not supported).',
    name: 'GoogleOAuth',
  );
  return null;
}
