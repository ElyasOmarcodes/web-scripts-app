// Mirrors `backend/webscripts/accounts.py`.

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
        createdAt: (json['created_at'] as num? ?? 0).toInt(),
        updatedAt: (json['updated_at'] as num? ?? 0).toInt(),
        lastUsedAt: (json['last_used_at'] as num?)?.toInt(),
      );
}

class AccountBook {
  const AccountBook({this.categories = const [], this.accounts = const []});

  final List<AccountCategory> categories;
  final List<Account> accounts;

  factory AccountBook.fromJson(Map<String, dynamic> json) => AccountBook(
        categories: (json['categories'] as List<dynamic>? ?? [])
            .map((c) => AccountCategory.fromJson(c as Map<String, dynamic>))
            .toList(),
        accounts: (json['accounts'] as List<dynamic>? ?? [])
            .map((a) => Account.fromJson(a as Map<String, dynamic>))
            .toList(),
      );

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
