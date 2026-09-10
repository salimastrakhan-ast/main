import 'package:flutter/material.dart';

/// Тема приложения.
///
/// Один сине-стальной акцент и много воздуха: в мессенджере глаз должен
/// цепляться за сообщения, а не за интерфейс вокруг них.
abstract final class MayakTheme {
  static const _seed = Color(0xFF2B6CB0);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final scheme = ColorScheme.fromSeed(
      seedColor: _seed,
      brightness: brightness,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Явно свой Roboto из assets: иначе движок в вебе пойдёт за ним на
      // чужой CDN и до ответа не покажет ни кадра.
      fontFamily: 'Roboto',
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      ),
    );
  }

  /// Цвет пузыря своего сообщения.
  static Color ownBubble(ColorScheme scheme) =>
      scheme.primaryContainer;

  /// Цвет пузыря чужого сообщения.
  static Color otherBubble(ColorScheme scheme) =>
      scheme.surfaceContainerHighest;
}
