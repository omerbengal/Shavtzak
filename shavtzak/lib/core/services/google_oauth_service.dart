import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'dart:developer' as developer;
import 'dart:async';

import 'environment_service.dart';
import 'oauth_popup_bridge.dart';

/// Service for handling Google OAuth 2.0 authentication with refresh tokens
/// Properly implements OAuth 2.0 flow to get long-lived refresh tokens
class GoogleOAuthService {
  static GoogleOAuthService? _instance;

  final FirebaseFirestore _firestore;
  String? _clientId;
  String? _clientSecret;
  bool _isInitialized = false;

  // OAuth tokens
  String? _accessToken;
  String? _refreshToken;
  DateTime? _expiresAt;
  String? _authenticatedUserEmail;

  // OAuth flow state
  StreamController<bool>? _authStateController;

  GoogleOAuthService._(this._firestore);

  static GoogleOAuthService get instance {
    _instance ??= GoogleOAuthService._(FirebaseFirestore.instance);
    return _instance!;
  }

  /// Check if the service is initialized
  bool get isInitialized => _isInitialized;

  /// Check if user is authenticated (has valid tokens)
  bool get isAuthenticated {
    return _accessToken != null && _refreshToken != null;
  }

  /// Get authenticated user email
  String? get authenticatedUserEmail {
    return _authenticatedUserEmail;
  }

  /// Get collection name with environment prefix
  String get _keysCollection {
    final prefix = EnvironmentService.instance.collectionPrefix;
    return '${prefix}keys';
  }

  /// Initialize the service by loading credentials from Firestore
  Future<void> initialize() async {
    try {
      developer.log(
        'GoogleOAuthService: Initializing...',
        name: 'GoogleOAuth',
      );

      // Load OAuth credentials from Firestore
      final doc = await _firestore.collection(_keysCollection).doc('googleCalendar').get();

      if (!doc.exists) {
        throw Exception('Google Calendar credentials not found in Firestore');
      }

      final data = doc.data()!;
      _clientId = data['clientId'] as String?;
      _clientSecret = data['clientSecret'] as String?;

      if (_clientId == null || _clientSecret == null) {
        throw Exception('clientId or clientSecret missing in Firestore');
      }

      // Try to load existing OAuth tokens from Firestore
      await _loadStoredTokens();

      _isInitialized = true;

      developer.log(
        'GoogleOAuthService: Initialized successfully',
        name: 'GoogleOAuth',
      );
    } catch (e) {
      developer.log(
        'GoogleOAuthService: Failed to initialize - $e',
        name: 'GoogleOAuth',
        error: e,
      );
      rethrow;
    }
  }

  /// Load stored OAuth tokens from Firestore
  Future<void> _loadStoredTokens() async {
    try {
      final doc = await _firestore.collection(_keysCollection).doc('googleCalendarOAuth').get();

      if (doc.exists) {
        final data = doc.data()!;
        _accessToken = data['accessToken'] as String?;
        _refreshToken = data['refreshToken'] as String?;
        final expiresAtTimestamp = data['expiresAt'] as Timestamp?;
        _expiresAt = expiresAtTimestamp?.toDate().toUtc();
        _authenticatedUserEmail = data['authenticatedBy'] as String?;

        developer.log(
          'GoogleOAuthService: Loaded stored tokens\n'
          '  Has accessToken: ${_accessToken != null}\n'
          '  Has refreshToken: ${_refreshToken != null}\n'
          '  Expires at (UTC): $_expiresAt\n'
          '  Authenticated by: $_authenticatedUserEmail',
          name: 'GoogleOAuth',
        );

        // Check if token is expired and refresh if we have a refresh token
        if (_isTokenExpired() && _refreshToken != null) {
          developer.log(
            'GoogleOAuthService: Token expired, attempting refresh with refresh token...',
            name: 'GoogleOAuth',
          );
          await _refreshAccessToken();
        }
      } else {
        developer.log(
          'GoogleOAuthService: No stored tokens found',
          name: 'GoogleOAuth',
        );
      }
    } catch (e) {
      developer.log(
        'GoogleOAuthService: Failed to load stored tokens - $e',
        name: 'GoogleOAuth',
        error: e,
      );
    }
  }

  /// Check if access token is expired or about to expire
  bool _isTokenExpired() {
    if (_expiresAt == null) return true;

    final now = DateTime.now().toUtc();
    final expiresWithBuffer = _expiresAt!.subtract(const Duration(minutes: 5));

    return now.isAfter(expiresWithBuffer);
  }

  /// Start OAuth 2.0 sign-in flow with offline access to get refresh token
  /// Returns true if successful, false otherwise
  Future<bool> signIn() async {
    if (!_isInitialized) {
      throw StateError('GoogleOAuthService not initialized. Call initialize() first.');
    }

    try {
      developer.log(
        'GoogleOAuthService: Starting OAuth 2.0 sign-in flow with offline access...',
        name: 'GoogleOAuth',
      );

      // Get the current origin for redirect URI (using dedicated callback page)
      final origin = getOAuthCurrentOrigin();
      final redirectUri = '$origin/oauth-callback.html';

      // Build OAuth 2.0 authorization URL with offline access
      final authUrl = Uri.https('accounts.google.com', '/o/oauth2/v2/auth', {
        'client_id': _clientId!,
        'redirect_uri': redirectUri,
        'response_type': 'code',
        'scope': 'https://www.googleapis.com/auth/calendar email',
        'access_type': 'offline', // CRITICAL: Request offline access for refresh token
        'prompt': 'consent', // Force consent screen to ensure refresh token is issued
        'state': 'oauth_state_${DateTime.now().millisecondsSinceEpoch}',
      });

      developer.log(
        'GoogleOAuthService: Opening OAuth consent screen...\n'
        '  Redirect URI: $redirectUri\n'
        '  Requesting offline access for refresh token',
        name: 'GoogleOAuth',
      );

      // Open OAuth consent screen in popup and wait for callback code.
      final authCode = await openOAuthPopupAndWaitForCode(authUrl.toString());

      if (authCode == null) {
        developer.log(
          'GoogleOAuthService: Sign-in cancelled or timed out',
          name: 'GoogleOAuth',
        );
        return false;
      }

      developer.log(
        'GoogleOAuthService: Received authorization code, exchanging for tokens...',
        name: 'GoogleOAuth',
      );

      // Exchange authorization code for tokens
      return await _exchangeCodeForTokens(authCode, redirectUri);

    } catch (e) {
      developer.log(
        'GoogleOAuthService: Sign-in failed - $e',
        name: 'GoogleOAuth',
        error: e,
      );
      return false;
    }
  }

  /// Exchange authorization code for access token and refresh token
  Future<bool> _exchangeCodeForTokens(String code, String redirectUri) async {
    try {
      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'code': code,
          'client_id': _clientId!,
          'client_secret': _clientSecret!,
          'redirect_uri': redirectUri,
          'grant_type': 'authorization_code',
        },
      );

      if (response.statusCode != 200) {
        developer.log(
          'GoogleOAuthService: Token exchange failed - ${response.statusCode}: ${response.body}',
          name: 'GoogleOAuth',
        );
        return false;
      }

      final data = json.decode(response.body);

      _accessToken = data['access_token'] as String?;
      _refreshToken = data['refresh_token'] as String?; // CRITICAL: Store refresh token
      final expiresIn = data['expires_in'] as int?;

      if (expiresIn != null) {
        _expiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
      }

      // Get user info to store email
      if (_accessToken != null) {
        await _fetchUserInfo();
      }

      developer.log(
        'GoogleOAuthService: Successfully obtained tokens!\n'
        '  Has accessToken: ${_accessToken != null}\n'
        '  Has refreshToken: ${_refreshToken != null} ← CRITICAL!\n'
        '  Expires in: ${expiresIn}s\n'
        '  Email: $_authenticatedUserEmail',
        name: 'GoogleOAuth',
      );

      // Store tokens in Firestore
      await _storeTokens();

      return _accessToken != null && _refreshToken != null;

    } catch (e) {
      developer.log(
        'GoogleOAuthService: Token exchange failed - $e',
        name: 'GoogleOAuth',
        error: e,
      );
      return false;
    }
  }

  /// Fetch user info to get email address
  Future<void> _fetchUserInfo() async {
    try {
      final response = await http.get(
        Uri.parse('https://www.googleapis.com/oauth2/v2/userinfo'),
        headers: {'Authorization': 'Bearer $_accessToken'},
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        _authenticatedUserEmail = data['email'] as String?;
      }
    } catch (e) {
      developer.log(
        'GoogleOAuthService: Failed to fetch user info - $e',
        name: 'GoogleOAuth',
        error: e,
      );
    }
  }

  /// Refresh the access token using the refresh token
  /// This is the KEY method that enables long-term authentication
  Future<void> _refreshAccessToken() async {
    if (_refreshToken == null) {
      developer.log(
        'GoogleOAuthService: No refresh token available, cannot refresh',
        name: 'GoogleOAuth',
      );
      return;
    }

    try {
      developer.log(
        'GoogleOAuthService: Refreshing access token using refresh token...',
        name: 'GoogleOAuth',
      );

      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'client_id': _clientId!,
          'client_secret': _clientSecret!,
          'refresh_token': _refreshToken!,
          'grant_type': 'refresh_token',
        },
      );

      if (response.statusCode != 200) {
        developer.log(
          'GoogleOAuthService: Token refresh failed - ${response.statusCode}: ${response.body}',
          name: 'GoogleOAuth',
          error: response.body,
        );

        // If refresh token is invalid, clear tokens
        _accessToken = null;
        _refreshToken = null;
        _expiresAt = null;
        return;
      }

      final data = json.decode(response.body);

      _accessToken = data['access_token'] as String?;
      // Note: Refresh token is NOT returned in refresh response, keep existing one
      final expiresIn = data['expires_in'] as int?;

      if (expiresIn != null) {
        _expiresAt = DateTime.now().toUtc().add(Duration(seconds: expiresIn));
      }

      developer.log(
        'GoogleOAuthService: Successfully refreshed access token!\n'
        '  New token expires in: ${expiresIn}s\n'
        '  Refresh token preserved: ${_refreshToken != null}',
        name: 'GoogleOAuth',
      );

      // Store updated tokens
      await _storeTokens();

    } catch (e) {
      developer.log(
        'GoogleOAuthService: Token refresh failed - $e',
        name: 'GoogleOAuth',
        error: e,
      );

      // Clear invalid tokens
      _accessToken = null;
      _refreshToken = null;
      _expiresAt = null;
    }
  }

  /// Store OAuth tokens in Firestore
  Future<void> _storeTokens() async {
    if (_accessToken == null) {
      return;
    }

    await _firestore.collection(_keysCollection).doc('googleCalendarOAuth').set({
      'accessToken': _accessToken,
      'refreshToken': _refreshToken,
      'expiresAt': _expiresAt != null ? Timestamp.fromDate(_expiresAt!) : null,
      'authenticatedBy': _authenticatedUserEmail,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    developer.log(
      'GoogleOAuthService: Tokens stored in Firestore',
      name: 'GoogleOAuth',
    );
  }

  /// Sign out and clear stored tokens
  Future<void> signOut() async {
    try {
      // Revoke tokens with Google
      if (_refreshToken != null) {
        await http.post(
          Uri.parse('https://oauth2.googleapis.com/revoke'),
          headers: {'Content-Type': 'application/x-www-form-urlencoded'},
          body: {'token': _refreshToken!},
        );
      }

      // Clear local state
      _accessToken = null;
      _refreshToken = null;
      _expiresAt = null;
      _authenticatedUserEmail = null;

      // Delete stored tokens from Firestore
      await _firestore.collection(_keysCollection).doc('googleCalendarOAuth').delete();

      developer.log(
        'GoogleOAuthService: Signed out and cleared tokens',
        name: 'GoogleOAuth',
      );
    } catch (e) {
      developer.log(
        'GoogleOAuthService: Sign-out failed - $e',
        name: 'GoogleOAuth',
        error: e,
      );
    }
  }

  /// Get a valid access token (refreshes automatically if needed)
  /// This is the magic - it auto-refreshes so the app always has a valid token!
  Future<String?> getAccessToken() async {
    if (!_isInitialized) {
      throw StateError('GoogleOAuthService not initialized. Call initialize() first.');
    }

    // Check if we have a valid token
    if (_accessToken != null && !_isTokenExpired()) {
      return _accessToken;
    }

    // Token is expired or missing, try to refresh
    if (_refreshToken != null) {
      await _refreshAccessToken();
      return _accessToken;
    }

    // No refresh token, user needs to sign in again
    developer.log(
      'GoogleOAuthService: No valid token and no refresh token, user must sign in',
      name: 'GoogleOAuth',
    );
    return null;
  }

  /// Force refresh the access token even if current token is not marked as expired.
  /// Returns true if a valid access token is available after refresh.
  Future<bool> forceRefreshAccessToken() async {
    if (!_isInitialized) {
      developer.log(
        'GoogleOAuthService: Cannot force refresh before initialization',
        name: 'GoogleOAuth',
      );
      return false;
    }

    if (_refreshToken == null) {
      developer.log(
        'GoogleOAuthService: Cannot force refresh without refresh token',
        name: 'GoogleOAuth',
      );
      return false;
    }

    await _refreshAccessToken();
    return _accessToken != null;
  }

  /// Get authenticated HTTP client for API calls
  Future<AuthClient?> getAuthClient() async {
    final token = await getAccessToken();

    if (token == null) {
      developer.log(
        'GoogleOAuthService: Failed to get auth client (re-authentication needed)',
        name: 'GoogleOAuth',
      );
      return null;
    }

    // Create AccessCredentials with refresh token support
    final credentials = AccessCredentials(
      AccessToken(
        'Bearer',
        token,
        _expiresAt ?? DateTime.now().toUtc().add(const Duration(hours: 1)),
      ),
      _refreshToken,
      [
        'https://www.googleapis.com/auth/calendar',
      ],
    );

    // Return authenticated client
    return authenticatedClient(
      http.Client(),
      credentials,
    );
  }

  /// Dispose resources
  void dispose() {
    _authStateController?.close();
    _isInitialized = false;
  }
}
