import 'dart:async';
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
      Timer(const Duration(milliseconds: 1500), () {
        try {
          // Check if the window is still open and try to close it
          // This will only succeed if:
          // 1. The window was opened by our script (same-origin policy)
          // 2. The window has navigated away (to an app) leaving it closeable
          if (!openedWindow.closed!) {
            openedWindow.close();
          }
        } catch (e) {
          // Browser may block this - that's expected
          // The window.close() is blocked if the page is still active
        }
      });

      // Also try after a longer delay in case redirect takes time
      Timer(const Duration(milliseconds: 3000), () {
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
