import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/services/firestore_reconnect_service.dart';

void main() {
  late List<String> calls;
  late DateTime now;
  Completer<void>? gate;
  late Future<void> Function() probe;

  FirestoreReconnectService build({Object? failDisable}) {
    return FirestoreReconnectService(
      disableNetwork: () async {
        calls.add('disable');
        await gate?.future;
        if (failDisable != null) throw failDisable;
      },
      enableNetwork: () async => calls.add('enable'),
      probe: () {
        calls.add('probe');
        return probe();
      },
      checkTimeout: const Duration(milliseconds: 30),
      clock: () => now,
    );
  }

  setUp(() {
    calls = [];
    now = DateTime(2026, 11, 9, 10);
    gate = null;
    probe = () async {};
  });

  test('takes the network down, then up', () async {
    await build().reconnect('test');
    expect(calls, ['disable', 'enable']);
  });

  test('a call while one runs joins it', () async {
    final service = build();
    gate = Completer<void>();
    final first = service.reconnect('a');
    final second = service.reconnect('b');
    gate!.complete();
    await Future.wait([first, second]);
    expect(calls, ['disable', 'enable']);
  });

  test('a call just after one finished is dropped, a later one runs',
      () async {
    final service = build();
    await service.reconnect('a');
    now = now.add(const Duration(seconds: 1));
    await service.reconnect('b');
    expect(calls, ['disable', 'enable']);

    now = now.add(const Duration(seconds: 5));
    await service.reconnect('c');
    expect(calls, ['disable', 'enable', 'disable', 'enable']);
  });

  test('a failed disable still brings the network back up', () async {
    await build(failDisable: StateError('x')).reconnect('a');
    expect(calls, ['disable', 'enable']);
  });

  group('check', () {
    test('an answer leaves the connection alone', () async {
      await build().check('test');
      expect(calls, ['probe']);
    });

    test('no answer reconnects', () async {
      probe = () => Completer<void>().future;
      await build().check('test');
      expect(calls, ['probe', 'disable', 'enable']);
    });

    test('an error is not a stuck connection', () async {
      probe = () async => throw StateError('permission-denied');
      await build().check('test');
      expect(calls, ['probe']);
    });

    test('a check while one runs joins it', () async {
      final answer = Completer<void>();
      probe = () => answer.future;
      final service = build();
      final first = service.check('a');
      final second = service.check('b');
      answer.complete();
      await Future.wait([first, second]);
      expect(calls, ['probe']);
    });
  });

  group('coming back into view', () {
    test('after a real absence, checks', () async {
      final service = build();
      service.onHidden();
      now = now.add(const Duration(seconds: 30));
      service.onShown();
      await Future<void>.delayed(Duration.zero);
      expect(calls, ['probe']);
    });

    test('after a glance away, does nothing', () async {
      final service = build();
      service.onHidden();
      now = now.add(const Duration(milliseconds: 500));
      service.onShown();
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty);
    });

    test('shown without having been hidden, does nothing', () async {
      build().onShown();
      await Future<void>.delayed(Duration.zero);
      expect(calls, isEmpty);
    });
  });
}
