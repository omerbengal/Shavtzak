import 'dart:typed_data';

/// A file the person picked to import.
class PickedImportFile {
  const PickedImportFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}
