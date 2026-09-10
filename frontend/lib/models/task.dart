// Mirrors `backend/webscripts/tasks.py`.

/// How one account's turn inside a task went.
class AccountRun {
  const AccountRun({
    required this.accountId,
    this.status = 'pending',
    this.startedAt,
    this.finishedAt,
    this.completed = 0,
    this.total = 0,
    this.error,
    this.screenshot,
  });

  final String accountId;

  /// pending | running | ok | failed | stopped
  final String status;
  final int? startedAt;
  final int? finishedAt;
  final int completed;
  final int total;
  final String? error;
  final String? screenshot;

  bool get done => status == 'ok';
  bool get failed => status == 'failed';
  bool get running => status == 'running';

  factory AccountRun.fromJson(Map<String, dynamic> json) => AccountRun(
        accountId: json['account_id'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        startedAt: (json['started_at'] as num?)?.toInt(),
        finishedAt: (json['finished_at'] as num?)?.toInt(),
        completed: (json['completed'] as num? ?? 0).toInt(),
        total: (json['total'] as num? ?? 0).toInt(),
        error: json['error'] as String?,
        screenshot: json['screenshot'] as String?,
      );
}

class WebTask {
  const WebTask({
    required this.id,
    this.name = '',
    this.scriptId = '',
    this.accountIds = const [],
    this.concurrency = 1,
    this.browser,
    this.speed,
    this.headless,
    this.keepOpen = false,
    this.stopOnError = false,
    this.gapSeconds = 3,
    this.variables = const {},
    this.note = '',
    this.status = 'draft',
    this.runs = const [],
    this.createdAt = 0,
    this.updatedAt = 0,
    this.lastRunAt,
    this.doneCount = 0,
    this.failedCount = 0,
    this.pendingCount = 0,
  });

  final String id;
  final String name;
  final String scriptId;
  final List<String> accountIds;

  /// How many browser windows work at the same time; they are tiled on
  /// screen. The sensible ceiling belongs to the machine — see /api/system.
  final int concurrency;
  final String? browser;
  final double? speed;
  final bool? headless;
  final bool keepOpen;
  final bool stopOnError;
  final double gapSeconds;
  final Map<String, String> variables;
  final String note;

  /// draft | running | done | failed | partial
  final String status;
  final List<AccountRun> runs;
  final int createdAt;
  final int updatedAt;
  final int? lastRunAt;
  final int doneCount;
  final int failedCount;
  final int pendingCount;

  bool get isRunning => status == 'running';

  /// Runs without showing a browser window. Null means "use the setting".
  bool get runsHidden => headless ?? false;

  /// A task that stopped half way can carry on from the account it stopped at.
  bool get canResume =>
      (status == 'partial' || status == 'failed') && pendingCount > 0;

  AccountRun? runFor(String accountId) {
    for (final run in runs) {
      if (run.accountId == accountId) return run;
    }
    return null;
  }

  factory WebTask.fromJson(Map<String, dynamic> json) => WebTask(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        scriptId: json['script_id'] as String? ?? '',
        accountIds: (json['account_ids'] as List<dynamic>? ?? [])
            .map((e) => e as String)
            .toList(),
        concurrency: (json['concurrency'] as num? ?? 1).toInt(),
        browser: json['browser'] as String?,
        speed: (json['speed'] as num?)?.toDouble(),
        headless: json['headless'] as bool?,
        keepOpen: json['keep_open'] as bool? ?? false,
        stopOnError: json['stop_on_error'] as bool? ?? false,
        gapSeconds: (json['gap_seconds'] as num? ?? 3).toDouble(),
        variables: (json['variables'] as Map<dynamic, dynamic>? ?? {})
            .map((key, value) => MapEntry('$key', '$value')),
        note: json['note'] as String? ?? '',
        status: json['status'] as String? ?? 'draft',
        runs: (json['runs'] as List<dynamic>? ?? [])
            .map((r) => AccountRun.fromJson(r as Map<String, dynamic>))
            .toList(),
        createdAt: (json['created_at'] as num? ?? 0).toInt(),
        updatedAt: (json['updated_at'] as num? ?? 0).toInt(),
        lastRunAt: (json['last_run_at'] as num?)?.toInt(),
        doneCount: (json['done_count'] as num? ?? 0).toInt(),
        failedCount: (json['failed_count'] as num? ?? 0).toInt(),
        pendingCount: (json['pending_count'] as num? ?? 0).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'script_id': scriptId,
        'account_ids': accountIds,
        'concurrency': concurrency,
        if (browser != null) 'browser': browser,
        if (speed != null) 'speed': speed,
        'headless': headless,
        'keep_open': keepOpen,
        'stop_on_error': stopOnError,
        'gap_seconds': gapSeconds,
        'variables': variables,
        'note': note,
      };

  WebTask copyWith({
    String? name,
    bool? clearHeadless,
    String? scriptId,
    List<String>? accountIds,
    int? concurrency,
    bool? keepOpen,
    bool? stopOnError,
    double? gapSeconds,
    double? speed,
    bool? headless,
    Map<String, String>? variables,
    String? note,
  }) {
    return WebTask(
      id: id,
      name: name ?? this.name,
      scriptId: scriptId ?? this.scriptId,
      accountIds: accountIds ?? this.accountIds,
      concurrency: concurrency ?? this.concurrency,
      browser: browser,
      speed: speed ?? this.speed,
      headless: (clearHeadless ?? false) ? null : (headless ?? this.headless),
      keepOpen: keepOpen ?? this.keepOpen,
      stopOnError: stopOnError ?? this.stopOnError,
      gapSeconds: gapSeconds ?? this.gapSeconds,
      variables: variables ?? this.variables,
      note: note ?? this.note,
      status: status,
      runs: runs,
      createdAt: createdAt,
      updatedAt: updatedAt,
      lastRunAt: lastRunAt,
      doneCount: doneCount,
      failedCount: failedCount,
      pendingCount: pendingCount,
    );
  }
}

class TaskBook {
  const TaskBook({this.tasks = const [], this.overview = const {}});

  final List<WebTask> tasks;
  final Map<String, int> overview;

  int get total => tasks.length;

  WebTask? byId(String id) {
    for (final task in tasks) {
      if (task.id == id) return task;
    }
    return null;
  }

  factory TaskBook.fromJson(Map<String, dynamic> json) => TaskBook(
        tasks: (json['tasks'] as List<dynamic>? ?? [])
            .map((t) => WebTask.fromJson(t as Map<String, dynamic>))
            .toList(),
        overview: (json['overview'] as Map<dynamic, dynamic>? ?? {})
            .map((key, value) => MapEntry('$key', (value as num).toInt())),
      );
}
