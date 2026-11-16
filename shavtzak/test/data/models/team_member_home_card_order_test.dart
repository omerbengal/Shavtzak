import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shavtzak/data/models/team_member_model.dart';
import 'package:shavtzak/domain/entities/team_member.dart';

TeamMember _member({List<String> order = const []}) => TeamMember(
      id: 'm1',
      name: 'עומר',
      isActive: true,
      constraints: const [],
      roleCapabilities: const {},
      createdAt: DateTime(2026, 11, 1),
      updatedAt: DateTime(2026, 11, 1),
      uniqueKey: 'm1',
      isAdmin: true,
      homeCardOrder: order,
    );

void main() {
  test('the home card order survives the device snapshot (toJson/fromJson)',
      () {
    final member = _member(order: const ['summary', 'personal']);
    final back =
        TeamMemberModel.fromJson(TeamMemberModel.fromEntity(member).toJson())
            .toEntity();
    expect(back.homeCardOrder, ['summary', 'personal']);
  });

  test('a snapshot from before the field reads as the default order', () {
    final json = TeamMemberModel.fromEntity(_member()).toJson()
      ..remove('homeCardOrder');
    expect(TeamMemberModel.fromJson(json).toEntity().homeCardOrder, isEmpty);
  });

  test('reads the order from Firestore; a malformed value = default', () async {
    final db = FakeFirebaseFirestore();
    final data = TeamMemberModel.fromEntity(_member()).toFirestore();
    await db.collection('teamMembers').doc('a').set({
      ...data,
      'homeCardOrder': ['teamTasks', 3, 'duYomi'],
    });
    await db.collection('teamMembers').doc('b').set({
      ...data,
      'homeCardOrder': 'oops',
    });
    final a = TeamMemberModel.fromFirestore(
            await db.collection('teamMembers').doc('a').get())
        .toEntity();
    final b = TeamMemberModel.fromFirestore(
            await db.collection('teamMembers').doc('b').get())
        .toEntity();
    expect(a.homeCardOrder, ['teamTasks', 'duYomi']);
    expect(b.homeCardOrder, isEmpty);
  });

  test('a new order is a different member (the screen rebuilds)', () {
    expect(_member(order: const ['a']), isNot(_member(order: const ['b'])));
  });
}
