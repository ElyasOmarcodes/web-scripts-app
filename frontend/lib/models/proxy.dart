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
    this.kind = 'unknown',
    this.isp = '',
    this.flagged = false,
    this.risk = 'unknown',
    this.riskNote = '',
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

  /// residential | mobile | datacentre | unknown — what kind of line the
  /// address sits on. Not a detail: it is the difference between a site
  /// treating the account as a person and treating it as a machine.
  final String kind;
  final String isp;

  /// Already published on a list of known proxies and VPNs.
  final bool flagged;

  /// low | high | unknown — how a social site is likely to take it.
  final String risk;
  final String riskNote;

  bool get risky => risk == 'high';

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
        kind: json['kind'] as String? ?? 'unknown',
        isp: json['isp'] as String? ?? '',
        flagged: json['flagged'] as bool? ?? false,
        risk: json['risk'] as String? ?? 'unknown',
        riskNote: json['risk_note'] as String? ?? '',
      );
}

class ProxyBook {
  const ProxyBook({this.proxies = const [], this.overview = const {}});

  final List<WebProxy> proxies;
  final Map<String, int> overview;

  /// Addresses a social site is likely to distrust — the reason a proxied
  /// login can look fine and then be thrown away half a minute later.
  List<WebProxy> get risky => proxies.where((p) => p.risky).toList();

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
