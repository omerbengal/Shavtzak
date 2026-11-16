import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/crud_action_result.dart';
import 'package:shavtzak/core/utils/debounced_saver.dart';

/// Omer, 16/11/2026: no save button on a task's owners / events; every tick
/// saves. Rapid ticks are one call, one call at a time, a refusal rolls back.
void main() {
  late List<List<String>> sent;
  late List<List<String>?> drafts;
  late List<String> failures;
  late List<Completer<CrudActionResult>> replies;

  DebouncedSaver<List<String>> saver({bool gated = false, String? Function(List<String>)? validate}) {
    return DebouncedSaver<List<String>>(
      send: (value) {
        sent.add(value);
        if (!gated) return Future.value(const CrudActionResult.success());
        final reply = Completer<CrudActionResult>();
        replies.add(reply);
        return reply.future;
      },
      onDraft: drafts.add,
      validate: validate,
      onFailure: failures.add,
    );
  }

  setUp(() {
    sent = [];
    drafts = [];
    failures = [];
    replies = [];
  });

  test('rapid ticks are shown at once and sent as ONE call with the last state', () {
    fakeAsync((async) {
      final s = saver();
      s.change(['a']);
      async.elapse(const Duration(milliseconds: 300));
      s.change(['a', 'b']);
      async.elapse(const Duration(milliseconds: 300));
      s.change(['b']);
      expect(drafts, [
        ['a'],
        ['a', 'b'],
        ['b'],
      ]);
      expect(sent, isEmpty);
      async.elapse(DebouncedSaver.defaultDelay);
      expect(sent, [
        ['b'],
      ]);
    });
  });

  test('one call in flight: a tick meanwhile is sent after it returns, never before', () {
    fakeAsync((async) {
      final s = saver(gated: true);
      s.change(['a']);
      async.elapse(DebouncedSaver.defaultDelay);
      expect(sent, [
        ['a'],
      ]);
      s.change(['a', 'b']);
      s.change(['a', 'b', 'c']);
      async.elapse(const Duration(seconds: 2));
      // Still only the first: it has not returned.
      expect(sent.length, 1);
      replies.single.complete(const CrudActionResult.success());
      async.flushMicrotasks();
      expect(sent, [
        ['a'],
        ['a', 'b', 'c'],
      ]);
    });
  });

  test('a refused call takes the change back and reports it', () {
    fakeAsync((async) {
      final s = saver(gated: true);
      s.change(['a']);
      async.elapse(DebouncedSaver.defaultDelay);
      s.change(['a', 'b']);
      replies.single.complete(const CrudActionResult.failure('אין הרשאה'));
      async.flushMicrotasks();
      expect(failures, ['אין הרשאה']);
      expect(s.revision, 1);
      // The waiting tick, built on the refused one, is dropped too.
      expect(drafts.last, isNull);
      async.elapse(const Duration(seconds: 2));
      expect(sent.length, 1);
    });
  });

  test('an invalid selection is neither sent nor shown, and says why', () {
    fakeAsync((async) {
      final s = saver(validate: (ids) => ids.isEmpty ? 'צריך לפחות אחד' : null);
      s.change(['a']);
      s.change([]);
      expect(s.error, 'צריך לפחות אחד');
      expect(drafts.last, isNull);
      async.elapse(const Duration(seconds: 2));
      expect(sent, isEmpty);
      s.change(['b']);
      expect(s.error, isNull);
      async.elapse(DebouncedSaver.defaultDelay);
      expect(sent, [
        ['b'],
      ]);
    });
  });

  test('flush on close sends a waiting change at once; dispose does too', () {
    fakeAsync((async) {
      final s = saver();
      s.change(['a']);
      s.flush();
      expect(sent, [
        ['a'],
      ]);
      async.flushMicrotasks();
      s.change(['b']);
      s.dispose();
      expect(sent.last, ['b']);
      async.elapse(const Duration(seconds: 2));
      expect(sent.length, 2);
    });
  });
}
