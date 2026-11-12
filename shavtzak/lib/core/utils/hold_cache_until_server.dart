import 'dart:async';

/// Holds a listener's first answers while they come only from the device's
/// cache, until the server confirms (or [grace] passes).
///
/// Why: Firestore answers a new query from whatever this device happens to
/// have cached first. For one event's assignments a member's device mostly
/// holds their OWN assignments (their "האירועים שלי" screen loads those), so
/// that first answer is "only you", replaced ~150 ms later by the server's
/// full list — a visible flash of a wrong list.
///
/// Rules, for a stream of snapshots listened to with metadata changes:
/// * Until the first confirmation: a server snapshot is emitted at once; a
///   cache snapshot is held (the newest one replaces an older held one) and
///   emitted only if nothing from the server arrives within [grace] — so
///   offline or a stuck connection still shows the cached list, never a
///   spinner forever.
/// * After that: every snapshot with data changes is emitted (including
///   cache ones: offline edits); metadata-only changes are skipped.
Stream<T> holdCacheUntilServer<T>(
  Stream<T> snapshots, {
  required bool Function(T snapshot) isFromCache,
  required bool Function(T snapshot) isMetadataOnly,
  Duration grace = const Duration(milliseconds: 1500),
}) {
  late StreamController<T> controller;
  StreamSubscription<T>? subscription;
  Timer? timer;
  var released = false;
  T? held;
  var holding = false;

  void release() {
    released = true;
    timer?.cancel();
    if (holding) {
      holding = false;
      controller.add(held as T);
      held = null;
    }
  }

  controller = StreamController<T>(
    onListen: () {
      subscription = snapshots.listen(
        (snapshot) {
          if (released) {
            if (!isMetadataOnly(snapshot)) controller.add(snapshot);
            return;
          }
          if (!isFromCache(snapshot)) {
            holding = false;
            held = null;
            released = true;
            timer?.cancel();
            controller.add(snapshot);
            return;
          }
          held = snapshot;
          holding = true;
          timer ??= Timer(grace, release);
        },
        onError: controller.addError,
        onDone: () {
          timer?.cancel();
          if (holding) controller.add(held as T);
          controller.close();
        },
      );
    },
    onPause: () => subscription?.pause(),
    onResume: () => subscription?.resume(),
    onCancel: () async {
      timer?.cancel();
      await subscription?.cancel();
    },
  );
  return controller.stream;
}
