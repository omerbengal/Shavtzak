import 'package:equatable/equatable.dart';

/// A topic ("נושא") a team task can belong to, such as "נשות מגדים" or
/// "כללי". A managed list like the categories ("ניהול נושאים"): stored in
/// `utilities/Lists` → `TaskTopics`. An archived topic stays on its tasks.
class TaskTopic extends Equatable {
  final String id;
  final String name;
  final int sortOrder;
  final bool isArchived;

  const TaskTopic({
    required this.id,
    required this.name,
    this.sortOrder = 0,
    this.isArchived = false,
  });

  TaskTopic copyWith({String? name, int? sortOrder, bool? isArchived}) => TaskTopic(
        id: id,
        name: name ?? this.name,
        sortOrder: sortOrder ?? this.sortOrder,
        isArchived: isArchived ?? this.isArchived,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'sortOrder': sortOrder,
        'isArchived': isArchived,
      };

  /// Null for an entry without an id or a name.
  static TaskTopic? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final name = (raw['name'] as String? ?? '').trim();
    if (id is! String || id.isEmpty || name.isEmpty) return null;
    return TaskTopic(
      id: id,
      name: name,
      sortOrder: (raw['sortOrder'] as num?)?.toInt() ?? 0,
      isArchived: raw['isArchived'] == true,
    );
  }

  /// The list in its order (`sortOrder`).
  static List<TaskTopic> listFromJson(Object? raw) {
    if (raw is! List) return const [];
    return raw.map(TaskTopic.fromJson).whereType<TaskTopic>().toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  @override
  List<Object?> get props => [id, name, sortOrder, isArchived];
}
