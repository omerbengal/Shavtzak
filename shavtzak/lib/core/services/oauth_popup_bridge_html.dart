import 'dart:async';
import 'dart:html' as html;
import 'dart:developer' as developer;

String getOAuthCurrentOrigin() {
  // Use document.baseUri so subdirectory deployments (e.g. GitHub Pages /Shavtzak/)
  // are included in the redirect URI, matching what is registered in Google Cloud Console.
  final baseUri = Uri.parse(html.document.baseUri ?? html.window.location.href);
  final origin = '${baseUri.scheme}://${baseUri.host}${baseUri.hasPort ? ':${baseUri.port}' : ''}';
  var basePath = baseUri.path;
  if (basePath.endsWith('/')) {
    basePath = basePath.substring(0, basePath.length - 1);
  }
  return '$origin$basePath';
}

Future<String?> openOAuthPopupAndWaitForCode(String authUrl) async {
  final width = 600;
  final height = 700;
  final left = (html.window.screen!.width! - width) ~/ 2;
  final top = (html.window.screen!.height! - height) ~/ 2;

  final popup = html.window.open(
    authUrl,
    'Google OAuth',
    'width=$width,height=$height,left=$left,top=$top,toolbar=no,location=no,status=no,menubar=no,scrollbars=yes,resizable=yes',
  );

  if (popup == null) {
    developer.log(
      'GoogleOAuthService: Failed to open popup - blocked by browser',
      name: 'GoogleOAuth',
    );
    return null;
  }

  final completer = Completer<String?>();
  StreamSubscription<html.MessageEvent>? messageSubscription;

  messageSubscription =
      html.window.onMessage.listen((html.MessageEvent event) {
    final data = event.data;
    if (data is Map) {
      if (data['type'] == 'oauth_callback') {
        final code = data['code'] as String?;
        if (code != null && !completer.isCompleted) {
          developer.log(
            'GoogleOAuthService: Received auth code from popup',
            name: 'GoogleOAuth',
          );
          completer.complete(code);
        }
      } else if (data['type'] == 'oauth_error') {
        if (!completer.isCompleted) {
          developer.log(
            'GoogleOAuthService: OAuth error - ${data['error']}',
            name: 'GoogleOAuth',
          );
          completer.complete(null);
        }
      }
    }
  });

  final authCode = await completer.future.timeout(
    const Duration(minutes: 5),
    onTimeout: () {
      developer.log(
        'GoogleOAuthService: OAuth flow timed out',
        name: 'GoogleOAuth',
      );
      return null;
    },
  );

  await messageSubscription.cancel();
  return authCode;
}
