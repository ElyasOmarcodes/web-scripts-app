import 'dart:async';
import 'dart:io';

import 'api_client.dart';

/// Starts the local Python backend when it is not already listening.
///
/// During development the app runs from `frontend/`, so the backend is found
/// by walking up until `backend/run_server.py` appears. In a packaged build
/// the `backend` folder sits next to the .exe.
class BackendLauncher {
  BackendLauncher(this.api);

  final ApiClient api;
  Process? _process;
  String? lastError;

  bool get isManaged => _process != null;

  Future<bool> ensureRunning({
    Duration timeout = const Duration(seconds: 40),
  }) async {
    if (await api.isUp()) return true;

    final backendDir = _findBackendDir();
    if (backendDir == null) {
      lastError = 'د backend فولډر ونه موندل شو (run_server.py).';
      return false;
    }
    final python = _findPython(backendDir);
    if (python == null) {
      lastError = 'Python ونه موندل شو. مهرباني وکړئ setup.ps1 وچلوئ.';
      return false;
    }

    try {
      _process = await Process.start(
        python,
        ['run_server.py'],
        workingDirectory: backendDir.path,
        // Keep the console attached on Windows so errors are visible in logs.
        mode: ProcessStartMode.normal,
      );
      _process!.stdout.drain<void>();
      _process!.stderr.drain<void>();
    } catch (error) {
      lastError = 'د سرور پیلولو تېروتنه: $error';
      return false;
    }

    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (await api.isUp()) return true;
      await Future<void>.delayed(const Duration(milliseconds: 500));
    }
    lastError = 'سرور په ټاکلي وخت کې ونه چلېد.';
    return false;
  }

  void dispose() {
    _process?.kill();
    _process = null;
  }

  Directory? _findBackendDir() {
    final roots = <Directory>[
      Directory.current,
      File(Platform.resolvedExecutable).parent,
    ];
    for (final root in roots) {
      var dir = root;
      for (var depth = 0; depth < 6; depth++) {
        final candidate = File('${dir.path}${Platform.pathSeparator}backend'
            '${Platform.pathSeparator}run_server.py');
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
