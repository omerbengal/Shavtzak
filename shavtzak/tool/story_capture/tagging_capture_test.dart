// Captures the REAL app screens a feature story is drawn from (here: the
// @-tagging story), with made-up names, as PNGs for the Remotion project
// (feature_stories/public/<story>/). Not part of the test suite: run it on
// purpose, from shavtzak/:
//
//   flutter test tool/story_capture/tagging_capture_test.dart --update-goldens
//
// The PNGs land in tool/story_capture/out/tagging/ (git-ignored); copy them
// to feature_stories/public/tagging/. See .claude/skills/feature-story.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/repositories/team_task_repository.dart';
import 'package:shavtzak/domain/entities/team_task.dart';

import '../../test/support/task_fixtures.dart';
import '../../test/support/team_task_fixtures.dart';
import 'capture_support.dart';

void main() {
  setUpAll(loadStoryFonts);

  final dana = buildMember(id: 'm1', name: 'דנה לוי', isPermanent: true);
  final yossi = buildMember(id: 'm2', name: 'יוסי כהן', isPermanent: true);
  final noa = buildMember(id: 'm3', name: 'נועה ברק', isPermanent: true);
  final amit = buildMember(id: 'm4', name: 'עמית שלום');

  const topic = TaskLink(TaskLinkType.topic, 'p1');
  final logistics = buildTopic(name: 'לוגיסטיקה');
  TeamTaskBoard board(List<TeamTask> tasks) => TeamTaskBoard(
        tasks: [for (final t in tasks) t.copyWith(topic: () => logistics)],
        members: [dana, yossi, noa, amit],
        topics: [logistics],
        categories: [buildCategory()],
      );

  final hall = buildTeamTask(id: 'a', title: 'להזמין אולם לטקס', link: topic, assigneeIds: ['m1'])
      .copyWith(owners: [dana]);
  final buses = buildTeamTask(id: 'b', title: 'לסגור הסעות', link: topic, assigneeIds: ['m1'])
      .copyWith(owners: [dana]);
  final mattresses =
      buildTeamTask(id: 'c', title: 'לתאם מזרנים', link: topic, assigneeIds: ['m2'])
          .copyWith(owners: [yossi]);
  const tagText = '@יוסי כהן תבדוק מחיר מול הספק';
  final hallTagged = hall.copyWith(updates: [
    TaskUpdateEntry(id: 'u1', text: tagText, at: DateTime(2026, 11, 15, 8), byId: 'm1'),
  ], mentions: [
    TeamTaskMention(memberId: 'm2', updateId: 'u1', byId: 'm1', at: DateTime(2026, 11, 15, 8)),
  ]);

  testWidgets('tagging: the writer tags', (tester) async {
    await pumpTeamTasksAsApp(tester, user: dana, board: board([hall, buses]));
    await capture(tester, 'tagging/01_writer_list');
    mark(tester, 'quickUpdate', find.byKey(const Key('team-task-quick-update-a')));
    mark(tester, 'writerRow', find.byKey(const Key('team-task-row-a')));

    await tester.tap(find.byKey(const Key('team-task-quick-update-a')));
    await tester.pumpAndSettle();
    await capture(tester, 'tagging/02_writer_update_open');
    mark(tester, 'updateField', find.byKey(const Key('team-task-update-field')));

    final field = find.byKey(const Key('team-task-update-field'));
    await tester.enterText(field, '@');
    await tester.pumpAndSettle();
    await capture(tester, 'tagging/03_writer_at_list');

    await tester.enterText(field, '@יו');
    await tester.pumpAndSettle();
    await capture(tester, 'tagging/04_writer_at_query');
    mark(tester, 'pickYossi', find.byKey(const Key('team-task-mention-option-m2')));

    await tester.tap(find.byKey(const Key('team-task-mention-option-m2')));
    await tester.pumpAndSettle();
    await capture(tester, 'tagging/05_writer_picked');

    await tester.enterText(field, '$tagText ');
    await tester.pumpAndSettle();
    await capture(tester, 'tagging/06_writer_typed');
    mark(tester, 'send', find.byKey(const Key('team-task-update-send')));
  });

  testWidgets('tagging: the tagged member', (tester) async {
    final harness =
        await pumpTeamTasksAsApp(tester, user: yossi, board: board([mattresses, hall]));
    await capture(tester, 'tagging/07_tagged_before');

    await harness.deliver(tester, board([mattresses, hallTagged]));
    await tester.pumpAndSettle();
    await capture(tester, 'tagging/08_tagged_after');
    mark(tester, 'taggedRow', find.byKey(const Key('team-task-row-a-u1')));
    mark(tester, 'taggedBox', find.byKey(const Key('team-task-mention-box-a-u1')));

    await tester.tap(find.byKey(const Key('team-task-mention-box-a-u1')));
    await tester.pumpAndSettle();
    await capture(tester, 'tagging/09_tagged_done_dialog');
    mark(tester, 'doneConfirm', find.byKey(const Key('team-task-mention-done-confirm')));

    await harness.deliver(tester, board([mattresses, hall]));
    await tester.tap(find.byKey(const Key('team-task-mention-done-cancel')));
    await tester.pumpAndSettle();
    await capture(tester, 'tagging/10_tagged_done');
    writePoints('tagging');
  });
}
