import 'oauth_popup_bridge_stub.dart'
    if (dart.library.html) 'oauth_popup_bridge_html.dart' as impl;

String getOAuthCurrentOrigin() => impl.getOAuthCurrentOrigin();

Object? prepareOAuthPopup() => impl.prepareOAuthPopup();

Future<String?> openOAuthPopupAndWaitForCode(
  String authUrl, {
  Object? popupHandle,
}) =>
    impl.openOAuthPopupAndWaitForCode(
      authUrl,
      popupHandle: popupHandle,
    );
