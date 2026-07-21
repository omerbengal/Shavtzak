/// Whether a Firestore query snapshot should be forwarded to stream consumers.
///
/// Skips the cold-start "empty from cache" snapshot: when a `.snapshots()`
/// listener attaches to a collection whose local cache is empty, Firestore
/// emits an empty snapshot from cache first (`isFromCache == true`), then the
/// authoritative server snapshot. Forwarding that first empty snapshot makes
/// consumers flash "no data" before the real data arrives — and, combined with
/// a slow/stuck first server snapshot, can leave them stuck showing empty until
/// a full reload.
///
/// Every other snapshot is forwarded, including a genuinely-empty *server*
/// snapshot (`isFromCache == false`), so a truly empty collection still
/// resolves to an empty result rather than hanging.
bool shouldEmitFirestoreSnapshot({
  required bool isFromCache,
  required bool isEmpty,
}) {
  return !(isFromCache && isEmpty);
}
