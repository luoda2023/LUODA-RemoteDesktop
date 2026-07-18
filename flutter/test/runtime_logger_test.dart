import 'dart:io';

import 'package:luoda_flutter/runtime_logger.dart';

Future<void> main() async {
  const fileName = 'runtime_logger_test.log';
  final directory =
      Directory('${Directory.current.path}${Platform.pathSeparator}test');
  final file = File('${directory.path}${Platform.pathSeparator}$fileName');
  if (file.existsSync()) {
    file.deleteSync();
  }

  final logger = RuntimeLogger.forTesting();
  await logger.init(directory: directory, fileName: fileName);
  logger.info('TEST', 'runtime logging works');
  logger.error('TEST', 'line one\nline two');

  String? sharedPath;
  final shared = await logger.share((path) async {
    sharedPath = path;
    return true;
  });

  final contents = file.readAsStringSync();
  if (logger.logPath != file.path ||
      !shared ||
      sharedPath != file.path ||
      !contents.contains('[INFO] [TEST] runtime logging works') ||
      !contents.contains('[ERROR] [TEST] line one\n    line two')) {
    throw StateError('runtime logger did not persist the expected entries');
  }

  final uninitializedLogger = RuntimeLogger.forTesting();
  if (await uninitializedLogger.share((_) async => true)) {
    throw StateError('uninitialized runtime logger must not export a file');
  }

  file.deleteSync();
}
