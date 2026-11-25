/// The browser's own text field (an `<input>`, or for several lines a
/// contenteditable `<div>` with one right-to-left block per line), laid into
/// the page as a platform view. Typing, the caret, the loupe, selection and
/// Cut/Copy/Paste are the browser's: on an iPhone the caret of an empty
/// Hebrew line sits on the right, which Flutter's own field cannot do
/// (25/11/2026). Used only through `AppTextField`; off the web the stub says
/// it is unavailable and `AppTextField` draws Flutter's `TextField`.
library;

export 'native_text_field_stub.dart'
    if (dart.library.js_interop) 'native_text_field_web.dart';
