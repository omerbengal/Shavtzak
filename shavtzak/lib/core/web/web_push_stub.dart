import 'web_push.dart';

/// Off the web: no notifications.
class _NoWebPush implements WebPushBridge {
  @override
  String permission() => 'unsupported';

  @override
  bool iosNotInstalled() => false;

  @override
  Future<String?> subscribe(String vapidPublicKey) async => null;

  @override
  bool askedWithoutWindow() => false;

  @override
  Future<String?> current() async => null;

  @override
  Future<String?> unsubscribe() async => null;
}

WebPushBridge createWebPushBridge() => _NoWebPush();
