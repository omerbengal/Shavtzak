import 'dart:typed_data';

import 'assignment_share_image_result.dart';

Future<AssignmentShareImageResult> shareAssignmentPng({
  required Uint8List pngBytes,
  required String filename,
  required String title,
  required String text,
}) async {
  return AssignmentShareImageResult.needsManualScreenshot;
}

Future<AssignmentShareImageResult> copyAssignmentPng({
  required Uint8List pngBytes,
}) async {
  return AssignmentShareImageResult.needsManualScreenshot;
}
