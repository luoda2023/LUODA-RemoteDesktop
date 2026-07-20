typedef FirstRunPermissionStep = Future<bool> Function();

class FirstRunPermissionFlow {
  FirstRunPermissionFlow(this._steps);

  final List<FirstRunPermissionStep> _steps;
  Future<bool>? _running;

  Future<bool> run() {
    return _running ??= _runSteps();
  }

  Future<bool> _runSteps() async {
    var allGranted = true;
    try {
      for (final step in _steps) {
        final granted = await step();
        allGranted = granted && allGranted;
      }
      return allGranted;
    } finally {
      _running = null;
    }
  }
}
