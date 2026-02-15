import 'oauth_popup_bridge_stub.dart'
    if (dart.library.html) 'oauth_popup_bridge_html.dart' as impl;

String getOAuthCurrentOrigin() => impl.getOAuthCurrentOrigin();

Future<String?> openOAuthPopupAndWaitForCode(String authUrl) =>
    impl.openOAuthPopupAndWaitForCode(authUrl);
