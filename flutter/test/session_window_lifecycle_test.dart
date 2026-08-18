import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/desktop/session_window_lifecycle.dart';

void main() {
  test('empty window is hidden before unregister', () async {
    final calls = <String>[];

    await deactivateEmptySessionWindow(
      hasSessions: () => false,
      hide: () async => calls.add('hide'),
      unregister: () async => calls.add('unregister'),
      reactivate: () async => calls.add('reactivate'),
    );

    expect(calls, ['hide', 'unregister']);
  });

  test('session added during hide reactivates window', () async {
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

    expect(calls, ['hide', 'reactivate']);
  });

  test('session added during unregister reactivates window', () async {
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

    expect(calls, ['hide', 'unregister', 'reactivate']);
  });

  test('lifecycle errors do not escape', () async {
    final errors = <Object>[];

    await deactivateEmptySessionWindow(
      hasSessions: () => false,
      hide: () async => throw StateError('window is gone'),
      unregister: () async => throw StateError('main window is gone'),
      reactivate: () async {},
      onError: (error, _) => errors.add(error),
    );

    expect(errors.length, 2);
  });
}
