import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/backend_launcher.dart';
import '../models/script.dart';

enum SessionState { idle, recording, playing }

class AppState extends ChangeNotifier {
  AppState({ApiClient? api}) : api = api ?? ApiClient() {
    launcher = BackendLauncher(this.api);
  }

  final ApiClient api;
  late final BackendLauncher launcher;

  bool booting = true;
  bool connected = false;
  String? connectionError;

  List<WebScript> scripts = const [];
  WebScript? selected;
  bool loadingScript = false;

  SessionState session = SessionState.idle;
  String? activeScriptId;
  int recordedSteps = 0;
  int? currentStep;
  int? totalSteps;

  final List<AppEvent> log = [];
  String? _error;

  StreamSubscription<AppEvent>? _events;
  Timer? _reconnect;

  // --------------------------------------------------------------- lifecycle

  Future<void> boot() async {
    booting = true;
    notifyListeners();

    connected = await launcher.ensureRunning();
    connectionError = connected ? null : launcher.lastError;
    booting = false;
    notifyListeners();

    if (connected) {
      await refresh();
      await _loadHistory();
      _listen();
    }
  }

  @override
  void dispose() {
    _events?.cancel();
    _reconnect?.cancel();
    launcher.dispose();
    api.close();
    super.dispose();
  }

  Future<void> retryConnection() => boot();

  // ------------------------------------------------------------------ events

  void _listen() {
    _events?.cancel();
    try {
      _events = api.events().listen(
            _onEvent,
            onError: (_) => _scheduleReconnect(),
            onDone: _scheduleReconnect,
            cancelOnError: true,
          );
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _scheduleReconnect() {
    _reconnect?.cancel();
    _reconnect = Timer(const Duration(seconds: 3), () async {
      if (await api.isUp()) {
        _listen();
      } else {
        _scheduleReconnect();
      }
    });
  }

  Future<void> _loadHistory() async {
    try {
      log
        ..clear()
        ..addAll(await api.eventHistory(limit: 100));
      notifyListeners();
    } catch (_) {
      // history is a nicety, not a requirement
    }
  }

  void _onEvent(AppEvent event) {
    switch (event.type) {
      case 'recording_started':
        session = SessionState.recording;
        recordedSteps = 0;
        break;
      case 'step_recorded':
        recordedSteps = event.index ?? recordedSteps + 1;
        break;
      case 'recording_saved':
      case 'recording_failed':
        session = SessionState.idle;
        unawaited(refresh());
        break;
      case 'run_started':
        session = SessionState.playing;
        currentStep = 0;
        totalSteps = event.total;
        break;
      case 'step_start':
        currentStep = (event.index ?? 0) + 1;
        totalSteps = event.total ?? totalSteps;
        break;
      case 'run_finished':
        session = SessionState.idle;
        currentStep = null;
        totalSteps = null;
        activeScriptId = null;
        unawaited(refresh());
        break;
    }

    if (event.message.isNotEmpty) {
      log.add(event);
      if (log.length > 500) log.removeRange(0, log.length - 500);
    }
    notifyListeners();
  }

  void clearLog() {
    log.clear();
    notifyListeners();
  }

  String? consumeError() {
    final error = _error;
    _error = null;
    return error;
  }

  bool get busy => session != SessionState.idle;

  // ----------------------------------------------------------------- scripts

  Future<void> refresh() async {
    try {
      scripts = await api.listScripts();
      final current = selected;
      if (current != null) {
        final fresh = await api.getScript(current.id);
        selected = fresh;
      }
    } on ApiException catch (error) {
      _error = error.message;
    } catch (error) {
      _error = '$error';
    }
    notifyListeners();
  }

  Future<void> openScript(String id) async {
    loadingScript = true;
    notifyListeners();
    try {
      selected = await api.getScript(id);
    } on ApiException catch (error) {
      _error = error.message;
    } finally {
      loadingScript = false;
      notifyListeners();
    }
  }

  void closeScript() {
    selected = null;
    notifyListeners();
  }

  Future<void> deleteScript(String id) async {
    try {
      await api.deleteScript(id);
      if (selected?.id == id) selected = null;
      await refresh();
    } on ApiException catch (error) {
      _error = error.message;
      notifyListeners();
    }
  }

  Future<void> renameScript(String id, String name) async {
    try {
      selected = await api.updateScript(id, name: name);
      await refresh();
    } on ApiException catch (error) {
      _error = error.message;
      notifyListeners();
    }
  }

  Future<void> saveSteps(List<StepModel> steps) async {
    final script = selected;
    if (script == null) return;
    try {
      selected = await api.updateScript(script.id, steps: steps);
      await refresh();
    } on ApiException catch (error) {
      _error = error.message;
      notifyListeners();
    }
  }

  Future<void> toggleStep(StepModel step) async {
    final script = selected;
    if (script == null) return;
    step.enabled = !step.enabled;
    notifyListeners();
    await saveSteps(script.steps);
  }

  Future<void> deleteStep(StepModel step) async {
    final script = selected;
    if (script == null) return;
    final steps = List<StepModel>.from(script.steps)
      ..removeWhere((s) => s.id == step.id);
    await saveSteps(steps);
  }

  Future<void> reorderSteps(int oldIndex, int newIndex) async {
    final script = selected;
    if (script == null) return;
    final steps = List<StepModel>.from(script.steps);
    if (newIndex > oldIndex) newIndex -= 1;
    steps.insert(newIndex, steps.removeAt(oldIndex));
    await saveSteps(steps);
  }

  Future<void> editStep(
    StepModel step, {
    String? value,
    String? url,
    int? delayMs,
  }) async {
    final script = selected;
    if (script == null) return;
    if (value != null) step.value = value;
    if (url != null) step.url = url;
    if (delayMs != null) step.delayMs = delayMs;
    await saveSteps(script.steps);
  }

  // --------------------------------------------------------------- recording

  Future<void> startRecording({
    required String name,
    required String url,
    bool captureScroll = false,
  }) async {
    try {
      await api.startRecording(
        name: name,
        url: url,
        captureScroll: captureScroll,
      );
      session = SessionState.recording;
      recordedSteps = 0;
    } on ApiException catch (error) {
      _error = error.message;
    }
    notifyListeners();
  }

  Future<void> stopRecording() async {
    try {
      final result = await api.stopRecording();
      session = SessionState.idle;
      final script = result['script'];
      if (script is Map<String, dynamic>) {
        selected = WebScript.fromJson(script);
      }
      await refresh();
    } on ApiException catch (error) {
      _error = error.message;
      notifyListeners();
    }
  }

  // ------------------------------------------------------------------ replay

  Future<void> runScript(
    String id, {
    Map<String, String> variables = const {},
    double speed = 1.0,
    bool headless = false,
    bool keepOpen = false,
  }) async {
    try {
      activeScriptId = id;
      await api.run(
        id,
        variables: variables,
        speed: speed,
        headless: headless,
        keepOpen: keepOpen,
      );
      session = SessionState.playing;
    } on ApiException catch (error) {
      activeScriptId = null;
      _error = error.message;
    }
    notifyListeners();
  }

  Future<void> stopSession() async {
    try {
      await api.stopSession();
    } on ApiException catch (error) {
      _error = error.message;
    }
    session = SessionState.idle;
    notifyListeners();
  }
}
