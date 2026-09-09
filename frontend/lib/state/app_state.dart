import 'dart:async';

import 'package:flutter/foundation.dart';

import '../api/api_client.dart';
import '../api/backend_launcher.dart';
import '../models/account.dart';
import '../models/script.dart';
import '../models/settings.dart';

enum SessionState { idle, recording, playing, loggingIn }

enum AppPage {
  dashboard,
  scripts,
  accounts,
  recorder,
  activity,
  settings,
  help
}

class AppState extends ChangeNotifier {
  AppState({ApiClient? api}) : api = api ?? ApiClient() {
    launcher = BackendLauncher(this.api);
  }

  final ApiClient api;
  late final BackendLauncher launcher;

  // -- connection
  bool booting = true;
  bool connected = false;
  String? connectionError;

  // -- navigation
  AppPage page = AppPage.dashboard;
  WebScript? selected; // non-null while a script's detail page is open

  // -- data
  List<WebScript> scripts = const [];
  AppSettings settings = const AppSettings();
  BrowserList browsers = const BrowserList();
  AccountBook accounts = const AccountBook();
  bool loadingScript = false;
  bool refreshingBrowsers = false;

  // -- live session
  SessionState session = SessionState.idle;
  String? activeScriptId;
  int recordedSteps = 0;
  String? pendingAccountId;
  String? pendingCategoryId;
  int? currentStep;
  int? totalSteps;
  DateTime? sessionStartedAt;
  final List<StepModel> liveSteps = [];

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
      await Future.wait([
        refresh(),
        loadSettings(),
        refreshBrowsers(),
        refreshAccounts(),
      ]);
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

  // -------------------------------------------------------------- navigation

  void navigate(AppPage target) {
    page = target;
    selected = null;
    notifyListeners();
  }

  Future<void> openScript(String id) async {
    loadingScript = true;
    page = AppPage.scripts;
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
        ..addAll(await api.eventHistory(limit: 120));
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
        liveSteps.clear();
        sessionStartedAt = DateTime.now();
        page = AppPage.recorder;
        break;
      case 'step_recorded':
        recordedSteps = event.index ?? recordedSteps + 1;
        final raw = event.raw['step'];
        if (raw is Map<String, dynamic>) {
          liveSteps.add(StepModel.fromJson(raw));
          if (liveSteps.length > 200) liveSteps.removeAt(0);
        }
        break;
      case 'recording_saved':
      case 'recording_failed':
        session = SessionState.idle;
        sessionStartedAt = null;
        unawaited(refresh());
        break;
      case 'login_started':
        session = SessionState.loggingIn;
        pendingAccountId = event.raw['account_id'] as String?;
        pendingCategoryId = event.raw['category'] as String?;
        sessionStartedAt = DateTime.now();
        page = AppPage.accounts;
        break;
      case 'login_finished':
        session = SessionState.idle;
        pendingAccountId = null;
        pendingCategoryId = null;
        sessionStartedAt = null;
        unawaited(refreshAccounts());
        break;
      case 'run_started':
        session = SessionState.playing;
        currentStep = 0;
        totalSteps = event.total;
        sessionStartedAt = DateTime.now();
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
        sessionStartedAt = null;
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

  void reportError(String message) {
    _error = message;
    notifyListeners();
  }

  bool get busy => session != SessionState.idle;

  // ---------------------------------------------------------------- insights

  int get totalStepCount => scripts.fold(0, (sum, s) => sum + s.stepCount);
  int get successCount => scripts.where((s) => s.lastRunOk == true).length;
  int get failedCount => scripts.where((s) => s.lastRunOk == false).length;
  int get neverRunCount => scripts.where((s) => s.lastRunOk == null).length;

  /// Percentage of scripts whose last run succeeded (of those ever run).
  int get successRate {
    final ran = scripts.where((s) => s.lastRunOk != null).length;
    if (ran == 0) return 0;
    return ((successCount / ran) * 100).round();
  }

  /// Rough "time saved": every replayed step stands for ~8 seconds of manual
  /// clicking. Returned in minutes, which stays readable while it is small.
  double get minutesSaved {
    final runs = scripts.where((s) => s.lastRunAt != null);
    final steps = runs.fold<int>(0, (sum, s) => sum + s.stepCount);
    return steps * 8 / 60;
  }

  List<WebScript> get recentScripts {
    final sorted = List<WebScript>.from(scripts)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sorted.take(4).toList();
  }

  // ----------------------------------------------------------------- scripts

  Future<void> refresh() async {
    try {
      scripts = await api.listScripts();
      final current = selected;
      if (current != null) {
        selected = await api.getScript(current.id);
      }
    } on ApiException catch (error) {
      _error = error.message;
    } catch (error) {
      _error = '$error';
    }
    notifyListeners();
  }

  Future<WebScript?> createScript(String name, String startUrl) async {
    try {
      final script = await api.createScript(name: name, startUrl: startUrl);
      await refresh();
      return script;
    } on ApiException catch (error) {
      _error = error.message;
      notifyListeners();
      return null;
    }
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
      final updated = await api.updateScript(id, name: name);
      if (selected?.id == id) selected = updated;
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

  /// "This one may be missing next time" — a cookie dialog, a one-off tip.
  Future<void> toggleOptional(StepModel step) async {
    final script = selected;
    if (script == null) return;
    step.optional = !step.optional;
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

  // ---------------------------------------------------------------- settings

  Future<void> loadSettings() async {
    try {
      settings = await api.settings();
    } on ApiException catch (error) {
      _error = error.message;
    }
    notifyListeners();
  }

  Future<void> updateSettings(Map<String, dynamic> changes) async {
    try {
      settings = await api.saveSettings(changes);
      if (changes.containsKey('browser')) await refreshBrowsers();
    } on ApiException catch (error) {
      _error = error.message;
    }
    notifyListeners();
  }

  Future<void> resetSettings() async {
    try {
      settings = await api.resetSettings();
      await refreshBrowsers();
    } on ApiException catch (error) {
      _error = error.message;
    }
    notifyListeners();
  }

  Future<void> refreshBrowsers({bool rescan = false}) async {
    refreshingBrowsers = rescan;
    if (rescan) notifyListeners();
    try {
      browsers = await api.browsers(refresh: rescan);
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      // the backend may still be starting
    }
    refreshingBrowsers = false;
    notifyListeners();
  }

  /// Human name of the browser that will actually be launched.
  String get activeBrowserName {
    final active = browsers.activeBrowser;
    if (active != null) return active.name;
    if (browsers.installed.isEmpty && browsers.browsers.isNotEmpty) {
      return 'براوزر ونه موندل شو';
    }
    return '—';
  }

  // ---------------------------------------------------------------- accounts

  Future<void> refreshAccounts() async {
    try {
      accounts = await api.accounts();
    } on ApiException catch (error) {
      _error = error.message;
    } catch (_) {
      // the backend may still be starting
    }
    notifyListeners();
  }

  /// Opens the service's login page in a small browser window.
  Future<bool> startLogin(String categoryId, {String label = ''}) async {
    try {
      final account = await api.startLogin(category: categoryId, label: label);
      session = SessionState.loggingIn;
      pendingAccountId = account.id;
      pendingCategoryId = categoryId;
      sessionStartedAt = DateTime.now();
      page = AppPage.accounts;
      notifyListeners();
      return true;
    } on ApiException catch (error) {
      _error = error.message;
      notifyListeners();
      return false;
    }
  }

  /// Tells the backend the sign-in is done, so it can store the session.
  Future<void> finishLogin() async {
    try {
      accounts = await api.finishLogin();
    } on ApiException catch (error) {
      _error = error.message;
    }
    session = SessionState.idle;
    pendingAccountId = null;
    pendingCategoryId = null;
    sessionStartedAt = null;
    notifyListeners();
    await refreshAccounts();
  }

  Future<void> renameAccount(String id, String label) async {
    try {
      await api.renameAccount(id, label);
    } on ApiException catch (error) {
      _error = error.message;
    }
    await refreshAccounts();
  }

  Future<void> deleteAccount(String id) async {
    try {
      await api.deleteAccount(id);
    } on ApiException catch (error) {
      _error = error.message;
    }
    await refreshAccounts();
  }

  Future<void> setCategoryLimit(String categoryId, int maxAccounts) async {
    try {
      await api.setCategoryLimit(categoryId, maxAccounts);
    } on ApiException catch (error) {
      _error = error.message;
    }
    await refreshAccounts();
  }

  // --------------------------------------------------------------- recording

  Future<void> startRecording({
    required String name,
    required String url,
    bool? captureScroll,
    String? browser,
    String? accountId,
  }) async {
    try {
      await api.startRecording(
        name: name,
        url: url,
        captureScroll: captureScroll,
        browser: browser,
        accountId: accountId,
      );
      session = SessionState.recording;
      recordedSteps = 0;
      liveSteps.clear();
      page = AppPage.recorder;
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
        page = AppPage.scripts;
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
    double? speed,
    bool? headless,
    bool? keepOpen,
    String? browser,
    String? accountId,
  }) async {
    try {
      activeScriptId = id;
      await api.run(
        id,
        variables: variables,
        speed: speed,
        headless: headless,
        keepOpen: keepOpen,
        browser: browser,
        accountId: accountId,
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
