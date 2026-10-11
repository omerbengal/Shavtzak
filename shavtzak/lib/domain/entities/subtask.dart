import 'package:equatable/equatable.dart';

/// One step of a [TaskItem]: a line of text that can be ticked.
class Subtask extends Equatable {
  final String id;
  final String title;
  final bool isDone;

  const Subtask({
    required this.id,
    required this.title,
    this.isDone = false,
  });

  Subtask copyWith({
    String? id,
    String? title,
    bool? isDone,
  }) {
    return Subtask(
      id: id ?? this.id,
      title: title ?? this.title,
      isDone: isDone ?? this.isDone,
    );
  }

  @override
  List<Object?> get props => [id, title, isDone];
}
