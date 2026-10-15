import 'package:equatable/equatable.dart';

import 'stage.dart';
import 'task_item.dart';

/// A stage read from an import file, with the tasks that go under it. Every
/// id is chosen already, so sending the same import twice cannot create it
/// twice.
class ImportedStage extends Equatable {
  const ImportedStage({required this.stage, required this.tasks});

  final Stage stage;
  final List<TaskItem> tasks;

  @override
  List<Object?> get props => [stage, tasks];
}
