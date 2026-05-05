import 'dart:typed_data';

import 'assignment_share_image_result.dart';
import 'assignment_share_image_service_stub.dart'
    if (dart.library.html) 'assignment_share_image_service_web.dart'
    as platform;

export 'assignment_share_image_result.dart';

class AssignmentShareImageService {
  const AssignmentShareImageService();

  Future<AssignmentShareImageResult> sharePng({
    required Uint8List pngBytes,
    required String filename,
    required String title,
    required String text,
  }) {
    return platform.shareAssignmentPng(
      pngBytes: pngBytes,
      filename: filename,
      title: title,
      text: text,
    );
  }
}
