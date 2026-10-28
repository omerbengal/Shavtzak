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
  // Safari only reports the pick for an input that is in the page, and a
  // detached one may be collected while the picker is still open.
  input.style.display = 'none';
  web.document.body!.appendChild(input);

  void finish(PickedImportFile? file) {
    input.remove();
    if (!completer.isCompleted) completer.complete(file);
  }

  void fail(Object error) {
    input.remove();
    if (!completer.isCompleted) completer.completeError(error);
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
        onError: fail,
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
