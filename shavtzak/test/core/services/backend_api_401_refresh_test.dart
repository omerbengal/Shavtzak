import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:shavtzak/core/services/backend_api_service.dart';
import 'package:shavtzak/core/services/user_cache_service.dart';

import 'backend_api_401_refresh_test.mocks.dart';

/// Signing out drops the Firebase credential, which kills every live Firestore
/// listener in the app at once — screens then freeze on their last snapshot and
/// any stream that errors (categories, roles) stays broken until a full page
/// reload. So a 401 must not reach that code path until a fresh token has been
/// tried.
@GenerateMocks([FirebaseAuth, User, UserCacheService])
void main() {
  late MockFirebaseAuth auth;
  late MockUser user;
  late MockUserCacheService cache;

  setUp(() {
    // Force a defined platform so DefaultFirebaseOptions.currentPlatform
    // resolves on any test host.
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    auth = MockFirebaseAuth();
    user = MockUser();
    cache = MockUserCacheService();
    when(auth.currentUser).thenReturn(user);
    when(auth.signOut()).thenAnswer((_) async {});
    when(cache.clearSelection()).thenAnswer((_) async {});
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  BackendApiService serviceWith(http.Client client) => BackendApiService(
        client: client,
        firebaseAuth: auth,
        userCacheService: cache,
        maxAttempts: 1,
        initialBackoff: Duration.zero,
      );

  String? bearerOf(http.BaseRequest request) =>
      request.headers['Authorization'];

  test('a 401 from a stale token is retried with a fresh one, not signed out',
      () async {
    when(user.getIdToken()).thenAnswer((_) async => 'stale-token');
    when(user.getIdToken(true)).thenAnswer((_) async => 'fresh-token');

    final sentTokens = <String?>[];
    final client = MockClient((request) async {
      sentTokens.add(bearerOf(request));
      return bearerOf(request) == 'Bearer fresh-token'
          ? http.Response('{"ok": true}', 200)
          : http.Response('{"error": "Invalid session token"}', 401);
    });

    final result = await serviceWith(client)
        .post('calendar/action', requireAuth: true);

    expect(result['ok'], true);
    expect(sentTokens, ['Bearer stale-token', 'Bearer fresh-token']);
    verifyNever(auth.signOut());
    verifyNever(cache.clearSelection());
  });

  test('a 401 that survives the refresh does sign the session out', () async {
    when(user.getIdToken()).thenAnswer((_) async => 'stale-token');
    when(user.getIdToken(true)).thenAnswer((_) async => 'fresh-token');

    var calls = 0;
    final client = MockClient((request) async {
      calls++;
      return http.Response('{"error": "User no longer exists"}', 401);
    });

    await expectLater(
      serviceWith(client).post('calendar/action', requireAuth: true),
      throwsA(
        isA<BackendApiException>()
            .having((e) => e.statusCode, 'statusCode', 401),
      ),
    );

    expect(calls, 2, reason: 'original request plus one refreshed retry');
    verify(auth.signOut()).called(1);
    verify(cache.clearSelection()).called(1);
  });

  test('a refresh that fails on the network never signs the user out',
      () async {
    when(user.getIdToken()).thenAnswer((_) async => 'stale-token');
    when(user.getIdToken(true)).thenThrow(
      FirebaseAuthException(code: 'network-request-failed'),
    );

    final client = MockClient(
      (request) async => http.Response('{"error": "Invalid session token"}', 401),
    );

    await expectLater(
      serviceWith(client).post('calendar/action', requireAuth: true),
      throwsA(
        isA<BackendApiException>()
            .having((e) => e.isNetworkError, 'isNetworkError', true),
      ),
    );

    verifyNever(auth.signOut());
    verifyNever(cache.clearSelection());
  });

  test('an unauthenticated call is unaffected by the refresh path', () async {
    final client = MockClient((request) async {
      expect(bearerOf(request), isNull);
      return http.Response('{"ok": true}', 200);
    });

    final result = await serviceWith(client).post('auth/list-members');

    expect(result['ok'], true);
    verifyNever(user.getIdToken(true));
  });
}
