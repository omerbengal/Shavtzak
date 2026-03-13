import 'dart:developer' as developer;

import 'package:firebase_auth/firebase_auth.dart';

import 'backend_api_service.dart';
import 'oauth_popup_bridge.dart';

/// Service for handling Google OAuth 2.0 authentication via backend endpoints.
/// The browser never receives the Google client secret or refresh tokens.
class GoogleOAuthService {
  static GoogleOAuthService? _instance;

  final BackendApiService _backendApiService;
  bool _isInitialized = false;
  bool _isAuthenticated = false;
  String? _authenticatedUserEmail;

  GoogleOAuthService._(this._backendApiService);

  static GoogleOAuthService get instance {
    _instance ??= GoogleOAuthService._(BackendApiService());
    return _instance!;
  }

  bool get isInitialized => _isInitialized;

  bool get isAuthenticated => _isAuthenticated;

  String? get authenticatedUserEmail => _authenticatedUserEmail;

  Future<void> initialize() async {
    if (_isInitialized) {
      return;
    }

    _isInitialized = true;
    await refreshStatus();
  }

  Future<bool> refreshStatus() async {
    if (!_isInitialized) {
      _isInitialized = true;
    }

    if (FirebaseAuth.instance.currentUser == null) {
      _isAuthenticated = false;
      _authenticatedUserEmail = null;
      return false;
    }

    try {
      final status = await _backendApiService.getCalendarStatus();
      _isAuthenticated = status['isAuthenticated'] == true;
      _authenticatedUserEmail = status['authenticatedUserEmail'] as String?;
      return _isAuthenticated;
    } on BackendApiException catch (e) {
      // Before the user logs in, or for non-admin connection-management flows,
      // the calendar status call can fail. Treat that as "not connected".
      developer.log(
        'GoogleOAuthService: Calendar status unavailable - ${e.message}',
        name: 'GoogleOAuth',
      );
      _isAuthenticated = false;
      _authenticatedUserEmail = null;
      return false;
    } catch (e) {
      developer.log(
        'GoogleOAuthService: Failed to refresh status - $e',
        name: 'GoogleOAuth',
        error: e,
      );
      _isAuthenticated = false;
      _authenticatedUserEmail = null;
      return false;
    }
  }

  Future<bool> signIn() async {
    if (!_isInitialized) {
      throw StateError(
        'GoogleOAuthService not initialized. Call initialize() first.',
      );
    }

    try {
      final origin = getOAuthCurrentOrigin();
      final redirectUri = '$origin/oauth-callback.html';
      final startResponse = await _backendApiService.startCalendarOAuth(
        redirectUri: redirectUri,
      );
      final authUrl = startResponse['authUrl'] as String?;

      if (authUrl == null || authUrl.isEmpty) {
        return false;
      }

      final authCode = await openOAuthPopupAndWaitForCode(authUrl);
      if (authCode == null || authCode.isEmpty) {
        return false;
      }

      await _backendApiService.exchangeCalendarOAuthCode(
        code: authCode,
        redirectUri: redirectUri,
      );

      return await refreshStatus();
    } catch (e) {
      developer.log(
        'GoogleOAuthService: Sign-in failed - $e',
        name: 'GoogleOAuth',
        error: e,
      );
      return false;
    }
  }

  Future<void> signOut() async {
    try {
      await _backendApiService.disconnectCalendarOAuth();
    } catch (e) {
      developer.log(
        'GoogleOAuthService: Sign-out failed - $e',
        name: 'GoogleOAuth',
        error: e,
      );
    } finally {
      _isAuthenticated = false;
      _authenticatedUserEmail = null;
    }
  }

  void dispose() {
    _isInitialized = false;
    _isAuthenticated = false;
    _authenticatedUserEmail = null;
  }
}
