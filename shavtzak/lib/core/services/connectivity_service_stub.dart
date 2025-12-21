/// Get current online status (always true for non-web platforms)
bool getOnlineStatus() => true;

/// Stream of connectivity changes (empty for non-web platforms)
Stream<bool> onConnectivityChanged() => const Stream.empty();
