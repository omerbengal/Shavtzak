import 'dart:async';

class CrudActionResult {
  final bool isSuccess;
  final String? message;

  const CrudActionResult._({
    required this.isSuccess,
    this.message,
  });

  const CrudActionResult.success([String? message])
      : this._(isSuccess: true, message: message);

  const CrudActionResult.failure(String message)
      : this._(isSuccess: false, message: message);

  bool get isFailure => !isSuccess;
}

typedef CrudActionCompleter = Completer<CrudActionResult>;

void completeCrudAction(
  CrudActionCompleter? completer,
  CrudActionResult result,
) {
  if (completer == null || completer.isCompleted) {
    return;
  }

  completer.complete(result);
}
