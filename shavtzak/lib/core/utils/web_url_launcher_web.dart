import 'dart:async';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Web-specific implementation that attempts to close the opened tab
/// after a delay to improve mobile UX.
Future<bool> launchUrlWeb(String url) async {
  try {
    // Open the URL in a new tab/window
    final openedWindow = html.window.open(url, '_blank');

    if (openedWindow != null) {
      // Attempt to close the window after a delay
      // This works when the browser has redirected to an external app
      // and the tab is left empty/blank
      Timer(const Duration(milliseconds: 500), () {
        try {
          if (!openedWindow.closed!) {
            openedWindow.close();
          }
        } catch (e) {
          // Browser may block this - that's expected
        }
      });

      // Retry in case redirect takes a bit longer
      Timer(const Duration(milliseconds: 1000), () {
        try {
          if (!openedWindow.closed!) {
            openedWindow.close();
          }
        } catch (e) {
          // Ignore - best effort
        }
      });

      return true;
    }

    return false;
  } catch (e) {
    return false;
  }
}
