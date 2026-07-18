import 'dart:io';

class RuntimeLogger {
  static const int _maxLogBytes = 5 * 1024 * 1024;
  static RuntimeLogger? _instance;

  File? _logFile;
  bool _enabled = false;

  RuntimeLogger._();

  RuntimeLogger.forTesting();

  static RuntimeLogger get instance {
    _instance ??= RuntimeLogger._();
    return _instance!;
  }

  String? get logPath => _logFile?.path;

  Future<void> init({Directory? directory, String? fileName}) async {
    if (_enabled && _logFile != null) {
      return;
    }

    try {
      final logDirectory = directory ?? Directory(_defaultLogDirectory());
      await logDirectory.create(recursive: true);
      final separator = Platform.pathSeparator;
      final logFile = File(
        '${logDirectory.path}$separator${fileName ?? 'luoda_runtime.log'}',
      );
      _rotateIfNeeded(logFile);
      _logFile = logFile;
      _enabled = true;
      info(
        'SYSTEM',
        'runtime logger initialized; os=${Platform.operatingSystem}',
      );
    } catch (_) {
      _enabled = false;
      _logFile = null;
    }
  }

  static String _defaultLogDirectory() {
    if (Platform.isWindows) {
      final appData = Platform.environment['APPDATA'];
      return '${appData ?? Directory.systemTemp.path}\\LUODA\\logs';
    }
    if (Platform.isMacOS) {
      final home = Platform.environment['HOME'] ?? '/tmp';
      return '$home/Library/Logs/LUODA';
    }
    if (Platform.isAndroid || Platform.isIOS) {
      return '${Directory.systemTemp.path}/LUODA/logs';
    }
    final home = Platform.environment['HOME'] ?? '/tmp';
    return '$home/.config/luoda/logs';
  }

  static void _rotateIfNeeded(File file) {
    if (!file.existsSync() || file.lengthSync() < _maxLogBytes) {
      return;
    }

    final backup = File('${file.path}.1');
    if (backup.existsSync()) {
      backup.deleteSync();
    }
    file.renameSync(backup.path);
  }

  void _write(String level, String tag, String message) {
    if (!_enabled || _logFile == null) {
      return;
    }

    final timestamp = DateTime.now().toIso8601String();
    final normalizedMessage = message
        .replaceAll('\r\n', '\n')
        .replaceAll('\r', '\n')
        .replaceAll('\n', '\n    ');
    final line = '[$timestamp] [$level] [$tag] $normalizedMessage\n';
    try {
      _logFile!.writeAsStringSync(
        line,
        mode: FileMode.append,
        flush: true,
      );
    } catch (_) {
      _enabled = false;
    }
  }

  void info(String tag, String message) => _write('INFO', tag, message);

  void warn(String tag, String message) => _write('WARN', tag, message);

  void error(String tag, String message) => _write('ERROR', tag, message);

  void debug(String tag, String message) => _write('DEBUG', tag, message);

  Future<bool> share(Future<bool> Function(String path) shareFile) async {
    final file = _logFile;
    if (!_enabled || file == null || !file.existsSync()) {
      return false;
    }
    try {
      return await shareFile(file.path);
    } catch (error) {
      _write('ERROR', 'SYSTEM', 'runtime log export failed: $error');
      return false;
    }
  }
}
