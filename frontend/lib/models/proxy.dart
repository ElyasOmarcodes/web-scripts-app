// Mirrors `backend/webscripts/proxies.py`.

/// One proxy: an address an account goes out through, so accounts do not all
/// appear from the same place.
class WebProxy {
  const WebProxy({
    required this.id,
    this.label = '',
    this.scheme = 'http',
    this.host = '',
    this.port = 0,
    this.username = '',
    this.hasPassword = false,
    this.enabled = true,
    this.status = 'unknown',
    this.latencyMs,
    this.exitIp = '',
    this.country = '',
    this.city = '',
    this.note = '',
    this.checkedAt,
    this.lastUsedAt,
    this.usedBy = 0,
  });

  final String id;
  final String label;
  final String scheme;
  final String host;
  final int port;
  final String username;

  /// The password itself never leaves the backend.
  final bool hasPassword;
  final bool enabled;

  /// alive | dead | checking | unknown
  final String status;
  final int? latencyMs;

  /// The address a site actually sees, and where it is.
  final String exitIp;
  final String country;
  final String city;
  final String note;
  final int? checkedAt;
  final int? lastUsedAt;

  /// How many accounts are pinned to this proxy.
  final int usedBy;

  String get address => '$host:$port';
  String get title => label.isEmpty ? address : label;
  bool get needsAuth => username.isNotEmpty || hasPassword;
  bool get alive => status == 'alive';
  bool get dead => status == 'dead';

  /// "Germany · Frankfurt", or empty when nothing is known yet.
  String get place => [country, city].where((p) => p.isNotEmpty).join(' · ');

  factory WebProxy.fromJson(Map<String, dynamic> json) => WebProxy(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        scheme: json['scheme'] as String? ?? 'http',
        host: json['host'] as String? ?? '',
        port: (json['port'] as num? ?? 0).toInt(),
        username: json['username'] as String? ?? '',
        hasPassword: json['has_password'] as bool? ?? false,
        enabled: json['enabled'] as bool? ?? true,
        status: json['status'] as String? ?? 'unknown',
        latencyMs: (json['latency_ms'] as num?)?.toInt(),
        exitIp: json['exit_ip'] as String? ?? '',
        country: json['country'] as String? ?? '',
        city: json['city'] as String? ?? '',
        note: json['note'] as String? ?? '',
        checkedAt: (json['checked_at'] as num?)?.toInt(),
        lastUsedAt: (json['last_used_at'] as num?)?.toInt(),
        usedBy: (json['used_by'] as num? ?? 0).toInt(),
      );
}

class ProxyBook {
  const ProxyBook({this.proxies = const [], this.overview = const {}});

  final List<WebProxy> proxies;
  final Map<String, int> overview;

  int get total => proxies.length;
  int get alive => overview['alive'] ?? 0;
  int get free => overview['free'] ?? 0;

  WebProxy? byId(String? id) {
    if (id == null || id.isEmpty) return null;
    for (final proxy in proxies) {
      if (proxy.id == id) return proxy;
    }
    return null;
  }

  List<WebProxy> get usable =>
      proxies.where((p) => p.enabled && !p.dead).toList();

  factory ProxyBook.fromJson(Map<String, dynamic> json) => ProxyBook(
        proxies: (json['proxies'] as List<dynamic>? ?? [])
            .map((p) => WebProxy.fromJson(p as Map<String, dynamic>))
            .toList(),
        overview: (json['overview'] as Map<dynamic, dynamic>? ?? {})
            .map((key, value) => MapEntry('$key', (value as num).toInt())),
      );
}
