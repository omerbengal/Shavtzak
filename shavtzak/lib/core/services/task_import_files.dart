import 'picked_import_file.dart';
import 'task_import_files_stub.dart'
    if (dart.library.html) 'task_import_files_web.dart' as platform;

export 'picked_import_file.dart';

/// Picking an import file and saving the template. An interface so the
/// screens can be tested without a browser.
abstract class TaskImportFiles {
  /// Opens the file picker; null when the person cancels.
  Future<PickedImportFile?> pickXlsx();

  void saveXlsx(List<int> bytes, String filename);
}

class BrowserTaskImportFiles implements TaskImportFiles {
  const BrowserTaskImportFiles();

  @override
  Future<PickedImportFile?> pickXlsx() => platform.pickXlsxFile();

  @override
  void saveXlsx(List<int> bytes, String filename) =>
      platform.saveXlsxFile(bytes, filename);
}
