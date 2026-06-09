// AUTO-INJECTED RUNTIME LOGGER
import 'dart:io';
import 'dart:convert';
class RuntimeLogger {
  static RuntimeLogger? _instance;
  File? _logFile;
  IOSink? _sink;
  bool _enabled = true;
  RuntimeLogger._();
  static RuntimeLogger get instance { _instance ??= RuntimeLogger._(); return _instance!; }
  Future<void> init() async {
    try {
      String basePath;
      if (Platform.isWindows) {
        basePath = (Platform.environment['APPDATA'] ?? 'C:\\LUODA') + '\\LUODA\\logs';
      } else if (Platform.isMacOS) {
        basePath = (Platform.environment['HOME'] ?? '/tmp') + '/Library/Logs/LUODA';
      } else {
        basePath = (Platform.environment['HOME'] ?? '/tmp') + '/.config/luoda/logs';
      }
      final dir = Directory(basePath);
      await dir.create(recursive: true);
      _logFile = File(dir.path + '/luoda_runtime.log');
      _sink = _logFile!.openWrite(mode: FileMode.append);
      info('SYSTEM', 'Runtime logger initialized on ' + Platform.operatingSystem);
    } catch (e) { _enabled = false; }
  }
  void _write(String level, String tag, String message) {
    if (!_enabled) return;
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    _sink?.write('[' + ts.toString() + '] [' + level + '] [' + tag + '] ' + message + "\n");
  }
  void info(String tag, String message) => _write('INFO', tag, message);
  void warn(String tag, String message) => _write('WARN', tag, message);
  void error(String tag, String message) => _write('ERROR', tag, message);
  void debug(String tag, String message) => _write('DEBUG', tag, message);
}
