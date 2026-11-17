import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/push_notification_service.dart';
import 'package:shavtzak/core/web/web_push.dart';

const _sub = '{"endpoint":"https://push.example/1","keys":{"p256dh":"p","auth":"a"}}';

class FakeBridge implements WebPushBridge {
  FakeBridge({this.perm = 'default', this.ios = false, this.existing});

  String perm;
  bool ios;
  String? existing;
  String? grantOnSubscribe = 'granted';
  int subscribeCalls = 0;

  /// The browser refuses at once, without its window (Chrome, 17/11/2026).
  bool refuseWithoutWindow = false;

  @override
  bool askedWithoutWindow() => refuseWithoutWindow && perm != 'granted';

  @override
  String permission() => perm;

  @override
  bool iosNotInstalled() => ios;

  @override
  Future<String?> subscribe(String vapidPublicKey) async {
    subscribeCalls++;
    expect(vapidPublicKey, PushNotificationService.vapidPublicKey);
    perm = grantOnSubscribe!;
    if (perm != 'granted') return null;
    return existing ??= _sub;
  }

  @override
  Future<String?> current() async => existing;

  @override
  Future<String?> unsubscribe() async {
    final had = existing;
    existing = null;
    return had == null ? null : jsonDecode(had)['endpoint'] as String;
  }
}

class FakeBackend implements PushBackend {
  final List<Map<String, dynamic>> subscribed = [];
  final List<String> unsubscribed = [];
  bool fail = false;

  @override
  Future<void> subscribe(Map<String, dynamic> subscription) async {
    if (fail) throw Exception('offline');
    subscribed.add(subscription);
  }

  @override
  Future<void> unsubscribe(String endpoint) async {
    if (fail) throw Exception('offline');
    unsubscribed.add(endpoint);
  }
}

class FakeFlags implements PushDeviceFlags {
  bool off = false;
  String? snoozed;

  @override
  Future<bool> turnedOff() async => off;

  @override
  Future<void> setTurnedOff(bool value) async => off = value;

  @override
  Future<String?> snoozedVersion() async => snoozed;

  @override
  Future<void> setSnoozedVersion(String? version) async => snoozed = version;
}

void main() {
  late FakeBridge bridge;
  late FakeBackend backend;
  late FakeFlags flags;
  PushNotificationService service() => PushNotificationService(bridge, backend, flags);

  setUp(() {
    bridge = FakeBridge();
    backend = FakeBackend();
    flags = FakeFlags();
  });

  group('status', () {
    test('never asked on this device', () async {
      expect(await service().status(), PushStatus.notAsked);
    });

    test('iPhone in the browser needs the home-screen app', () async {
      bridge = FakeBridge(perm: 'unsupported', ios: true);
      expect(await service().status(), PushStatus.iosInstallNeeded);
    });

    test('a browser without push', () async {
      bridge = FakeBridge(perm: 'unsupported');
      expect(await service().status(), PushStatus.unsupported);
    });

    test('blocked in the browser', () async {
      bridge = FakeBridge(perm: 'denied');
      expect(await service().status(), PushStatus.blocked);
    });

    test('granted with a subscription = enabled; turned off by hand = off', () async {
      bridge = FakeBridge(perm: 'granted', existing: _sub);
      expect(await service().status(), PushStatus.enabled);
      flags.off = true;
      expect(await service().status(), PushStatus.off);
    });
  });

  group('shouldPrompt', () {
    test('not asked and not snoozed for this version', () async {
      expect(await service().shouldPrompt(PushStatus.notAsked, '1.2'), isTrue);
    });

    test('"לא עכשיו" holds until the version changes', () async {
      final s = service();
      await s.snooze('1.2');
      expect(await s.shouldPrompt(PushStatus.notAsked, '1.2'), isFalse);
      expect(await s.shouldPrompt(PushStatus.notAsked, '1.3'), isTrue);
    });

    test('the iPhone explainer follows the same rule', () async {
      final s = service();
      expect(await s.shouldPrompt(PushStatus.iosInstallNeeded, '1.2'), isTrue);
      await s.snooze('1.2');
      expect(await s.shouldPrompt(PushStatus.iosInstallNeeded, '1.2'), isFalse);
    });

    test('never when blocked, enabled, off or unsupported', () async {
      final s = service();
      for (final status in [PushStatus.blocked, PushStatus.enabled, PushStatus.off, PushStatus.unsupported]) {
        expect(await s.shouldPrompt(status, '1.2'), isFalse, reason: '$status');
      }
    });
  });

  test('enable subscribes, tells the server and clears "turned off"', () async {
    flags.off = true;
    expect(await service().enable(), PushStatus.enabled);
    expect(backend.subscribed.single['endpoint'], 'https://push.example/1');
    expect(flags.off, isFalse);
  });

  test('enable refused in the phone\'s window = blocked, nothing sent', () async {
    bridge.grantOnSubscribe = 'denied';
    expect(await service().enable(), PushStatus.blocked);
    expect(backend.subscribed, isEmpty);
  });

  test('enable refused by the browser without its window = noWindow', () async {
    bridge.grantOnSubscribe = 'default';
    bridge.refuseWithoutWindow = true;
    expect(await service().enable(), PushStatus.noWindow);
    expect(backend.subscribed, isEmpty);
  });

  test('a window closed by the person stays notAsked', () async {
    bridge.grantOnSubscribe = 'default';
    expect(await service().enable(), PushStatus.notAsked);
  });

  test('disable unsubscribes, deletes on the server and remembers it', () async {
    bridge = FakeBridge(perm: 'granted', existing: _sub);
    expect(await service().disable(), PushStatus.off);
    expect(backend.unsubscribed, ['https://push.example/1']);
    expect(bridge.existing, isNull);
    expect(flags.off, isTrue);
  });

  group('syncSilently', () {
    test('granted, not turned off: re-subscribes and tells the server', () async {
      bridge = FakeBridge(perm: 'granted');
      await service().syncSilently(canReceive: true);
      expect(bridge.subscribeCalls, 1);
      expect(backend.subscribed, hasLength(1));
    });

    test('an existing subscription is sent again (it may be another member\'s device now)', () async {
      bridge = FakeBridge(perm: 'granted', existing: _sub);
      await service().syncSilently(canReceive: true);
      expect(bridge.subscribeCalls, 0);
      expect(backend.subscribed, hasLength(1));
    });

    test('turned off by hand: nothing', () async {
      bridge = FakeBridge(perm: 'granted');
      flags.off = true;
      await service().syncSilently(canReceive: true);
      expect(bridge.subscribeCalls, 0);
      expect(backend.subscribed, isEmpty);
    });

    test('permission not granted: never asks', () async {
      await service().syncSilently(canReceive: true);
      expect(bridge.subscribeCalls, 0);
    });

    test('a member who may not get notifications: nothing', () async {
      bridge = FakeBridge(perm: 'granted', existing: _sub);
      await service().syncSilently(canReceive: false);
      expect(backend.subscribed, isEmpty);
    });

    test('a server failure is swallowed', () async {
      bridge = FakeBridge(perm: 'granted', existing: _sub);
      backend.fail = true;
      await service().syncSilently(canReceive: true);
    });
  });

  test('forgetDevice deletes the server copy, keeps the browser subscription', () async {
    bridge = FakeBridge(perm: 'granted', existing: _sub);
    await service().forgetDevice();
    expect(backend.unsubscribed, ['https://push.example/1']);
    expect(bridge.existing, isNotNull);
  });

  test('forgetDevice with no subscription or a failing server does not throw', () async {
    await service().forgetDevice();
    bridge = FakeBridge(perm: 'granted', existing: _sub);
    backend.fail = true;
    await service().forgetDevice();
  });
}
