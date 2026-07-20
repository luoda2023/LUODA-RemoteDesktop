import 'dart:async';

import 'package:luoda_flutter/mobile/first_run_permission_flow.dart';

Future<void> main() async {
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

  if (!identical(firstRun, duplicateRun) ||
      events.join(',') !=
          'notification,audio,battery,overlay,storage,accessibility') {
    throw StateError('First-run permissions were not serialized');
  }

  accessibilityReturn.complete();
  await firstRun;
  if (events.last != 'screen-capture') {
    throw StateError('Screen capture did not start after settings returned');
  }

  var attempts = 0;
  final retryFlow = FirstRunPermissionFlow([
    () async {
      attempts++;
      return attempts > 1;
    },
  ]);
  final firstAttemptResult = await retryFlow.run();
  final secondAttemptResult = await retryFlow.run();
  if (firstAttemptResult || !secondAttemptResult) {
    throw StateError('Incomplete authorization was not retried');
  }
}
