import 'dart:async';
import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/feature_stories.dart';
import '../web/web_stub.dart' if (dart.library.js) '../web/web_helper.dart';

/// Global app-version gate based on Firestore realtime updates.
///
/// Source of truth:
/// - collection: utilities
/// - document: information
/// - field: version (string)
///
/// Behavior:
/// - If cached version is empty, seed it from Firestore and allow usage.
/// - If cached version exists and differs from Firestore version, block usage.
/// - If Firestore value is missing/invalid/unavailable, fail open (allow usage).
class AppVersionService extends ChangeNotifier {
  static AppVersionService? _instance;

  static AppVersionService get instance {
    _instance ??= AppVersionService._internal();
    return _instance!;
  }

  AppVersionService._internal();

  static const String _versionCacheKey = 'version';
  static const String _collection = 'utilities';
  static const String _document = 'information';
  static const String _field = 'version';
  static const String _whatsNewField = 'WhatsNew';
  static const String _storiesField = 'WhatsNewStories';

  /// The version whose stories this browser already opened (Omer,
  /// 20/11/2026, option A): every member sees the running version's stories
  /// once, whatever refresh button brought them there (`storiesUnseen`).
  static const String _storiesSeenKey = 'stories_seen_version';

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _subscription;
  StreamSubscription<User?>? _authSubscription;

  bool _initialized = false;
  bool _isBlocked = false;
  String? _cachedVersion;
  String? _remoteVersion;
  List<String> _whatsNewItems = const [];
  List<FeatureStory> _stories = const [];
  bool _hasRemoteData = false;

  bool get isBlocked => _isBlocked;
  String? get cachedVersion => _cachedVersion;
  String? get remoteVersion => _remoteVersion;
  List<String> get whatsNewItems => List.unmodifiable(_whatsNewItems);

  /// This version's feature stories (`WhatsNewStories`), every audience.
  List<FeatureStory> get stories => _stories;

  /// `utilities/information` has been read at least once since sign-in.
  bool get hasRemoteData => _hasRemoteData;

  void initialize() {
    if (_initialized) return;
    _initialized = true;
    unawaited(_initializeInternal());
  }

  Future<void> _initializeInternal() async {
    await _loadCachedVersion();
    _bindAuthState();
  }

  Future<void> _loadCachedVersion() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final version = prefs.getString(_versionCacheKey)?.trim();
      _cachedVersion = (version == null || version.isEmpty) ? null : version;
    } catch (e) {
      developer.log(
        'AppVersionService: Failed to load cached version: $e',
        name: 'AppVersion',
      );
      _cachedVersion = null;
    }
  }

  void _bindAuthState() {
    _authSubscription?.cancel();
    _authSubscription = _auth.authStateChanges().listen(
      (user) {
        if (user == null) {
          _stopRealtimeListener();
          _remoteVersion = null;
          _setWhatsNewItems(const []);
          _setBlocked(false);
          return;
        }
        _startRealtimeListener();
      },
      onError: (Object error, StackTrace stackTrace) {
        developer.log(
          'AppVersionService: Auth state stream error: $error',
          name: 'AppVersion',
          error: error,
          stackTrace: stackTrace,
        );
        _stopRealtimeListener();
        _remoteVersion = null;
        _setWhatsNewItems(const []);
        _setBlocked(false);
      },
    );

    if (_auth.currentUser != null) {
      _startRealtimeListener();
    }
  }

  void _startRealtimeListener() {
    _subscription?.cancel();
    _subscription =
        _firestore.collection(_collection).doc(_document).snapshots().listen(
      (snapshot) async {
        await _handleSnapshot(snapshot);
      },
      onError: (Object error, StackTrace stackTrace) {
        // Fail open when version cannot be confirmed.
        developer.log(
          'AppVersionService: Version stream error: $error',
          name: 'AppVersion',
          error: error,
          stackTrace: stackTrace,
        );
        _remoteVersion = null;
        _setWhatsNewItems(const []);
        _setBlocked(false);
      },
    );
  }

  void _stopRealtimeListener() {
    _subscription?.cancel();
    _subscription = null;
  }

  Future<void> _handleSnapshot(
    DocumentSnapshot<Map<String, dynamic>> snapshot,
  ) async {
    final data = snapshot.data();
    _stories = parseFeatureStories(data?[_storiesField]);
    final firstRead = !_hasRemoteData;
    try {
      await _applyVersion(data);
    } finally {
      // The stories gate waits for the first read, and for the version to be
      // applied (a new device saves it as its cached version first).
      _hasRemoteData = true;
      if (firstRead) notifyListeners();
    }
  }

  Future<void> _applyVersion(Map<String, dynamic>? data) async {
    _setWhatsNewItems(_parseWhatsNewItems(data?[_whatsNewField]));

    final rawVersion = data?[_field];
    final version = rawVersion is String ? rawVersion.trim() : '';

    if (version.isEmpty) {
      // Missing/invalid version -> fail open.
      _remoteVersion = null;
      _setBlocked(false);
      return;
    }

    _remoteVersion = version;

    if (_cachedVersion == null || _cachedVersion!.isEmpty) {
      await _saveCachedVersion(version);
      _setBlocked(false);
      return;
    }

    _setBlocked(_cachedVersion != version);
  }

  List<String> _parseWhatsNewItems(dynamic raw) {
    if (raw is! List) return const [];

    final items = <String>[];
    for (final item in raw) {
      if (item is String) {
        final normalized = item.trim();
        if (normalized.isNotEmpty) {
          items.add(normalized);
        }
      }
    }
    return items;
  }

  void _setWhatsNewItems(List<String> items) {
    if (listEquals(_whatsNewItems, items)) return;
    _whatsNewItems = List.unmodifiable(items);
    notifyListeners();
  }

  Future<void> _saveCachedVersion(String version) async {
    final normalized = version.trim();
    if (normalized.isEmpty) return;

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_versionCacheKey, normalized);
      _cachedVersion = normalized;
    } catch (e) {
      developer.log(
        'AppVersionService: Failed to save cached version: $e',
        name: 'AppVersion',
      );
    }
  }

  void _setBlocked(bool blocked) {
    if (_isBlocked == blocked) return;
    _isBlocked = blocked;
    notifyListeners();
  }

  Future<void> refreshApp() async {
    final currentRemoteVersion = _remoteVersion;
    if (currentRemoteVersion != null && currentRemoteVersion.isNotEmpty) {
      await _saveCachedVersion(currentRemoteVersion);
    }
    WebHelper.reloadPage();
  }

  /// True when this browser has not yet opened the stories of the version it
  /// runs now (and the server confirms it: [remoteVersion] is it too, so a
  /// browser waiting for a refresh sees nothing yet).
  Future<bool> storiesUnseen() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return storiesUnseenFor(
        seen: prefs.getString(_storiesSeenKey),
        cached: _cachedVersion,
        remote: _remoteVersion,
      );
    } catch (e) {
      developer.log('AppVersionService: Failed to read the stories mark: $e',
          name: 'AppVersion');
      return false;
    }
  }

  /// The stories of the version running now were opened in this browser.
  Future<void> markStoriesSeen() async {
    final version = _remoteVersion?.trim();
    if (version == null || version.isEmpty) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storiesSeenKey, version);
    } catch (e) {
      developer.log('AppVersionService: Failed to mark stories seen: $e',
          name: 'AppVersion');
    }
  }

  @override
  void dispose() {
    _stopRealtimeListener();
    _authSubscription?.cancel();
    _authSubscription = null;
    super.dispose();
  }
}
