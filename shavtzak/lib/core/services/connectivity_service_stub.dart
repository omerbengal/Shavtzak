/// Stub implementation for non-web platforms.
/// Always returns online since this feature is web-specific.

/// Get current online status (always true for non-web platforms)
bool getOnlineStatus() => true;

/// Stream of connectivity changes (empty for non-web platforms)
Stream<bool> onConnectivityChanged() => const Stream.empty();
