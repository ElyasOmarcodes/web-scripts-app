// Mirrors `backend/webscripts/fingerprints.py`.

/// One of the hundred browser identities an account can wear.
///
/// A user agent on its own would be a disguise with the mask on and the
/// clothes unchanged; this carries the whole device — the browser brand and
/// version, the operating system, the screen, the cores and memory, and the
/// graphics card the page reads out of WebGL.
class BrowserIdentity {
  const BrowserIdentity({
    required this.id,
    required this.label,
    this.tier = 'safe',
    this.tierLabel = '',
    this.ua = '',
    this.brand = '',
    this.version = 0,
    this.platform = '',
    this.mobile = false,
    this.screen = '',
    this.cores = 0,
    this.memory,
    this.gpu = '',
    this.usedBy = 0,
  });

  final String id;
  final String label;

  /// safe (Windows desktop — what this machine really is), fair (other
  /// desktops), bold (phones and tablets: offered, never given out by
  /// itself).
  final String tier;
  final String tierLabel;
  final String ua;
  final String brand;
  final int version;
  final String platform;
  final bool mobile;
  final String screen;
  final int cores;
  final int? memory;
  final String gpu;

  /// How many accounts already wear this identity. Anything above one is
  /// worth avoiding.
  final int usedBy;

  bool get shared => usedBy > 1;

  /// A short line for the account card: "Windows · Chrome 145".
  String get shortLabel => label;

  factory BrowserIdentity.fromJson(Map<String, dynamic> json) =>
      BrowserIdentity(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        tier: json['tier'] as String? ?? 'safe',
        tierLabel: json['tier_label'] as String? ?? '',
        ua: json['ua'] as String? ?? '',
        brand: json['brand'] as String? ?? '',
        version: (json['version'] as num? ?? 0).toInt(),
        platform: json['platform'] as String? ?? '',
        mobile: json['mobile'] as bool? ?? false,
        screen: json['screen'] as String? ?? '',
        cores: (json['cores'] as num? ?? 0).toInt(),
        memory: (json['memory'] as num?)?.toInt(),
        gpu: json['gpu'] as String? ?? '',
        usedBy: (json['used_by'] as num? ?? 0).toInt(),
      );
}

class IdentityTier {
  const IdentityTier({required this.id, required this.label, this.note = ''});

  final String id;
  final String label;
  final String note;

  factory IdentityTier.fromJson(Map<String, dynamic> json) => IdentityTier(
        id: json['id'] as String? ?? '',
        label: json['label'] as String? ?? '',
        note: json['note'] as String? ?? '',
      );
}

/// The whole catalogue, as the Accounts page sees it.
class IdentityBook {
  const IdentityBook({this.profiles = const [], this.tiers = const []});

  final List<BrowserIdentity> profiles;
  final List<IdentityTier> tiers;

  factory IdentityBook.fromJson(Map<String, dynamic> json) => IdentityBook(
        profiles: (json['profiles'] as List<dynamic>? ?? [])
            .map((p) => BrowserIdentity.fromJson(p as Map<String, dynamic>))
            .toList(),
        tiers: (json['tiers'] as List<dynamic>? ?? [])
            .map((t) => IdentityTier.fromJson(t as Map<String, dynamic>))
            .toList(),
      );

  BrowserIdentity? byId(String id) {
    for (final profile in profiles) {
      if (profile.id == id) return profile;
    }
    return null;
  }

  List<BrowserIdentity> ofTier(String tier) =>
      profiles.where((p) => p.tier == tier).toList();

  /// Identities no account is using yet — the ones worth offering first.
  List<BrowserIdentity> get free =>
      profiles.where((p) => p.usedBy == 0).toList();

  int get total => profiles.length;
}

/// Two accounts of the same site going out through one address — the exact
/// pattern those sites look for.
class SharedAddress {
  const SharedAddress({
    required this.category,
    required this.proxyId,
    this.labels = const [],
  });

  final String category;
  final String proxyId;
  final List<String> labels;

  factory SharedAddress.fromJson(Map<String, dynamic> json) => SharedAddress(
        category: json['category'] as String? ?? '',
        proxyId: json['proxy_id'] as String? ?? '',
        labels: (json['labels'] as List<dynamic>? ?? [])
            .map((l) => l.toString())
            .toList(),
      );
}
