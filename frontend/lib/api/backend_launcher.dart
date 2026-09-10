import 'dart:async';
import 'dart:io';

import 'api_client.dart';

/// Starts the local backend when it is not already listening.
///
/// Two shapes are supported:
///   * packaged  — `webscripts-backend.exe` sits next to the app executable
///     (or in a `backend` folder beside it); no Python needed.
///   * developer — the repository checkout, where `backend/run_server.py` is
///     run with the venv interpreter.
class BackendLauncher {
  BackendLauncher(this.api);

  final ApiClient api;
  Process? _process;
  String? lastError;

  /// Set once the backend was started by this app (so it can be stopped again).
  bool get isManaged => _process != null;

  Future<bool> ensureRunning({
    Duration timeout = const Duration(seconds: 45),
  }) async {
    if (await api.isUp()) return true;

    final started = await _startPackaged() || await _startFromSource();
    if (!started) return false;

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await api.isUp()) return true;
      if (_process != null) {
        // Died on startup: report instead of waiting out the timeout.
        final exited = await _process!.exitCode
            .timeout(const Duration(milliseconds: 1), onTimeout: () => -999);
        if (exited != -999) {
          lastError = 'د سرور پروسه ودرېده (کوډ $exited).';
          return false;
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 400));
    }
    lastError = 'سرور په ټاکلي وخت کې ونه چلېد.';
    return false;
  }

  /// Stop the backend the polite way, then make sure it is really gone.
  ///
  /// A windowed build has no console and no window: one left running would be
  /// invisible, would hold its own .exe open (so the folder cannot be deleted)
  /// and would keep the port for the next start.
  Future<void> shutdown({
    Duration grace = const Duration(seconds: 3),
  }) async {
    // Ask it to close the browser and exit — this also covers a backend that
    // was already running when the app started.
    await api.shutdown();

    final process = _process;
    _process = null;
    if (process == null) return;
    try {
      await process.exitCode.timeout(grace);
      return;
    } on TimeoutException {
      // It did not go: take the whole tree down, children included.
      if (Platform.isWindows) {
        await Process.run('taskkill', ['/PID', '${process.pid}', '/T', '/F']);
      } else {
        process.kill(ProcessSignal.sigkill);
      }
    } catch (_) {
      // Already gone.
    }
  }

  void dispose() {
    _process?.kill();
    _process = null;
  }

  // ------------------------------------------------------------- strategies

  Future<bool> _startPackaged() async {
    final executable = _findPackagedBackend();
    if (executable == null) return false;
    return _spawn(executable.path, _lifetimeArgs, executable.parent.path);
  }

  /// The backend exits by itself as soon as this app's process is gone, so a
  /// crash or a force-quit can never leave it running with no window.
  static List<String> get _lifetimeArgs => ['--parent-pid', '$pid'];

  Future<bool> _startFromSource() async {
    final backendDir = _findBackendDir();
    if (backendDir == null) {
      lastError ??= 'نه بسته شوی backend او نه یې سرچینه ونه موندل شوه.';
      return false;
    }
    final python = _findPython(backendDir);
    if (python == null) {
      lastError = 'Python ونه موندل شو. مهرباني وکړئ scripts\\setup.ps1 وچلوئ.';
      return false;
    }
    return _spawn(python, ['run_server.py', ..._lifetimeArgs], backendDir.path);
  }

  Future<bool> _spawn(
      String executable, List<String> args, String workingDirectory) async {
    try {
      _process = await Process.start(
        executable,
        args,
        workingDirectory: workingDirectory,
        mode: ProcessStartMode.normal,
      );
      // Drain the pipes so a chatty backend can never block on a full buffer.
      _process!.stdout.drain<void>();
      _process!.stderr.drain<void>();
      return true;
    } catch (error) {
      lastError = 'د سرور پیلولو تېروتنه: $error';
      return false;
    }
  }

  // ---------------------------------------------------------------- lookups

  static const _backendExeNames = [
    'webscripts-backend.exe',
    'webscripts-backend'
  ];

  File? _findPackagedBackend() {
    final sep = Platform.pathSeparator;
    final appDir = File(Platform.resolvedExecutable).parent;
    for (final directory in [
      appDir,
      Directory('${appDir.path}${sep}backend')
    ]) {
      for (final name in _backendExeNames) {
        final candidate = File('${directory.path}$sep$name');
        if (candidate.existsSync()) return candidate;
      }
    }
    return null;
  }

  Directory? _findBackendDir() {
    final sep = Platform.pathSeparator;
    final roots = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];
    for (final root in roots) {
      var dir = root;
      for (var depth = 0; depth < 6; depth++) {
        final candidate = File('${dir.path}${sep}backend${sep}run_server.py');
        if (candidate.existsSync()) return candidate.parent;
        final parent = dir.parent;
        if (parent.path == dir.path) break;
        dir = parent;
      }
    }
    return null;
  }

  String? _findPython(Directory backendDir) {
    final fromEnv = Platform.environment['WEBSCRIPTS_PYTHON'];
    if (fromEnv != null && File(fromEnv).existsSync()) return fromEnv;

    final sep = Platform.pathSeparator;
    final candidates = Platform.isWindows
        ? [
            '${backendDir.path}$sep.venv${sep}Scripts${sep}python.exe',
            'py',
            'python',
          ]
        : [
            '${backendDir.path}$sep.venv${sep}bin${sep}python',
            'python3',
            'python',
          ];

    for (final candidate in candidates) {
      if (candidate.contains(sep)) {
        if (File(candidate).existsSync()) return candidate;
      } else if (_onPath(candidate)) {
        return candidate;
      }
    }
    return null;
  }

  bool _onPath(String executable) {
    try {
      final result = Process.runSync(
        Platform.isWindows ? 'where' : 'which',
        [executable],
      );
      return result.exitCode == 0;
    } catch (_) {
      return false;
    }
  }
}
