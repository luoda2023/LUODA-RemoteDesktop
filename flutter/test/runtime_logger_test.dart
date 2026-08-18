import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:luoda_flutter/runtime_logger.dart';

void main() {
  test('runtime logger persists entries and supports sharing', () async {
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
    expect(logger.logPath, file.path);
    expect(shared, isTrue);
    expect(sharedPath, file.path);
    expect(contents.contains('[INFO] [TEST] runtime logging works'), isTrue);
    expect(contents.contains('[ERROR] [TEST] line one\n line two'), isTrue);

    file.deleteSync();
  });

  test('uninitialized runtime logger does not export a file', () async {
    final uninitializedLogger = RuntimeLogger.forTesting();
    final result = await uninitializedLogger.share((_) async => true);
    expect(result, isFalse);
  });
}
