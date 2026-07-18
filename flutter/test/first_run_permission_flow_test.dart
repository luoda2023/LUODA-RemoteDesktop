import 'dart:async';

import 'package:luoda_flutter/mobile/first_run_permission_flow.dart';

Future<void> main() async {
  final events = <String>[];
  final accessibilityReturn = Completer<void>();
  final flow = FirstRunPermissionFlow([
    () async => events.add('notification'),
    () async => events.add('audio'),
    () async => events.add('battery'),
    () async => events.add('overlay'),
    () async => events.add('storage'),
    () async {
      events.add('accessibility');
      await accessibilityReturn.future;
    },
    () async => events.add('screen-capture'),
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
}
