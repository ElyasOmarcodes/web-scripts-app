import 'package:flutter/material.dart';

/// The macOS design tokens the whole UI is built from.
///
/// Values mirror `docs/design-source/mac.css`, which is what the screenshots
/// in `docs/screenshots/` were rendered from.
@immutable
class MacPalette extends ThemeExtension<MacPalette> {
  const MacPalette({
    required this.accent,
    required this.accentSoft,
    required this.window,
    required this.sidebar,
    required this.content,
    required this.text,
    required this.text2,
    required this.text3,
    required this.hairline,
    required this.fill,
    required this.fill2,
    required this.green,
    required this.red,
    required this.orange,
    required this.purple,
    required this.pink,
    required this.teal,
  });

  final Color accent;
  final Color accentSoft;
  final Color window;
  final Color sidebar;
  final Color content;
  final Color text;
  final Color text2;
  final Color text3;
  final Color hairline;
  final Color fill;
  final Color fill2;
  final Color green;
  final Color red;
  final Color orange;
  final Color purple;
  final Color pink;
  final Color teal;

  static const light = MacPalette(
    accent: Color(0xFF007AFF),
    accentSoft: Color(0x1F007AFF),
    window: Color(0xFFFFFFFF),
    sidebar: Color(0xFFF4F4F6),
    content: Color(0xFFFFFFFF),
    text: Color(0xFF1D1D1F),
    text2: Color(0xFF6E6E73),
    text3: Color(0xFF98989D),
    hairline: Color(0x17000000),
    fill: Color(0x14787880),
    fill2: Color(0x24787880),
    green: Color(0xFF34C759),
    red: Color(0xFFFF3B30),
    orange: Color(0xFFFF9500),
    purple: Color(0xFFAF52DE),
    pink: Color(0xFFFF2D55),
    teal: Color(0xFF30B0C7),
  );

  static const dark = MacPalette(
    accent: Color(0xFF0A84FF),
    accentSoft: Color(0x380A84FF),
    window: Color(0xFF1E1E1E),
    sidebar: Color(0xFF28282A),
    content: Color(0xFF232325),
    text: Color(0xFFF5F5F7),
    text2: Color(0xFFA1A1A6),
    text3: Color(0xFF7C7C80),
    hairline: Color(0x1AFFFFFF),
    fill: Color(0x0FFFFFFF),
    fill2: Color(0x1FFFFFFF),
    green: Color(0xFF30D158),
    red: Color(0xFFFF453A),
    orange: Color(0xFFFF9F0A),
    purple: Color(0xFFBF5AF2),
    pink: Color(0xFFFF375F),
    teal: Color(0xFF40C8E0),
  );

  static MacPalette of(BuildContext context) =>
      Theme.of(context).extension<MacPalette>() ?? light;

  /// Gradients used by the colourful dashboard cards.
  static const gradients = <String, List<Color>>{
    'blue': [Color(0xFF0A84FF), Color(0xFF5E5CE6)],
    'green': [Color(0xFF32D74B), Color(0xFF24A148)],
    'orange': [Color(0xFFFF9F0A), Color(0xFFFF6482)],
    'purple': [Color(0xFFBF5AF2), Color(0xFF7D5FFF)],
    'pink': [Color(0xFFFF2D55), Color(0xFFFF6482)],
    'teal': [Color(0xFF30B0C7), Color(0xFF32D74B)],
  };

  /// Stable avatar colour for a script, so a script keeps its identity.
  Color avatarFor(String seed) {
    final palette = [accent, purple, orange, teal, pink, green];
    if (seed.isEmpty) return palette.first;
    return palette[seed.codeUnits.fold<int>(0, (a, b) => a + b) % palette.length];
  }

  @override
  MacPalette copyWith({
    Color? accent,
    Color? accentSoft,
    Color? window,
    Color? sidebar,
    Color? content,
    Color? text,
    Color? text2,
    Color? text3,
    Color? hairline,
    Color? fill,
    Color? fill2,
    Color? green,
    Color? red,
    Color? orange,
    Color? purple,
    Color? pink,
    Color? teal,
  }) {
    return MacPalette(
      accent: accent ?? this.accent,
      accentSoft: accentSoft ?? this.accentSoft,
      window: window ?? this.window,
      sidebar: sidebar ?? this.sidebar,
      content: content ?? this.content,
      text: text ?? this.text,
      text2: text2 ?? this.text2,
      text3: text3 ?? this.text3,
      hairline: hairline ?? this.hairline,
      fill: fill ?? this.fill,
      fill2: fill2 ?? this.fill2,
      green: green ?? this.green,
      red: red ?? this.red,
      orange: orange ?? this.orange,
      purple: purple ?? this.purple,
      pink: pink ?? this.pink,
      teal: teal ?? this.teal,
    );
  }

  @override
  MacPalette lerp(ThemeExtension<MacPalette>? other, double t) {
    if (other is! MacPalette) return this;
    Color mix(Color a, Color b) => Color.lerp(a, b, t) ?? a;
    return MacPalette(
      accent: mix(accent, other.accent),
      accentSoft: mix(accentSoft, other.accentSoft),
      window: mix(window, other.window),
      sidebar: mix(sidebar, other.sidebar),
      content: mix(content, other.content),
      text: mix(text, other.text),
      text2: mix(text2, other.text2),
      text3: mix(text3, other.text3),
      hairline: mix(hairline, other.hairline),
      fill: mix(fill, other.fill),
      fill2: mix(fill2, other.fill2),
      green: mix(green, other.green),
      red: mix(red, other.red),
      orange: mix(orange, other.orange),
      purple: mix(purple, other.purple),
      pink: mix(pink, other.pink),
      teal: mix(teal, other.teal),
    );
  }
}

/// Accent colours the user can pick in Settings.
const macAccents = <String, Color>{
  'blue': Color(0xFF007AFF),
  'purple': Color(0xFFAF52DE),
  'pink': Color(0xFFFF2D55),
  'orange': Color(0xFFFF9500),
  'green': Color(0xFF34C759),
};

class MacRadius {
  static const card = 12.0;
  static const row = 7.0;
  static const control = 6.0;
  static const sheet = 12.0;
}

/// Segoe UI is the closest match to SF on Windows; the Arabic-script fallback
/// keeps Pashto text readable at small sizes.
const macFontFamily = 'Segoe UI';
const macFontFallback = <String>['Segoe UI', 'Noto Naskh Arabic', 'Tahoma'];

ThemeData buildMacTheme(Brightness brightness, String accentKey) {
  final base = brightness == Brightness.dark ? MacPalette.dark : MacPalette.light;
  final accent = macAccents[accentKey] ?? base.accent;
  final palette = base.copyWith(
    accent: accent,
    accentSoft: accent.withOpacity(brightness == Brightness.dark ? 0.22 : 0.12),
  );

  final scheme = ColorScheme.fromSeed(
    seedColor: accent,
    brightness: brightness,
  ).copyWith(primary: accent, surface: palette.content);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: palette.content,
    fontFamily: macFontFamily,
    fontFamilyFallback: macFontFallback,
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    extensions: <ThemeExtension<dynamic>>[palette],
    textTheme: TextTheme(
      // 13px base, the macOS system size.
      bodyMedium: TextStyle(fontSize: 13, color: palette.text, height: 1.45),
      bodySmall: TextStyle(fontSize: 11.5, color: palette.text2, height: 1.4),
      titleSmall: TextStyle(
        fontSize: 13, fontWeight: FontWeight.w600, color: palette.text),
      titleMedium: TextStyle(
        fontSize: 16, fontWeight: FontWeight.w600, color: palette.text),
      headlineSmall: TextStyle(
        fontSize: 25,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.4,
        color: palette.text,
      ),
    ),
  );
}
