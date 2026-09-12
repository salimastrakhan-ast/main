import 'package:flutter/material.dart';

import 'tokens.dart';

/// Тема приложения.
///
/// Построена на [Tokens] — значениях из `web/src/styles.css`. Плоские
/// поверхности, волосяные границы, единственная глубокая тень у
/// всплывающего, один акцент.
///
/// Тема одна: в источнике светлой нет. Подробности — в [Tokens].
abstract final class TitoTheme {
  // --- Шрифты ---

  /// Текст интерфейса — тот же Manrope, что в веб-клиенте.
  static const _font = 'Manrope';

  /// Название приложения и крупные заголовки — Unbounded, как в источнике
  /// (`--font-display`).
  static const display = 'Unbounded';

  /// Цифры одной ширины.
  ///
  /// Заменяют отдельный моноширинный шрифт: время и счётчики не прыгают при
  /// обновлении минуты, а в сборке на одно семейство меньше.
  static const tabularFigures = [FontFeature.tabularFigures()];

  static ThemeData dark() => _build(_darkScheme);

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Tokens.accent,
    onPrimary: Tokens.onAccent,
    primaryContainer: Tokens.bubbleOut,
    onPrimaryContainer: Tokens.fg,
    secondary: Tokens.accent,
    onSecondary: Tokens.onAccent,
    secondaryContainer: Tokens.elevated,
    onSecondaryContainer: Tokens.muted,
    tertiary: Tokens.accent,
    onTertiary: Tokens.onAccent,
    tertiaryContainer: Tokens.surface,
    onTertiaryContainer: Tokens.fg,
    error: Tokens.danger,
    onError: Color(0xFF3A0E0E),
    errorContainer: Color(0xFF5A2020),
    onErrorContainer: Color(0xFFF7DEDE),
    surface: Tokens.bg,
    onSurface: Tokens.fg,
    surfaceDim: Tokens.bg,
    surfaceBright: Tokens.elevated,
    surfaceContainerLowest: Tokens.bg,
    surfaceContainerLow: Tokens.sidebar,
    surfaceContainer: Tokens.sidebar,
    surfaceContainerHigh: Tokens.surface,
    surfaceContainerHighest: Tokens.elevated,
    onSurfaceVariant: Tokens.muted,
    outline: Tokens.subtle,
    outlineVariant: Tokens.border,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: Tokens.fg,
    onInverseSurface: Tokens.bg,
    inversePrimary: Tokens.accent,
  );

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: _font,
      textTheme: _textTheme,
      scaffoldBackgroundColor: scheme.surface,

      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 17,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 20),
        actionsIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 20,
        ),
        shape: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant,
            width: Tokens.borderSm,
          ),
        ),
      ),

      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 20),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        // В источнике поля залиты `elevated`: на полотне они должны быть
        // видны как поля, а не как вырез в нём.
        fillColor: scheme.surfaceContainerHighest,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
        border: _inputBorder(scheme.outlineVariant),
        enabledBorder: _inputBorder(scheme.outlineVariant),
        // Кольцо фокуса — `--color-ring`, он же акцент.
        focusedBorder: _inputBorder(Tokens.ring, width: Tokens.borderMd),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: Tokens.borderMd),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Tokens.space4,
          vertical: Tokens.space3 + 2,
        ),
        prefixIconColor: scheme.onSurfaceVariant,
        suffixIconColor: scheme.onSurfaceVariant,
      ),

      filledButtonTheme: FilledButtonThemeData(style: _primaryButton(scheme)),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: _secondaryButton(scheme),
      ),
      textButtonTheme: TextButtonThemeData(style: _ghostButton(scheme)),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          overlayColor: _overlay(scheme.onSurface),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(Tokens.radiusShell),
            ),
          ),
        ),
      ),

      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _FadeThroughTransitions(),
          TargetPlatform.iOS: _FadeThroughTransitions(),
          TargetPlatform.macOS: _FadeThroughTransitions(),
          TargetPlatform.windows: _FadeThroughTransitions(),
          TargetPlatform.linux: _FadeThroughTransitions(),
          TargetPlatform.fuchsia: _FadeThroughTransitions(),
        },
      ),

      dividerTheme: DividerThemeData(
        color: scheme.outlineVariant,
        thickness: Tokens.borderSm,
        space: Tokens.borderSm,
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(
          horizontal: Tokens.space4,
          vertical: Tokens.space1 + 2,
        ),
      ),

      dialogTheme: DialogThemeData(
        // Всплывающее в источнике — `bg-elevated` с глубокой тенью и без
        // обводки: обводка нужна тому, что лежит на полотне, а не над ним.
        backgroundColor: scheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(Tokens.br16)),
        ),
        titleTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 18,
          fontWeight: FontWeight.w600,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontFamily: _font,
          fontSize: 14,
          height: 1.5,
          color: scheme.onSurfaceVariant,
        ),
        insetPadding: const EdgeInsets.symmetric(
          horizontal: Tokens.space6 + 4,
          vertical: Tokens.space6,
        ),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerHighest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(Tokens.br16)),
        ),
      ),

      snackBarTheme: SnackBarThemeData(
        backgroundColor: scheme.inverseSurface,
        contentTextStyle: TextStyle(
          color: scheme.onInverseSurface,
          fontSize: 14,
        ),
        behavior: SnackBarBehavior.floating,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusShell),
        ),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
      // Чернильная волна Material чужая этому языку: нажатие показывается
      // ровной подсветкой.
      splashFactory: NoSplash.splashFactory,
    );
  }

  static OutlineInputBorder _inputBorder(
    Color color, {
    double width = Tokens.borderSm,
  }) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(Tokens.radiusInput),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  // --- Кнопки ---

  static const _buttonText = TextStyle(
    fontFamily: _font,
    fontSize: 15,
    fontWeight: FontWeight.w600,
    letterSpacing: -0.1,
  );

  /// Ровная подсветка вместо чернильной волны.
  static WidgetStateProperty<Color?> _overlay(Color base) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return base.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return base.withValues(alpha: 0.06);
      }
      return null;
    });
  }

  /// Кольцо фокуса с клавиатуры.
  ///
  /// Цвет передаётся отдельно: на акцентной кнопке кольцо того же акцента
  /// невидимо, и фокус пропадает совсем — там оно берёт цвет надписи.
  static WidgetStateProperty<BorderSide?> _focusRing(
    ColorScheme scheme, {
    required Color focus,
    required Color rest,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: focus, width: Tokens.borderLg);
      }
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: scheme.outlineVariant, width: Tokens.borderSm);
      }
      return BorderSide(color: rest, width: Tokens.borderSm);
    });
  }

  static ButtonStyle _primaryButton(ColorScheme scheme) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.surfaceContainerHigh;
        }
        // В источнике и наведение, и нажатие — `bg-accent/90`; нажатие
        // вдобавок сжимает кнопку, этим занимается сама кнопка.
        if (states.contains(WidgetState.pressed) ||
            states.contains(WidgetState.hovered)) {
          return Tokens.accentHover;
        }
        return Tokens.accent;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurfaceVariant;
        }
        return scheme.onPrimary;
      }),
      // Подсветка не нужна: цвет уже меняется самой заливкой.
      overlayColor: const WidgetStatePropertyAll(Colors.transparent),
      side: _focusRing(
        scheme,
        focus: scheme.onPrimary,
        rest: Colors.transparent,
      ),
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(48)),
      textStyle: const WidgetStatePropertyAll(_buttonText),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusShell),
        ),
      ),
      animationDuration: Tokens.duration,
    );
  }

  static ButtonStyle _secondaryButton(ColorScheme scheme) {
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurfaceVariant;
        }
        return scheme.onSurface;
      }),
      overlayColor: _overlay(scheme.onSurface),
      side: _focusRing(scheme, focus: Tokens.ring, rest: scheme.outline),
      minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
      textStyle: const WidgetStatePropertyAll(_buttonText),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusShell),
        ),
      ),
      animationDuration: Tokens.duration,
    );
  }

  static ButtonStyle _ghostButton(ColorScheme scheme) {
    return ButtonStyle(
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurfaceVariant;
        }
        return scheme.onSurface;
      }),
      overlayColor: _overlay(scheme.onSurface),
      side: _focusRing(
        scheme,
        focus: Tokens.ring,
        rest: Colors.transparent,
      ),
      minimumSize: const WidgetStatePropertyAll(Size(64, 44)),
      textStyle: const WidgetStatePropertyAll(_buttonText),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.radiusShell),
        ),
      ),
      animationDuration: Tokens.duration,
    );
  }

  /// Типографика.
  ///
  /// Одно семейство на всё, различие — в размере и насыщенности. Жирность
  /// заголовков 600, а не 700: в их интерфейсе заголовки плотные, но не
  /// чёрные, и отрицательный трекинг держит их собранными.
  static const _textTheme = TextTheme(
    headlineLarge: TextStyle(
      fontSize: 28,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.6,
      height: 1.2,
    ),
    headlineMedium: TextStyle(
      fontSize: 24,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.5,
      height: 1.2,
    ),
    headlineSmall: TextStyle(
      fontSize: 20,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.3,
      height: 1.25,
    ),
    titleLarge: TextStyle(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
    ),
    titleMedium: TextStyle(
      fontSize: 15,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.1,
    ),
    titleSmall: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(fontSize: 16, height: 1.5),
    bodyMedium: TextStyle(fontSize: 14, height: 1.5),
    bodySmall: TextStyle(fontSize: 13, height: 1.45),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    // Время, счётчики, статусы: цифры одной ширины, чтобы не прыгали.
    labelSmall: TextStyle(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      fontFeatures: tabularFigures,
    ),
  );

  // --- Готовые куски для экранов ---

  /// Цвет своего пузыря — подкрашен акцентом, как в источнике.
  static Color ownBubble(ColorScheme scheme) => Tokens.bubbleOut;

  /// Цвет чужого пузыря: нейтральный, едва заметнее полотна.
  static Color otherBubble(ColorScheme scheme) => Tokens.bubbleIn;

  /// Текст в пузыре — обычный: оба пузыря держат основной текст выше 8:1.
  static Color onOwnBubble(ColorScheme scheme) => scheme.onSurface;
}

/// Переход между экранами: проявление со сдвигом.
class _FadeThroughTransitions extends PageTransitionsBuilder {
  const _FadeThroughTransitions();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 0.012),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      ),
    );
  }
}
