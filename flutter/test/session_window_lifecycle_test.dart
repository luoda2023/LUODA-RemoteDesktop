import 'package:luoda_flutter/desktop/session_window_lifecycle.dart';

Future<void> main() async {
  await _testEmptyWindowIsHiddenBeforeUnregister();
  await _testSessionAddedDuringHideReactivatesWindow();
  await _testSessionAddedDuringUnregisterReactivatesWindow();
  await _testLifecycleErrorsDoNotEscape();
  print('session_window_lifecycle_test: all tests passed');
}

Future<void> _testEmptyWindowIsHiddenBeforeUnregister() async {
  final calls = <String>[];

  await deactivateEmptySessionWindow(
    hasSessions: () => false,
    hide: () async => calls.add('hide'),
    unregister: () async => calls.add('unregister'),
    reactivate: () async => calls.add('reactivate'),
  );

  _expectEqual(calls, ['hide', 'unregister']);
}

Future<void> _testSessionAddedDuringHideReactivatesWindow() async {
  final calls = <String>[];
  var hasSessions = false;

  await deactivateEmptySessionWindow(
    hasSessions: () => hasSessions,
    hide: () async {
      calls.add('hide');
      hasSessions = true;
    },
    unregister: () async => calls.add('unregister'),
    reactivate: () async => calls.add('reactivate'),
  );

  _expectEqual(calls, ['hide', 'reactivate']);
}

Future<void> _testLifecycleErrorsDoNotEscape() async {
  final errors = <Object>[];

  await deactivateEmptySessionWindow(
    hasSessions: () => false,
    hide: () async => throw StateError('window is gone'),
    unregister: () async => throw StateError('main window is gone'),
    reactivate: () async {},
    onError: (error, _) => errors.add(error),
  );

  if (errors.length != 2) {
    throw StateError('Expected 2 captured errors, got ${errors.length}');
  }
}

Future<void> _testSessionAddedDuringUnregisterReactivatesWindow() async {
  final calls = <String>[];
  var hasSessions = false;

  await deactivateEmptySessionWindow(
    hasSessions: () => hasSessions,
    hide: () async => calls.add('hide'),
    unregister: () async {
      calls.add('unregister');
      hasSessions = true;
    },
    reactivate: () async => calls.add('reactivate'),
  );

  _expectEqual(calls, ['hide', 'unregister', 'reactivate']);
}

void _expectEqual(List<String> actual, List<String> expected) {
  if (actual.length != expected.length) {
    throw StateError('Expected $expected, got $actual');
  }
  for (var i = 0; i < expected.length; i++) {
    if (actual[i] != expected[i]) {
      throw StateError('Expected $expected, got $actual');
    }
  }
}
