import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/push_notification_service.dart';
import 'package:shavtzak/presentation/widgets/push_prompt_dialog.dart';
import 'package:shavtzak/presentation/widgets/push_settings_section.dart';

import '../../core/services/push_notification_service_test.dart'
    show FakeBackend, FakeBridge, FakeFlags;

void main() {
  late FakeBridge bridge;
  late FakeBackend backend;
  late FakeFlags flags;
  late PushNotificationService service;

  setUp(() {
    resetPushPromptSession();
    bridge = FakeBridge();
    backend = FakeBackend();
    flags = FakeFlags();
    service = PushNotificationService(bridge, backend, flags);
  });

  Future<void> open(WidgetTester tester, {bool canReceive = true}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (context) => TextButton(
            onPressed: () => maybeShowPushPrompt(
              context,
              canReceive: canReceive,
              appVersion: '1.2',
              service: service,
            ),
            child: const Text('go'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('go'));
    await tester.pumpAndSettle();
  }

  testWidgets('a device never asked gets the popup; "הפעל התראות" subscribes', (tester) async {
    await open(tester);
    expect(find.text('התראות על משימות'), findsOneWidget);
    expect(find.text('נעדכן אותך כשמשבצים אותך למשימה, גם כשהאפליקציה סגורה.'), findsOneWidget);
    await tester.tap(find.byKey(const Key('push-prompt-enable')));
    await tester.pumpAndSettle();
    expect(backend.subscribed, hasLength(1));
    expect(find.text('🔔 ההתראות הופעלו במכשיר הזה'), findsOneWidget);
  });

  testWidgets('"לא עכשיו" snoozes this version', (tester) async {
    await open(tester);
    await tester.tap(find.byKey(const Key('push-prompt-later')));
    await tester.pumpAndSettle();
    expect(flags.snoozed, '1.2');
    expect(backend.subscribed, isEmpty);
    resetPushPromptSession();
    await open(tester);
    expect(find.text('התראות על משימות'), findsNothing);
  });

  testWidgets('iPhone in the browser: the home-screen explainer instead', (tester) async {
    bridge = FakeBridge(perm: 'unsupported', ios: true);
    service = PushNotificationService(bridge, backend, flags);
    await open(tester);
    expect(find.text('התראות באייפון'), findsOneWidget);
    expect(find.byKey(const Key('push-prompt-enable')), findsNothing);
    await tester.tap(find.byKey(const Key('push-prompt-ok')));
    await tester.pumpAndSettle();
    expect(flags.snoozed, '1.2');
  });

  testWidgets('blocked, or a member who gets none: no popup', (tester) async {
    await open(tester, canReceive: false);
    expect(find.byType(PushPromptDialog), findsNothing);
    bridge = FakeBridge(perm: 'denied');
    service = PushNotificationService(bridge, backend, flags);
    await open(tester);
    expect(find.byType(PushPromptDialog), findsNothing);
  });

  testWidgets('settings: on = a switch that turns it off and remembers it', (tester) async {
    bridge = FakeBridge(perm: 'granted', existing: '{"endpoint":"https://push.example/1","keys":{"p256dh":"p","auth":"a"}}');
    service = PushNotificationService(bridge, backend, flags);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PushSettingsSection(service: service))));
    await tester.pumpAndSettle();
    expect(find.text('פעיל במכשיר הזה'), findsOneWidget);
    await tester.tap(find.byKey(const Key('push-settings-switch')));
    await tester.pumpAndSettle();
    expect(flags.off, isTrue);
    expect(find.byKey(const Key('push-settings-enable')), findsOneWidget);
  });

  testWidgets('settings: blocked shows how to undo it', (tester) async {
    bridge = FakeBridge(perm: 'denied');
    service = PushNotificationService(bridge, backend, flags);
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PushSettingsSection(service: service))));
    await tester.pumpAndSettle();
    expect(find.text('חסום בדפדפן'), findsOneWidget);
    expect(find.text(pushUnblockSteps), findsOneWidget);
  });

  testWidgets('popup: the browser answers without a "yes" = a message, never silence', (tester) async {
    bridge.grantOnSubscribe = 'default';
    await open(tester);
    await tester.tap(find.byKey(const Key('push-prompt-enable')));
    await tester.pumpAndSettle();
    expect(backend.subscribed, isEmpty);
    expect(find.text(pushNotEnabledText), findsOneWidget);
  });

  testWidgets('popup: a failure on the way says so', (tester) async {
    backend.fail = true;
    await open(tester);
    await tester.tap(find.byKey(const Key('push-prompt-enable')));
    await tester.pumpAndSettle();
    expect(find.text('לא הצלחנו להפעיל התראות. אפשר לנסות שוב בהגדרות'), findsOneWidget);
  });

  testWidgets('settings: "הפעל התראות" with no "yes" from the browser = a message', (tester) async {
    bridge.grantOnSubscribe = 'default';
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PushSettingsSection(service: service))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('push-settings-enable')));
    await tester.pumpAndSettle();
    expect(find.text(pushNotEnabledText), findsOneWidget);
    expect(find.byKey(const Key('push-settings-enable')), findsOneWidget);
  });

  testWidgets('popup: Chrome refuses without its window = the way to allow it', (tester) async {
    bridge.grantOnSubscribe = 'default';
    bridge.refuseWithoutWindow = true;
    await open(tester);
    await tester.tap(find.byKey(const Key('push-prompt-enable')));
    await tester.pump();
    expect(find.text(pushNoWindowText), findsOneWidget);
  });

  testWidgets('settings: Chrome refuses without its window = the way to allow it, button kept', (tester) async {
    bridge.grantOnSubscribe = 'default';
    bridge.refuseWithoutWindow = true;
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PushSettingsSection(service: service))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('push-settings-enable')));
    await tester.pumpAndSettle();
    expect(find.text(pushChromeAllowSteps), findsOneWidget);
    expect(find.byKey(const Key('push-settings-enable')), findsOneWidget);
  });
}
