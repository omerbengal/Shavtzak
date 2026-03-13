import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import '../../firebase_options.dart';
import 'environment_service.dart';
import 'user_cache_service.dart';

class BackendApiService {
  BackendApiService({
    http.Client? client,
    UserCacheService? userCacheService,
    FirebaseAuth? firebaseAuth,
  })  : _client = client ?? http.Client(),
        _userCacheService = userCacheService ?? UserCacheService(),
        _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final http.Client _client;
  final UserCacheService _userCacheService;
  final FirebaseAuth _firebaseAuth;

  String get _environment =>
      EnvironmentService.instance.isTestMode ? 'test' : 'production';

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

    final headers = <String, String>{
      'Content-Type': 'application/json',
    };

    if (requireAuth) {
      final currentUser = _firebaseAuth.currentUser;
      if (currentUser == null) {
        throw BackendApiException('אין סשן פעיל. יש להתחבר מחדש.');
      }
      final token = await currentUser.getIdToken();
      headers['Authorization'] = 'Bearer $token';
    }

    final response = await _client.post(
      _buildUri(path),
      headers: headers,
      body: jsonEncode(requestBody),
    );

    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return decoded;
    }

    final errorMessage = decoded['error']?.toString() ?? 'Backend request failed';
    if (response.statusCode == 401 && requireAuth) {
      await _firebaseAuth.signOut();
      await _userCacheService.clearSelection();
    }
    throw BackendApiException(errorMessage, statusCode: response.statusCode);
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
    await _firebaseAuth.signOut();
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
  const BackendApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
