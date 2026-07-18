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

  final contents = file.readAsStringSync();
  if (logger.logPath != file.path ||
      !contents.contains('[INFO] [TEST] runtime logging works') ||
      !contents.contains('[ERROR] [TEST] line one\n    line two')) {
    throw StateError('runtime logger did not persist the expected entries');
  }

  file.deleteSync();
}
