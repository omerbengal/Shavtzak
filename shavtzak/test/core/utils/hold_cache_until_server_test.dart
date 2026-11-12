import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/hold_cache_until_server.dart';

/// A stand-in snapshot: its data, where it came from, and whether it only
/// changed metadata.
class _Snap {
  const _Snap(this.data, {this.cache = false, this.metaOnly = false});
  final String data;
  final bool cache;
  final bool metaOnly;
}

void main() {
  late StreamController<_Snap> source;
  late List<String> seen;

  void listen() {
    holdCacheUntilServer<_Snap>(
      source.stream,
      isFromCache: (s) => s.cache,
      isMetadataOnly: (s) => s.metaOnly,
      grace: const Duration(milliseconds: 1500),
    ).listen((s) => seen.add(s.data));
  }

  setUp(() {
    source = StreamController<_Snap>();
    seen = [];
  });

  test('a partial cache answer is replaced by the server one, never shown',
      () {
    fakeAsync((async) {
      listen();
      source.add(const _Snap('only me', cache: true));
      async.elapse(const Duration(milliseconds: 150));
      expect(seen, isEmpty);
      source.add(const _Snap('everyone'));
      async.flushMicrotasks();
      expect(seen, ['everyone']);
      async.elapse(const Duration(seconds: 5));
      expect(seen, ['everyone']);
    });
  });

  test('a server answer first is shown at once', () {
    fakeAsync((async) {
      listen();
      source.add(const _Snap('everyone'));
      async.flushMicrotasks();
      expect(seen, ['everyone']);
    });
  });

  test('the server confirming the cached list unchanged still shows it', () {
    fakeAsync((async) {
      listen();
      source.add(const _Snap('everyone', cache: true));
      // Same data from the server: a metadata-only change.
      source.add(const _Snap('everyone', metaOnly: true));
      async.flushMicrotasks();
      expect(seen, ['everyone']);
    });
  });

  test('no server answer within the grace: the cached list is shown', () {
    fakeAsync((async) {
      listen();
      source.add(const _Snap('cached', cache: true));
      async.elapse(const Duration(milliseconds: 1499));
      expect(seen, isEmpty);
      async.elapse(const Duration(milliseconds: 2));
      expect(seen, ['cached']);
    });
  });

  test('the newest held cache answer is the one shown', () {
    fakeAsync((async) {
      listen();
      source.add(const _Snap('cached 1', cache: true));
      source.add(const _Snap('cached 2', cache: true));
      async.elapse(const Duration(seconds: 2));
      expect(seen, ['cached 2']);
    });
  });

  test('afterwards: changes pass, metadata-only changes are skipped', () {
    fakeAsync((async) {
      listen();
      source.add(const _Snap('a'));
      source.add(const _Snap('a', metaOnly: true));
      source.add(const _Snap('b'));
      source.add(const _Snap('c (offline edit)', cache: true));
      async.flushMicrotasks();
      expect(seen, ['a', 'b', 'c (offline edit)']);
    });
  });

  test('errors pass through', () {
    fakeAsync((async) {
      final errors = <Object>[];
      holdCacheUntilServer<_Snap>(
        source.stream,
        isFromCache: (s) => s.cache,
        isMetadataOnly: (s) => s.metaOnly,
      ).listen((_) {}, onError: errors.add);
      source.addError(StateError('denied'));
      async.flushMicrotasks();
      expect(errors, hasLength(1));
    });
  });
}
