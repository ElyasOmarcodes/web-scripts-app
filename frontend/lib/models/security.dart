// Mirrors `backend/webscripts/vault.py`.

/// How the app is locked, and which ways in this computer can offer.
class SecurityState {
  const SecurityState({
    this.configured = false,
    this.locked = false,
    this.windowsUser = '',
    this.windowsAvailable = false,
    this.windowsEnabled = false,
    this.biometricState = 'not_windows',
    this.biometricMessage = '',
    this.biometricDetail = '',
    this.biometricEnabled = false,
    this.createdAt,
    this.changedAt,
    this.minLength = 6,
  });

  /// False on the very first run — the app asks for a new password instead of
  /// an old one.
  final bool configured;
  final bool locked;

  final String windowsUser;
  final bool windowsAvailable;
  final bool windowsEnabled;

  /// ready · not_enrolled · uncertain · no_hardware · not_windows
  final String biometricState;
  final String biometricMessage;

  /// The raw reason, shown small, for when Windows would not answer.
  final String biometricDetail;
  final bool biometricEnabled;

  final int? createdAt;
  final int? changedAt;
  final int minLength;

  /// A reader that exists and has a finger registered on it.
  bool get biometricReady => biometricState == 'ready';

  /// Windows would not say — often on the very machines whose owner unlocks
  /// them with the reader every morning. Offered anyway: one touch settles
  /// it better than any amount of asking.
  bool get biometricUncertain => biometricState == 'uncertain';

  /// A reader is there, but Windows has no fingerprint on file yet — the one
  /// case where offering to open the Windows page is useful.
  bool get biometricNeedsEnrolment => biometricState == 'not_enrolled';

  /// No reader at all: the option is shown, greyed out, with the reason.
  bool get biometricPossible =>
      biometricReady || biometricNeedsEnrolment || biometricUncertain;

  /// Whether the switch may be touched at all: anything but "definitely no".
  bool get biometricOfferable => biometricReady || biometricUncertain;

  /// The ways in that are switched on right now.
  List<String> get methods => [
        'password',
        if (windowsEnabled) 'windows',
        if (biometricEnabled) 'biometric',
      ];

  factory SecurityState.fromJson(Map<String, dynamic> json) => SecurityState(
        configured: json['configured'] as bool? ?? false,
        locked: json['locked'] as bool? ?? false,
        windowsUser: json['windows_user'] as String? ?? '',
        windowsAvailable: json['windows_available'] as bool? ?? false,
        windowsEnabled: json['windows_enabled'] as bool? ?? false,
        biometricState: json['biometric_state'] as String? ?? 'not_windows',
        biometricMessage: json['biometric_message'] as String? ?? '',
        biometricDetail: json['biometric_detail'] as String? ?? '',
        biometricEnabled: json['biometric_enabled'] as bool? ?? false,
        createdAt: (json['created_at'] as num?)?.toInt(),
        changedAt: (json['changed_at'] as num?)?.toInt(),
        minLength: (json['min_length'] as num? ?? 6).toInt(),
      );
}

/// What the app knows it is holding for an account, without holding it open.
class SecretSummary {
  const SecretSummary({
    this.hasUsername = false,
    this.hasPassword = false,
    this.hasNote = false,
    this.updatedAt,
  });

  final bool hasUsername;
  final bool hasPassword;
  final bool hasNote;
  final int? updatedAt;

  bool get any => hasUsername || hasPassword || hasNote;

  factory SecretSummary.fromJson(Map<String, dynamic> json) => SecretSummary(
        hasUsername: json['has_username'] as bool? ?? false,
        hasPassword: json['has_password'] as bool? ?? false,
        hasNote: json['has_note'] as bool? ?? false,
        updatedAt: (json['updated_at'] as num?)?.toInt(),
      );
}

/// Everything one account's own page shows — and no secret among it.
class AccountDetail {
  const AccountDetail({
    required this.id,
    this.label = '',
    this.category = '',
    this.categoryName = '',
    this.displayName = '',
    this.loginUrl = '',
    this.status = 'pending',
    this.cookieCount = 0,
    this.cookieState = 'unknown',
    this.cookieCheckedAt,
    this.cookieNote = '',
    this.cookieNames = const [],
    this.cookieDomains = const [],
    this.proxyMode = 'none',
    this.proxyTitle = '',
    this.proxyPlace = '',
    this.fingerprintLabel = '',
    this.fingerprintUa = '',
    this.fingerprintScreen = '',
    this.fingerprintGpu = '',
    this.profileDir = '',
    this.createdAt = 0,
    this.lastUsedAt,
    this.secrets = const SecretSummary(),
  });

  final String id;
  final String label;
  final String category;
  final String categoryName;
  final String displayName;
  final String loginUrl;
  final String status;

  final int cookieCount;
  final String cookieState;
  final int? cookieCheckedAt;
  final String cookieNote;

  /// The names only. What is inside them needs the password.
  final List<String> cookieNames;
  final List<String> cookieDomains;

  final String proxyMode;
  final String proxyTitle;
  final String proxyPlace;

  final String fingerprintLabel;
  final String fingerprintUa;
  final String fingerprintScreen;
  final String fingerprintGpu;

  final String profileDir;
  final int createdAt;
  final int? lastUsedAt;
  final SecretSummary secrets;

  factory AccountDetail.fromJson(Map<String, dynamic> json) {
    final proxy = json['proxy'] as Map<String, dynamic>?;
    final identity = json['fingerprint'] as Map<String, dynamic>?;
    return AccountDetail(
      id: json['id'] as String? ?? '',
      label: json['label'] as String? ?? '',
      category: json['category'] as String? ?? '',
      categoryName: json['category_name'] as String? ?? '',
      displayName: json['display_name'] as String? ?? '',
      loginUrl: json['login_url'] as String? ?? '',
      status: json['status'] as String? ?? 'pending',
      cookieCount: (json['cookie_count'] as num? ?? 0).toInt(),
      cookieState: json['cookie_state'] as String? ?? 'unknown',
      cookieCheckedAt: (json['cookie_checked_at'] as num?)?.toInt(),
      cookieNote: json['cookie_note'] as String? ?? '',
      cookieNames: (json['cookie_names'] as List<dynamic>? ?? [])
          .map((c) => c.toString())
          .toList(),
      cookieDomains: (json['cookie_domains'] as List<dynamic>? ?? [])
          .map((c) => c.toString())
          .toList(),
      proxyMode: json['proxy_mode'] as String? ?? 'none',
      proxyTitle: proxy == null
          ? ''
          : (proxy['label'] as String? ?? '').isNotEmpty
              ? proxy['label'] as String
              : (proxy['address'] as String? ?? ''),
      proxyPlace: proxy == null
          ? ''
          : [proxy['country'], proxy['city']]
              .where((p) => (p as String? ?? '').isNotEmpty)
              .join(' · '),
      fingerprintLabel: identity?['label'] as String? ?? '',
      fingerprintUa: identity?['ua'] as String? ?? '',
      fingerprintScreen: identity?['screen'] as String? ?? '',
      fingerprintGpu: identity?['gpu'] as String? ?? '',
      profileDir: json['profile_dir'] as String? ?? '',
      createdAt: (json['created_at'] as num? ?? 0).toInt(),
      lastUsedAt: (json['last_used_at'] as num?)?.toInt(),
      secrets: SecretSummary.fromJson(
          json['secrets'] as Map<String, dynamic>? ?? const {}),
    );
  }
}

/// Where an export landed, so the page can say so and offer the folder.
class TransferResult {
  const TransferResult({
    this.folder = '',
    this.files = const [],
    this.count = 0,
    this.added = 0,
    this.duplicates = 0,
    this.problems = const [],
    this.note = '',
  });

  final String folder;
  final List<String> files;
  final int count;
  final int added;
  final int duplicates;
  final List<String> problems;
  final String note;

  factory TransferResult.fromJson(Map<String, dynamic> json) => TransferResult(
        folder: json['folder'] as String? ?? '',
        files: (json['files'] as List<dynamic>? ?? [])
            .map((f) => f.toString())
            .toList(),
        count: (json['count'] as num? ?? 0).toInt(),
        added: (json['added'] as num? ?? 0).toInt(),
        duplicates: (json['duplicates'] as num? ?? 0).toInt(),
        problems: (json['problems'] as List<dynamic>? ?? [])
            .map((p) => p.toString())
            .toList(),
        note: json['note'] as String? ?? '',
      );
}
