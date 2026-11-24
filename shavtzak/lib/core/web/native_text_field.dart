import 'package:flutter/widgets.dart';

import 'native_text_field_stub.dart'
    if (dart.library.js_interop) 'native_text_field_web.dart' as impl;

/// PROTOTYPE (native-field-proto): a real browser <textarea> / <input> laid
/// into the page, so typing, the caret, the loupe, double-tap selection and
/// Cut/Copy/Paste are the browser's own. Null off the web: use a TextField.
Widget? nativeTextField({
  required String initial,
  required ValueChanged<String> onChanged,
  required VoidCallback onSubmit,
  required bool multiline,
  String? hint,
}) =>
    impl.nativeTextField(
      initial: initial,
      onChanged: onChanged,
      onSubmit: onSubmit,
      multiline: multiline,
      hint: hint,
    );
