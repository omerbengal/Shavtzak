import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/core/utils/task_edit_overlay.dart';
import 'package:shavtzak/domain/entities/subtask.dart';
import 'package:shavtzak/domain/entities/task_item.dart';

import '../../support/task_fixtures.dart';

void main() {
  EditOverlay<TaskItem> overlay() => EditOverlay<TaskItem>(sameTaskEdit);
  final live = buildTask(id: 't1', title: 'ישן');

  test('resolve returns live when nothing sent', () {
    expect(overlay().resolve('t1', live), live);
  });

  test('overlay keeps the newer sent version as the base', () {
    final o = overlay();
    final a = live.copyWith(title: 'חדש');
    final b = a.copyWith(description: 'תיאור');
    o.sent('t1', a);
    o.sent('t1', b);
    expect(o.resolve('t1', live), b);
  });

  test('reconcile drops a matching entry', () {
    final o = overlay();
    final sent = live.copyWith(title: 'חדש');
    o.sent('t1', sent);
    // The stream brings it back with a new timestamp and a tick.
    o.reconcile(
        {'t1': sent.copyWith(updatedAt: DateTime(2030), isComplete: true)});
    expect(o.isEmpty, isTrue);
  });

  test('reconcile keeps a non-matching entry', () {
    final o = overlay();
    o.sent('t1', live.copyWith(title: 'חדש'));
    o.reconcile({'t1': live});
    expect(o.resolve('t1', live).title, 'חדש');
  });

  test('a renamed subtask does not match', () {
    final withSub =
        live.copyWith(subtasks: const [Subtask(id: 's', title: 'א')]);
    final renamed =
        live.copyWith(subtasks: const [Subtask(id: 's', title: 'ב')]);
    expect(sameTaskEdit(withSub, renamed), isFalse);
    expect(sameTaskEdit(withSub, withSub.copyWith()), isTrue);
  });

  test('failed entry is dropped', () {
    final o = overlay();
    o.sent('t1', live.copyWith(title: 'חדש'));
    o.failed('t1');
    expect(o.resolve('t1', live), live);
  });

  test('reconcile drops an entry whose item is gone', () {
    final o = overlay();
    o.sent('t1', live.copyWith(title: 'חדש'));
    o.reconcile(const {});
    expect(o.isEmpty, isTrue);
  });
}
