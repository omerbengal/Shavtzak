import 'dart:async';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'picked_import_file.dart';

const _xlsxMime =
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';

Future<PickedImportFile?> pickXlsxFile() {
  final completer = Completer<PickedImportFile?>();
  final input = web.HTMLInputElement()
    ..type = 'file'
    ..accept = '.xlsx,$_xlsxMime';

  void finish(PickedImportFile? file) {
    if (!completer.isCompleted) completer.complete(file);
  }

  input.addEventListener(
    'change',
    ((web.Event _) {
      final file = input.files?.item(0);
      if (file == null) {
        finish(null);
        return;
      }
      file.arrayBuffer().toDart.then(
        (buffer) => finish(
          PickedImportFile(name: file.name, bytes: buffer.toDart.asUint8List()),
        ),
        onError: (Object error) {
          if (!completer.isCompleted) completer.completeError(error);
        },
      );
    }).toJS,
  );
  // Fired by current browsers when the picker closes without a file.
  input.addEventListener('cancel', ((web.Event _) => finish(null)).toJS);
  input.click();
  return completer.future;
}

void saveXlsxFile(List<int> bytes, String filename) {
  final blob = web.Blob(
    <JSAny>[Uint8List.fromList(bytes).toJS].toJS,
    web.BlobPropertyBag(type: _xlsxMime),
  );
  final url = web.URL.createObjectURL(blob);
  final anchor = web.HTMLAnchorElement()
    ..href = url
    ..download = filename;
  web.document.body!.appendChild(anchor);
  anchor.click();
  anchor.remove();
  // Revoking at once can cancel the download in some browsers.
  Timer(const Duration(seconds: 2), () => web.URL.revokeObjectURL(url));
}
