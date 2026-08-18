import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/mobile/first_run_permission_flow.dart';

void main() {
  test('first-run permissions are serialized before screen capture', () async {
    final events = <String>[];
    final accessibilityReturn = Completer<void>();
    final flow = FirstRunPermissionFlow([
      () async {
        events.add('notification');
        return true;
      },
      () async {
        events.add('audio');
        return true;
      },
      () async {
        events.add('battery');
        return true;
      },
      () async {
        events.add('overlay');
        return true;
      },
      () async {
        events.add('storage');
        return true;
      },
      () async {
        events.add('accessibility');
        await accessibilityReturn.future;
        return true;
      },
      () async {
        events.add('screen-capture');
        return true;
      },
    ]);

    final firstRun = flow.run();
    final duplicateRun = flow.run();
    await Future<void>.delayed(Duration.zero);

    expect(identical(firstRun, duplicateRun), isTrue);
    expect(
      events.join(','),
      'notification,audio,battery,overlay,storage,accessibility',
    );

    accessibilityReturn.complete();
    await firstRun;
    expect(events.last, 'screen-capture');
  });

  test('incomplete authorization is retried on next run', () async {
    var attempts = 0;
    final retryFlow = FirstRunPermissionFlow([
      () async {
        attempts++;
        return attempts > 1;
      },
    ]);
    final firstAttemptResult = await retryFlow.run();
    final secondAttemptResult = await retryFlow.run();
    expect(firstAttemptResult, isFalse);
    expect(secondAttemptResult, isTrue);
  });
}
