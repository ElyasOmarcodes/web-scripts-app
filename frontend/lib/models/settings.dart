// Mirrors `backend/webscripts/settings.py` and `browsers.py`.

class AppSettings {
  const AppSettings({
    this.browser = 'auto',
    this.headless = false,
    this.keepOpen = false,
    this.speed = 1.0,
    this.captureScroll = false,
    this.stepTimeout = 15,
    this.useProfile = true,
    this.humanize = true,
    this.humanMinGap = 0.5,
    this.humanMaxGap = 1.5,
    this.randomScroll = true,
    this.smartSkip = true,
    this.theme = 'system',
    this.accent = 'blue',
    this.sidebarCollapsed = false,
    this.confirmDelete = true,
  });

  final String browser;
  final bool headless;
  final bool keepOpen;
  final double speed;
  final bool captureScroll;
  final double stepTimeout;
  final bool useProfile;

  /// Anti-ban behaviour: random pauses, random click points, random scrolling.
  final bool humanize;
  final double humanMinGap;
  final double humanMaxGap;
  final bool randomScroll;

  /// Step over a step whose element is legitimately gone.
  final bool smartSkip;
  final String theme;
  final String accent;
  final bool sidebarCollapsed;
  final bool confirmDelete;

  factory AppSettings.fromJson(Map<String, dynamic> json) => AppSettings(
        browser: json['browser'] as String? ?? 'auto',
        headless: json['headless'] as bool? ?? false,
        keepOpen: json['keep_open'] as bool? ?? false,
        speed: (json['speed'] as num? ?? 1).toDouble(),
        captureScroll: json['capture_scroll'] as bool? ?? false,
        stepTimeout: (json['step_timeout'] as num? ?? 15).toDouble(),
        useProfile: json['use_profile'] as bool? ?? true,
        humanize: json['humanize'] as bool? ?? true,
        humanMinGap: (json['human_min_gap'] as num? ?? 0.5).toDouble(),
        humanMaxGap: (json['human_max_gap'] as num? ?? 1.5).toDouble(),
        randomScroll: json['random_scroll'] as bool? ?? true,
        smartSkip: json['smart_skip'] as bool? ?? true,
        theme: json['theme'] as String? ?? 'system',
        accent: json['accent'] as String? ?? 'blue',
        sidebarCollapsed: json['sidebar_collapsed'] as bool? ?? false,
        confirmDelete: json['confirm_delete'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => {
        'browser': browser,
        'headless': headless,
        'keep_open': keepOpen,
        'speed': speed,
        'capture_scroll': captureScroll,
        'step_timeout': stepTimeout,
        'use_profile': useProfile,
        'humanize': humanize,
        'human_min_gap': humanMinGap,
        'human_max_gap': humanMaxGap,
        'random_scroll': randomScroll,
        'smart_skip': smartSkip,
        'theme': theme,
        'accent': accent,
        'sidebar_collapsed': sidebarCollapsed,
        'confirm_delete': confirmDelete,
      };
}

class BrowserInfo {
  const BrowserInfo({
    required this.id,
    required this.name,
    this.family = 'chromium',
    this.path = '',
    this.version = '',
    this.installed = false,
    this.supported = true,
  });

  final String id;
  final String name;
  final String family;
  final String path;
  final String version;
  final bool installed;
  final bool supported;

  factory BrowserInfo.fromJson(Map<String, dynamic> json) => BrowserInfo(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        family: json['family'] as String? ?? 'chromium',
        path: json['path'] as String? ?? '',
        version: json['version'] as String? ?? '',
        installed: json['installed'] as bool? ?? false,
        supported: json['supported'] as bool? ?? true,
      );

  /// "141.0.2623.75" out of "Microsoft Edge 141.0.2623.75"
  String get shortVersion {
    final match = RegExp(r'[\d.]{3,}').firstMatch(version);
    return match?.group(0) ?? version;
  }

  bool get usable => installed && supported;
}

class BrowserList {
  const BrowserList(
      {this.browsers = const [], this.selected = 'auto', this.active});

  final List<BrowserInfo> browsers;
  final String selected;
  final String? active;

  factory BrowserList.fromJson(Map<String, dynamic> json) => BrowserList(
        browsers: (json['browsers'] as List<dynamic>? ?? [])
            .map((b) => BrowserInfo.fromJson(b as Map<String, dynamic>))
            .toList(),
        selected: json['selected'] as String? ?? 'auto',
        active: json['active'] as String?,
      );

  BrowserInfo? get activeBrowser {
    for (final browser in browsers) {
      if (browser.id == active) return browser;
    }
    return null;
  }

  List<BrowserInfo> get installed => browsers.where((b) => b.usable).toList();
}
