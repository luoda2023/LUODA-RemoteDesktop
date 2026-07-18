typedef FirstRunPermissionStep = Future<void> Function();

class FirstRunPermissionFlow {
  FirstRunPermissionFlow(this._steps);

  final List<FirstRunPermissionStep> _steps;
  Future<void>? _running;

  Future<void> run() {
    return _running ??= _runSteps();
  }

  Future<void> _runSteps() async {
    try {
      for (final step in _steps) {
        await step();
      }
    } finally {
      _running = null;
    }
  }
}
