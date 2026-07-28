import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../firebase_options.dart';
import 'environment_service.dart';
import 'user_cache_service.dart';

class BackendApiService {
  BackendApiService({
    http.Client? client,
    UserCacheService? userCacheService,
    FirebaseAuth? firebaseAuth,
    int maxAttempts = 3,
    Duration requestTimeout = const Duration(seconds: 30),
    Duration initialBackoff = const Duration(milliseconds: 500),
  })  : _client = client ?? http.Client(),
        _userCacheService = userCacheService,
        _firebaseAuth = firebaseAuth,
        _maxAttempts = maxAttempts,
        _requestTimeout = requestTimeout,
        _initialBackoff = initialBackoff;

  final http.Client _client;

  // Resolved lazily so the service can be constructed in unit tests (and in
  // any non-auth flow) without a live Firebase app / browser storage.
  UserCacheService? _userCacheService;
  FirebaseAuth? _firebaseAuth;
  UserCacheService get _cache => _userCacheService ??= UserCacheService();
  FirebaseAuth get _auth => _firebaseAuth ??= FirebaseAuth.instance;

  final int _maxAttempts;
  final Duration _requestTimeout;
  final Duration _initialBackoff;

  /// Friendly message shown when the request never got a response from the
  /// backend (dropped connection, DNS/TLS failure, client-side timeout).
  static const String networkErrorMessage =
      'בעיית תקשורת עם השרת. בדוק את החיבור לאינטרנט ונסה שוב.';

  String get _environment =>
      EnvironmentService.instance.isTestMode ? 'test' : 'production';

  /// Whether [error] represents a request that failed *without* a server
  /// response (network drop, timeout) and is therefore safe to retry.
  static bool isTransientError(Object error) =>
      error is http.ClientException || error is TimeoutException;

  /// Runs [action], retrying transient failures with exponential backoff.
  ///
  /// Non-transient errors (and the final transient failure once [maxAttempts]
  /// is reached) are rethrown. [sleep] is injectable so tests don't wait.
  @visibleForTesting
  static Future<T> retryTransient<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
    Duration initialBackoff = const Duration(milliseconds: 500),
    Future<void> Function(Duration)? sleep,
  }) async {
    final sleeper = sleep ?? (Duration d) => Future<void>.delayed(d);
    var backoff = initialBackoff;
    for (var attempt = 1;; attempt++) {
      try {
        return await action();
      } catch (error) {
        if (attempt >= maxAttempts || !isTransientError(error)) {
          rethrow;
        }
        await sleeper(backoff);
        backoff *= 2;
      }
    }
  }

  Uri _buildUri(String path) {
    final projectId = DefaultFirebaseOptions.currentPlatform.projectId;
    return Uri.https(
      'us-central1-$projectId.cloudfunctions.net',
      'api',
      {
        'route': path,
      },
    );
  }

  Future<Map<String, dynamic>> post(
    String path, {
    Map<String, dynamic>? body,
    bool requireAuth = false,
  }) async {
    final requestBody = <String, dynamic>{
      'environment': _environment,
      ...?body,
    };

    final uri = _buildUri(path);
    final encodedBody = jsonEncode(requestBody);

    Future<http.Response> send(String? token) async {
      final headers = <String, String>{
        'Content-Type': 'application/json',
        if (token != null) 'Authorization': 'Bearer $token',
      };
      try {
        return await retryTransient(
          () => _client
              .post(uri, headers: headers, body: encodedBody)
              .timeout(_requestTimeout),
          maxAttempts: _maxAttempts,
          initialBackoff: _initialBackoff,
        );
      } catch (error) {
        // A dropped connection / timeout never reached (or never heard back
        // from) the backend. Surface it as a distinct, retryable network error
        // so callers can show a friendly message instead of a hard failure.
        if (isTransientError(error)) {
          throw BackendApiException(
            networkErrorMessage,
            isNetworkError: true,
            cause: error,
          );
        }
        rethrow;
      }
    }

    String? token;
    if (requireAuth) {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        throw BackendApiException('אין סשן פעיל. יש להתחבר מחדש.');
      }
      token = await currentUser.getIdToken();
    }

    var response = await send(token);

    // A 401 far more often means the cached ID token went stale — a suspended
    // mobile tab, a sleeping laptop — than a session that is genuinely gone.
    // Mint a fresh token and retry ONCE before concluding otherwise, because
    // the sign-out below drops the Firebase credential and therefore kills
    // EVERY live Firestore listener in the app at the same instant.
    if (response.statusCode == 401 && requireAuth) {
      final refreshed = await _refreshIdToken();
      if (refreshed != null && refreshed != token) {
        response = await send(refreshed);
      }
    }

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final errorMessage = decoded['error']?.toString() ?? 'Backend request failed';
    if (response.statusCode == 401 && requireAuth) {
      await _auth.signOut();
      await _cache.clearSelection();
    }
    throw BackendApiException(errorMessage, statusCode: response.statusCode);
  }

  /// Force-mints a new ID token for the current user.
  ///
  /// Returns `null` when there is nothing to refresh (no signed-in user) or
  /// when the refresh was rejected — a revoked/disabled account — which leaves
  /// the caller's 401 standing so the session is torn down.
  ///
  /// A refresh that fails for *connectivity* reasons is a different story: it
  /// says nothing about whether the session is still valid, so it throws a
  /// network error rather than letting the caller sign the user out.
  Future<String?> _refreshIdToken() async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return null;
    try {
      return await currentUser.getIdToken(true);
    } on FirebaseAuthException catch (error) {
      if (error.code == 'network-request-failed') {
        throw BackendApiException(
          networkErrorMessage,
          isNetworkError: true,
          cause: error,
        );
      }
      return null;
    } catch (error) {
      if (isTransientError(error)) {
        throw BackendApiException(
          networkErrorMessage,
          isNetworkError: true,
          cause: error,
        );
      }
      return null;
    }
  }

  Future<List<Map<String, dynamic>>> listSelectableMembers() async {
    final response = await post('auth/list-members');
    final members = response['members'] as List<dynamic>? ?? const [];
    return members.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> getCalendarConfig() async {
    return await post('calendar/config');
  }

  Future<Map<String, dynamic>> getCalendarStatus() async {
    return await post(
      'calendar/status',
      requireAuth: true,
    );
  }

  Future<Map<String, dynamic>> startCalendarOAuth({
    required String redirectUri,
  }) async {
    return await post(
      'calendar/oauth/start',
      requireAuth: true,
      body: {
        'redirectUri': redirectUri,
      },
    );
  }

  Future<Map<String, dynamic>> exchangeCalendarOAuthCode({
    required String code,
    required String redirectUri,
  }) async {
    return await post(
      'calendar/oauth/exchange',
      requireAuth: true,
      body: {
        'code': code,
        'redirectUri': redirectUri,
      },
    );
  }

  Future<void> disconnectCalendarOAuth() async {
    await post(
      'calendar/oauth/sign-out',
      requireAuth: true,
    );
  }

  Future<Map<String, dynamic>> calendarAction(
    String action, {
    Map<String, dynamic>? payload,
  }) async {
    return await post(
      'calendar/action',
      requireAuth: true,
      body: {
        'action': action,
        'payload': payload ?? const <String, dynamic>{},
      },
    );
  }

  Future<Map<String, dynamic>> signInWithPasscode({
    required String uniqueKey,
    required String passcode,
  }) async {
    return await post(
      'auth/sign-in',
      body: {
        'uniqueKey': uniqueKey,
        'passcode': passcode,
      },
    );
  }

  Future<Map<String, dynamic>> validateSession() async {
    return await post(
      'auth/validate-session',
      requireAuth: true,
    );
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }

  Future<Map<String, dynamic>> mutate(
    String operation, {
    Map<String, dynamic>? payload,
  }) async {
    return await post(
      'mutate',
      requireAuth: true,
      body: {
        'operation': operation,
        'payload': payload ?? const <String, dynamic>{},
      },
    );
  }
}

class BackendApiException implements Exception {
  const BackendApiException(
    this.message, {
    this.statusCode,
    this.isNetworkError = false,
    this.cause,
  });

  final String message;
  final int? statusCode;

  /// True when the request failed at the network layer (no server response):
  /// dropped connection, DNS/TLS failure, or client-side timeout. Callers can
  /// treat these as transient/retryable rather than a genuine backend error.
  final bool isNetworkError;

  /// The underlying error (e.g. the original `ClientException`), kept for logs.
  final Object? cause;

  @override
  String toString() => message;
}
