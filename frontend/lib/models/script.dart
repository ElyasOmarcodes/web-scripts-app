// Data model mirroring `backend/webscripts/models.py`.

class TargetModel {
  TargetModel({required this.type, required this.value, this.kind = 'generic'});

  final String type; // css | xpath
  final String value;
  final String kind;

  factory TargetModel.fromJson(Map<String, dynamic> json) => TargetModel(
        type: json['type'] as String? ?? 'css',
        value: json['value'] as String? ?? '',
        kind: json['kind'] as String? ?? 'generic',
      );

  Map<String, dynamic> toJson() => {'type': type, 'value': value, 'kind': kind};
}

class StepModel {
  StepModel({
    required this.id,
    required this.action,
    this.targets = const [],
    this.value,
    this.optionValue,
    this.url,
    this.framePath = const [],
    this.label = '',
    this.tag,
    this.delayMs = 0,
    this.enabled = true,
    this.optional = false,
    this.secret = false,
    this.ts = 0,
    this.note = '',
  });

  final String id;
  final String action;
  final List<TargetModel> targets;
  String? value;
  final String? optionValue;
  String? url;
  final List<int> framePath;
  final String label;
  final String? tag;
  int delayMs;
  bool enabled;

  /// Skip me instead of failing the run when my element is not there.
  bool optional;
  final bool secret;
  final int ts;
  String note;

  factory StepModel.fromJson(Map<String, dynamic> json) => StepModel(
        id: json['id'] as String? ?? '',
        action: json['action'] as String? ?? 'click',
        targets: (json['targets'] as List<dynamic>? ?? [])
            .map((t) => TargetModel.fromJson(t as Map<String, dynamic>))
            .toList(),
        value: json['value'] as String?,
        optionValue: json['option_value'] as String?,
        url: json['url'] as String?,
        framePath: (json['frame_path'] as List<dynamic>? ?? [])
            .map((e) => (e as num).toInt())
            .toList(),
        label: json['label'] as String? ?? '',
        tag: json['tag'] as String?,
        delayMs: (json['delay_ms'] as num? ?? 0).toInt(),
        enabled: json['enabled'] as bool? ?? true,
        optional: json['optional'] as bool? ?? false,
        secret: json['secret'] as bool? ?? false,
        ts: (json['ts'] as num? ?? 0).toInt(),
        note: json['note'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'action': action,
        'targets': targets.map((t) => t.toJson()).toList(),
        'value': value,
        'option_value': optionValue,
        'url': url,
        'frame_path': framePath,
        'label': label,
        'tag': tag,
        'delay_ms': delayMs,
        'enabled': enabled,
        'optional': optional,
        'secret': secret,
        'ts': ts,
        'note': note,
      };

  /// The same wording the backend uses in its logs.
  String get description {
    final what = label.isNotEmpty
        ? label
        : (targets.isNotEmpty ? targets.first.value : '');
    switch (action) {
      case 'goto':
        return 'پرانیستل: ${url ?? ''}';
      case 'click':
        return 'کلیک: $what';
      case 'type':
        return 'لیکل «${secret ? '••••••' : (value ?? '')}» په: $what';
      case 'select':
        return 'غوره کول «${value ?? ''}» له: $what';
      case 'press_key':
        return 'تڼۍ: ${value ?? ''}';
      case 'hover':
        return 'موږک پورته: $what';
      case 'scroll':
        return 'سکرول: ${value ?? ''}';
      case 'wait':
        return 'انتظار: ${value ?? ''} ms';
      case 'switch_window':
        return 'بلې کړکۍ ته تګ';
      case 'assert_text':
        return 'د متن کتنه: ${value ?? ''}';
      case 'screenshot':
        return 'عکس اخیستل';
      default:
        return action;
    }
  }

  bool get isEditable =>
      action == 'type' || action == 'assert_text' || action == 'goto';
}

class VariableModel {
  VariableModel({
    required this.name,
    this.label = '',
    this.secret = false,
    this.defaultValue = '',
  });

  final String name;
  final String label;
  final bool secret;
  final String defaultValue;

  factory VariableModel.fromJson(Map<String, dynamic> json) => VariableModel(
        name: json['name'] as String? ?? '',
        label: json['label'] as String? ?? '',
        secret: json['secret'] as bool? ?? false,
        defaultValue: json['default'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'name': name,
        'label': label,
        'secret': secret,
        'default': defaultValue,
      };
}

class WebScript {
  WebScript({
    required this.id,
    required this.name,
    this.description = '',
    this.startUrl = '',
    this.steps = const [],
    this.variables = const [],
    this.stepCount = 0,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.lastRunAt,
    this.lastRunOk,
  });

  final String id;
  final String name;
  final String description;
  final String startUrl;
  final List<StepModel> steps;
  final List<VariableModel> variables;
  final int stepCount;
  final int createdAt;
  final int updatedAt;
  final int? lastRunAt;
  final bool? lastRunOk;

  /// Handles both the summary payload (`/api/scripts`) and the full script.
  factory WebScript.fromJson(Map<String, dynamic> json) {
    final steps = (json['steps'] as List<dynamic>? ?? [])
        .map((s) => StepModel.fromJson(s as Map<String, dynamic>))
        .toList();
    return WebScript(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? '',
      description: json['description'] as String? ?? '',
      startUrl: json['start_url'] as String? ?? '',
      steps: steps,
      variables: (json['variables'] as List<dynamic>? ?? [])
          .map((v) => VariableModel.fromJson(v as Map<String, dynamic>))
          .toList(),
      stepCount: (json['step_count'] as num?)?.toInt() ??
          steps.where((s) => s.enabled).length,
      createdAt: (json['created_at'] as num? ?? 0).toInt(),
      updatedAt: (json['updated_at'] as num? ?? 0).toInt(),
      lastRunAt: (json['last_run_at'] as num?)?.toInt(),
      lastRunOk: json['last_run_ok'] as bool?,
    );
  }

  bool get hasDetail => steps.isNotEmpty;
}

/// One line coming from the backend event stream.
class AppEvent {
  AppEvent({
    required this.type,
    this.level = 'info',
    this.message = '',
    this.index,
    this.total,
    this.ts = 0,
    this.raw = const {},
  });

  final String type;
  final String level;
  final String message;
  final int? index;
  final int? total;
  final int ts;
  final Map<String, dynamic> raw;

  factory AppEvent.fromJson(Map<String, dynamic> json) => AppEvent(
        type: json['type'] as String? ?? 'log',
        level: json['level'] as String? ?? 'info',
        message: json['message'] as String? ?? _fallbackMessage(json),
        index: (json['index'] as num?)?.toInt(),
        total: (json['total'] as num?)?.toInt(),
        ts: (json['ts'] as num? ?? 0).toInt(),
        raw: json,
      );

  bool get isError =>
      level == 'error' || type == 'step_error' || type == 'recording_failed';

  static String _fallbackMessage(Map<String, dynamic> json) {
    switch (json['type']) {
      case 'run_started':
        return 'چلول پیل شول: ${json['name'] ?? ''}';
      case 'run_finished':
        return 'پای: ${json['status'] ?? ''}';
      case 'recording_started':
        return 'ثبتول پیل شول';
      case 'recording_saved':
        return 'سکریپټ خوندي شو';
      default:
        return '';
    }
  }
}
