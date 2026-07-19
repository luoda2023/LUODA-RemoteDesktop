typedef WindowLifecycleErrorHandler = void Function(
  Object error,
  StackTrace stackTrace,
);

Future<void> deactivateEmptySessionWindow({
  required bool Function() hasSessions,
  required Future<void> Function() hide,
  required Future<void> Function() unregister,
  required Future<void> Function() reactivate,
  WindowLifecycleErrorHandler? onError,
}) async {
  if (hasSessions()) return;

  Future<void> runSafely(Future<void> Function() action) async {
    try {
      await action();
    } catch (error, stackTrace) {
      try {
        onError?.call(error, stackTrace);
      } catch (_) {
        // Window cleanup must not surface a second asynchronous error.
      }
    }
  }

  await runSafely(hide);
  if (hasSessions()) {
    await runSafely(reactivate);
    return;
  }

  await runSafely(unregister);
  if (hasSessions()) {
    await runSafely(reactivate);
  }
}
