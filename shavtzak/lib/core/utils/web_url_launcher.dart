import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

// Conditional import for web
import 'web_url_launcher_stub.dart'
    if (dart.library.html) 'web_url_launcher_web.dart' as platform;

/// Launches a URL with special handling for mobile web browsers.
///
/// On mobile web, opening links to apps like Google Drive causes an in-app
/// browser to open first, which remains open after redirecting to the app.
/// This utility attempts to close that browser tab after a short delay.
Future<bool> launchUrlWithAutoClose(String url) async {
  if (kIsWeb) {
    return platform.launchUrlWeb(url);
  } else {
    // On native platforms, use standard url_launcher
    final uri = Uri.parse(url);
    if (await canLaunchUrl(uri)) {
      return launchUrl(uri, mode: LaunchMode.externalApplication);
    }
    return false;
  }
}
