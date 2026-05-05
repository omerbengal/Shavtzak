import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

import 'assignment_share_image_result.dart';

const _pngMimeType = 'image/png';

Future<AssignmentShareImageResult> shareAssignmentPng({
  required Uint8List pngBytes,
  required String filename,
  required String title,
  required String text,
}) async {
  final blob = _createPngBlob(pngBytes);
  final file = web.File(
    <JSAny>[blob].toJS,
    filename,
    web.FilePropertyBag(type: _pngMimeType),
  );

  if (await _tryNativeShare(file: file, title: title, text: text)) {
    return AssignmentShareImageResult.shared;
  }

  return AssignmentShareImageResult.needsManualScreenshot;
}

Future<AssignmentShareImageResult> copyAssignmentPng({
  required Uint8List pngBytes,
}) async {
  final blob = _createPngBlob(pngBytes);

  if (await _tryClipboardWrite(blob)) {
    return AssignmentShareImageResult.copiedImage;
  }

  return AssignmentShareImageResult.needsManualScreenshot;
}

web.Blob _createPngBlob(Uint8List pngBytes) {
  return web.Blob(
    <JSAny>[pngBytes.toJS].toJS,
    web.BlobPropertyBag(type: _pngMimeType),
  );
}

Future<bool> _tryNativeShare({
  required web.File file,
  required String title,
  required String text,
}) async {
  final navigator = web.window.navigator;
  if (!navigator.has('share')) {
    return false;
  }

  final shareData = web.ShareData(
    files: <web.File>[file].toJS,
    title: title,
    text: text,
  );

  try {
    if (navigator.has('canShare') && !navigator.canShare(shareData)) {
      return false;
    }

    await navigator.share(shareData).toDart;
    return true;
  } catch (_) {
    return false;
  }
}

Future<bool> _tryClipboardWrite(web.Blob blob) async {
  final navigator = web.window.navigator;
  if (!navigator.has('clipboard')) {
    return false;
  }

  try {
    final clipboard = navigator.clipboard;
    if (!clipboard.has('write')) {
      return false;
    }

    final itemData = JSObject()..setProperty(_pngMimeType.toJS, blob);
    final item = web.ClipboardItem(itemData);

    await clipboard.write(<web.ClipboardItem>[item].toJS).toDart;
    return true;
  } catch (_) {
    return false;
  }
}
