// Mirrors `backend/webscripts/accounts.py`.

import 'fingerprint.dart';

class AccountCategory {
  const AccountCategory({
    required this.id,
    required this.name,
    this.loginUrl = '',
    this.maxAccounts = 2,
    this.used = 0,
    this.color = 'blue',
    this.enabled = true,
  });

  final String id;
  final String name;
  final String loginUrl;
  final int maxAccounts;
  final int used;
  final String color;
  final bool enabled;

  bool get full => used >= maxAccounts;
  int get free => maxAccounts - used;

  factory AccountCategory.fromJson(Map<String, dynamic> json) =>
      AccountCategory(
        id: json['id'] as String? ?? '',
        name: json['name'] as String? ?? '',
        loginUrl: json['login_url'] as String? ?? '',
        maxAccounts: (json['max_accounts'] as num? ?? 2).toInt(),
        used: (json['used'] as num? ?? 0).toInt(),
        color: json['color'] as String? ?? 'blue',
        enabled: json['enabled'] as bool? ?? true,
      );
}

class Account {
  const Account({
    required this.id,
    required this.category,
    this.label = '',
    this.displayName = '',
    this.status = 'pending',
    this.cookieCount = 0,
    this.hasCookies = false,
    this.cookieState = 'unknown',
    this.cookieCheckedAt,
    this.cookieNote = '',
    this.proxyId = '',
    this.proxyMode = 'none',
    this.fingerprintId = '',
    this.fingerprint,
    this.createdAt = 0,
    this.updatedAt = 0,
    this.lastUsedAt,
  });

  final String id;
  final String category;
  final String label;
  final String displayName;
  final String status; // ready | pending | expired
  final int cookieCount;
  final bool hasCookies;

  /// alive | dead | checking | unknown — whether the saved cookies still
  /// open the site. "unknown" means nothing has checked yet.
  final String cookieState;
  final int? cookieCheckedAt;
  final String cookieNote;

  /// Which proxy this account goes out through, and how it is chosen:
  /// none (this machine's own address) | fixed | random.
  final String proxyId;
  final String proxyMode;

  bool get usesProxy => proxyMode != 'none';

  /// The browser identity this account wears — picked when it was created and
  /// kept for life, because a computer that changes every week is stranger
  /// than one that never moves.
  final String fingerprintId;
  final BrowserIdentity? fingerprint;

  final int createdAt;
  final int updatedAt;
  final int? lastUsedAt;

  bool get ready => status == 'ready' && hasCookies;

  factory Account.fromJson(Map<String, dynamic> json) => Account(
        id: json['id'] as String? ?? '',
        category: json['category'] as String? ?? '',
        label: json['label'] as String? ?? '',
        displayName: json['display_name'] as String? ?? '',
        status: json['status'] as String? ?? 'pending',
        cookieCount: (json['cookie_count'] as num? ?? 0).toInt(),
        hasCookies: json['has_cookies'] as bool? ?? false,
        cookieState: json['cookie_state'] as String? ?? 'unknown',
        cookieCheckedAt: (json['cookie_checked_at'] as num?)?.toInt(),
        cookieNote: json['cookie_note'] as String? ?? '',
        proxyId: json['proxy_id'] as String? ?? '',
        proxyMode: json['proxy_mode'] as String? ?? 'none',
        fingerprintId: json['fingerprint_id'] as String? ?? '',
        fingerprint: json['fingerprint'] == null
            ? null
            : BrowserIdentity.fromJson(
                json['fingerprint'] as Map<String, dynamic>),
        createdAt: (json['created_at'] as num? ?? 0).toInt(),
        updatedAt: (json['updated_at'] as num? ?? 0).toInt(),
        lastUsedAt: (json['last_used_at'] as num?)?.toInt(),
      );
}

class AccountBook {
  const AccountBook({
    this.categories = const [],
    this.accounts = const [],
    this.sharingProxy = const [],
  });

  final List<AccountCategory> categories;
  final List<Account> accounts;

  /// Groups of accounts on one site that would all go out through one
  /// address. Worth saying out loud rather than leaving to be found later.
  final List<SharedAddress> sharingProxy;

  factory AccountBook.fromJson(Map<String, dynamic> json) => AccountBook(
        categories: (json['categories'] as List<dynamic>? ?? [])
            .map((c) => AccountCategory.fromJson(c as Map<String, dynamic>))
            .toList(),
        accounts: (json['accounts'] as List<dynamic>? ?? [])
            .map((a) => Account.fromJson(a as Map<String, dynamic>))
            .toList(),
        sharingProxy: (json['sharing_proxy'] as List<dynamic>? ?? [])
            .map((s) => SharedAddress.fromJson(s as Map<String, dynamic>))
            .toList(),
      );

  /// Accounts wearing an identity another account also wears.
  List<Account> get twins {
    final counts = <String, int>{};
    for (final account in usable) {
      if (account.fingerprintId.isEmpty) continue;
      counts[account.fingerprintId] = (counts[account.fingerprintId] ?? 0) + 1;
    }
    return usable
        .where((a) => (counts[a.fingerprintId] ?? 0) > 1)
        .toList();
  }

  List<Account> of(String categoryId) =>
      accounts.where((a) => a.category == categoryId && a.ready).toList();

  AccountCategory? category(String id) {
    for (final category in categories) {
      if (category.id == id) return category;
    }
    return null;
  }

  Account? account(String id) {
    for (final account in accounts) {
      if (account.id == id) return account;
    }
    return null;
  }

  /// Only accounts that actually carry a usable session.
  List<Account> get usable => accounts.where((a) => a.ready).toList();

  int get total => usable.length;

  /// Categories that already hold at least one account, for the tab bar.
  List<AccountCategory> get populated =>
      categories.where((c) => of(c.id).isNotEmpty).toList();
}
