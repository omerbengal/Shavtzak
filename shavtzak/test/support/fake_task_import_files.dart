import 'package:shavtzak/core/services/task_import_files.dart';

class FakeTaskImportFiles implements TaskImportFiles {
  /// What each pick returns, in order; an empty queue means "cancelled".
  final List<PickedImportFile?> picks = [];
  final List<(List<int>, String)> saved = [];
  int pickCalls = 0;

  @override
  Future<PickedImportFile?> pickXlsx() async {
    pickCalls++;
    return picks.isEmpty ? null : picks.removeAt(0);
  }

  @override
  void saveXlsx(List<int> bytes, String filename) =>
      saved.add((bytes, filename));
}
