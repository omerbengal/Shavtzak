import 'dart:js_interop';

import 'web_push.dart';

/// `window.shavtzakPush` (web/push.js).
extension type _ShavtzakPush._(JSObject _) implements JSObject {
  external JSString permission();
  external JSBoolean iosNotInstalled();
  external JSPromise<JSString?> subscribe(JSString publicKey);
  external JSPromise<JSString?> current();
  external JSPromise<JSString?> unsubscribe();
}

@JS('shavtzakPush')
external _ShavtzakPush? get _push;

class _BrowserWebPush implements WebPushBridge {
  @override
  String permission() {
    try {
      return _push?.permission().toDart ?? 'unsupported';
    } catch (_) {
      return 'unsupported';
    }
  }

  @override
  bool iosNotInstalled() {
    try {
      return _push?.iosNotInstalled().toDart ?? false;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<String?> subscribe(String vapidPublicKey) async {
    final push = _push;
    if (push == null) return null;
    return (await push.subscribe(vapidPublicKey.toJS).toDart)?.toDart;
  }

  @override
  Future<String?> current() async {
    final push = _push;
    if (push == null) return null;
    return (await push.current().toDart)?.toDart;
  }

  @override
  Future<String?> unsubscribe() async {
    final push = _push;
    if (push == null) return null;
    return (await push.unsubscribe().toDart)?.toDart;
  }
}

WebPushBridge createWebPushBridge() => _BrowserWebPush();
