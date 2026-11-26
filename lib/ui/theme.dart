import 'dart:ui';

import 'package:flutter/material.dart';

/// 应用主题与毛玻璃配色。
class AppTheme {
  const AppTheme._();

  static const primary = Color(0xFF3E7BFA);
  static const secondary = Color(0xFF8B6BFF);
  static const accent = Color(0xFF17C3B2);

  static ThemeData light() => _build(Brightness.light);

  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: Colors.transparent,
      splashFactory: InkSparkle.splashFactory,
      appBarTheme: AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        foregroundColor: scheme.onSurface,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 19,
          fontWeight: FontWeight.w700,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: isDark
            ? Colors.white.withValues(alpha: 0.06)
            : Colors.white.withValues(alpha: 0.72),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        hintStyle: TextStyle(
          color: scheme.onSurfaceVariant.withValues(alpha: 0.75),
          fontSize: 14,
        ),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.85),
          ),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(
            color: isDark
                ? Colors.white.withValues(alpha: 0.10)
                : Colors.white.withValues(alpha: 0.85),
          ),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: BorderSide(color: primary, width: 1.4),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: isDark ? const Color(0xFF1B2233) : const Color(0xFF25304A),
        contentTextStyle: const TextStyle(color: Colors.white, fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant.withValues(alpha: 0.35),
        thickness: 0.7,
        space: 1,
      ),
    );
  }

  static bool isDark(BuildContext context) =>
      Theme.of(context).brightness == Brightness.dark;

  /// 玻璃填充色。
  static Color glassFill(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.065)
      : Colors.white.withValues(alpha: 0.58);

  /// 玻璃描边色。
  static Color glassBorder(BuildContext context) => isDark(context)
      ? Colors.white.withValues(alpha: 0.12)
      : Colors.white.withValues(alpha: 0.78);

  static Color textSecondary(BuildContext context) =>
      Theme.of(context).colorScheme.onSurfaceVariant;

  /// 页面背景渐变。
  static List<Color> backgroundGradient(BuildContext context) => isDark(context)
      ? const [Color(0xFF0A0F1E), Color(0xFF131A2C), Color(0xFF0B1220)]
      : const [Color(0xFFEBF1FF), Color(0xFFF8F9FF), Color(0xFFEDF7F5)];

  static List<BoxShadow> softShadow(BuildContext context) => [
        BoxShadow(
          color: isDark(context)
              ? Colors.black.withValues(alpha: 0.35)
              : const Color(0xFF3A5A96).withValues(alpha: 0.10),
          blurRadius: 26,
          offset: const Offset(0, 12),
        ),
      ];
}

/// 背景装饰用的模糊光斑。
class AuroraBackground extends StatelessWidget {
  const AuroraBackground({super.key});

  @override
  Widget build(BuildContext context) {
    final dark = AppTheme.isDark(context);
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: AppTheme.backgroundGradient(context),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        children: [
          _blob(
            Alignment.topRight,
            const Color(0xFF6C8CFF).withValues(alpha: dark ? 0.30 : 0.45),
            300,
          ),
          _blob(
            const Alignment(-0.95, -0.35),
            const Color(0xFF7DE2D1).withValues(alpha: dark ? 0.18 : 0.42),
            260,
          ),
          _blob(
            const Alignment(-0.7, 0.95),
            const Color(0xFFB79CFF).withValues(alpha: dark ? 0.22 : 0.38),
            320,
          ),
        ],
      ),
    );
  }

  Widget _blob(Alignment alignment, Color color, double size) {
    return Align(
      alignment: alignment,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 70, sigmaY: 70),
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
          ),
        ),
      ),
    );
  }
}
