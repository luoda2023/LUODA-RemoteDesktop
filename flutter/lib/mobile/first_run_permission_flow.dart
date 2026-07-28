typedef FirstRunPermissionStep = Future<bool> Function();

/// Callback for step progress: (stepName, stepIndex, totalSteps, granted)
typedef FirstRunStepCallback = void Function(
    String stepName, int stepIndex, int totalSteps, bool granted);

class FirstRunPermissionFlow {
  FirstRunPermissionFlow(
    this._steps, {
    List<String>? stepNames,
    this.onStepProgress,
  }) : _stepNames = stepNames ?? List.filled(_steps.length, '');

  final List<FirstRunPermissionStep> _steps;
  final List<String> _stepNames;
  final FirstRunStepCallback? onStepProgress;
  Future<bool>? _running;

  Future<bool> run() {
    return _running ??= _runSteps();
  }

  Future<bool> _runSteps() async {
    var allGranted = true;
    try {
      for (var i = 0; i < _steps.length; i++) {
        final stepName = i < _stepNames.length ? _stepNames[i] : 'step_$i';
        onStepProgress?.call(stepName, i, _steps.length, false);
        final granted = await _steps[i]();
        allGranted = granted && allGranted;
        onStepProgress?.call(stepName, i, _steps.length, granted);
      }
      return allGranted;
    } finally {
      _running = null;
    }
  }
}
