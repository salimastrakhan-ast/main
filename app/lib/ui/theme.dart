import 'package:flutter/material.dart';

import 'tokens.dart';

/// Тема приложения.
///
/// Построена на [Tokens] — значениях, снятых с публичного CSS claude.com.
/// Плоские поверхности, волосяные границы, очень мягкие тени, один акцент.
abstract final class TitoTheme {
  // --- Шрифты ---

  /// Один шрифт на весь интерфейс.
  ///
  /// В их системе три семейства — anthropicSans, Serif и Mono, — но это
  /// лицензионные шрифты, и поставлять их в чужом приложении нельзя. Их
  /// собственный запасной вариант прописан там же: system-ui. Он и взят.
  ///
  /// На телефонах это родной шрифт системы. В вебе движок не умеет взять
  /// системный шрифт, не сходив за Roboto на чужой CDN — замерено
  /// пятнадцать секунд белого экрана, — поэтому Roboto лежит в сборке. Он
  /// же и есть системный шрифт Android, так что подмена честная.
  static const _font = 'Roboto';

  /// Цифры одной ширины.
  ///
  /// Заменяют отдельный моноширинный шрифт: время и счётчики не прыгают при
  /// обновлении минуты, а в сборке на два семейства меньше.
  static const tabularFigures = [FontFeature.tabularFigures()];

  static ThemeData light() => _build(_lightScheme);
  static ThemeData dark() => _build(_darkScheme);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: Tokens.clay,
    // Тёмный, а не белый: белый на clay даёт 3.1:1 и не проходит.
    onPrimary: Tokens.gray950,
    primaryContainer: Color(0xFFF6DDD2),
    onPrimaryContainer: Tokens.gray950,
    secondary: Tokens.sky,
    onSecondary: Tokens.gray950,
    secondaryContainer: Color(0xFFDCE7F2),
    onSecondaryContainer: Tokens.gray950,
    tertiary: Tokens.olive,
    onTertiary: Tokens.gray950,
    tertiaryContainer: Color(0xFFE0E5D5),
    onTertiaryContainer: Tokens.gray950,
    error: Tokens.error,
    onError: Tokens.gray000,
    errorContainer: Color(0xFFF5DAD4),
    onErrorContainer: Color(0xFF4A1710),
    surface: Tokens.gray050,
    onSurface: Tokens.gray950,
    surfaceDim: Tokens.gray150,
    surfaceBright: Tokens.gray000,
    surfaceContainerLowest: Tokens.gray000,
    surfaceContainerLow: Tokens.gray100,
    surfaceContainer: Tokens.gray150,
    surfaceContainerHigh: Tokens.gray200,
    surfaceContainerHighest: Tokens.gray250,
    // gray-550 даёт 5.3:1 на полотне. Сам gray-400 как текст — 2.1:1,
    // он годится только для границ.
    onSurfaceVariant: Tokens.gray550,
    outline: Tokens.gray350,
    outlineVariant: Tokens.gray250,
    shadow: Tokens.gray1000,
    scrim: Tokens.gray1000,
    inverseSurface: Tokens.gray950,
    onInverseSurface: Tokens.gray050,
    inversePrimary: Tokens.clay,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: Tokens.clay,
    onPrimary: Tokens.gray950,
    primaryContainer: Color(0xFF5C3226),
    onPrimaryContainer: Color(0xFFF6DDD2),
    secondary: Tokens.sky,
    onSecondary: Tokens.gray950,
    secondaryContainer: Color(0xFF2C4257),
    onSecondaryContainer: Color(0xFFDCE7F2),
    tertiary: Tokens.olive,
    onTertiary: Tokens.gray950,
    tertiaryContainer: Color(0xFF3A452B),
    onTertiaryContainer: Color(0xFFE0E5D5),
    error: Color(0xFFE9A08F),
    onError: Color(0xFF3A1009),
    errorContainer: Color(0xFF5F2318),
    onErrorContainer: Color(0xFFF5DAD4),
    surface: Tokens.gray950,
    onSurface: Tokens.gray050,
    surfaceDim: Tokens.gray1000,
    surfaceBright: Tokens.gray800,
    surfaceContainerLowest: Tokens.gray1000,
    surfaceContainerLow: Tokens.gray900,
    surfaceContainer: Tokens.gray850,
    surfaceContainerHigh: Tokens.gray800,
    surfaceContainerHighest: Tokens.gray750,
    onSurfaceVariant: Tokens.gray400,
    outline: Tokens.gray650,
    outlineVariant: Tokens.gray750,
    shadow: Tokens.gray1000,
    scrim: Tokens.gray1000,
    inverseSurface: Tokens.gray050,
    onInverseSurface: Tokens.gray950,
    inversePrimary: Tokens.clay,
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
        fillColor: scheme.surfaceContainerLowest,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
        border: _inputBorder(scheme.outlineVariant),
        enabledBorder: _inputBorder(scheme.outlineVariant),
        // Кольцо фокуса — их цвет focus, он же clay-dark.
        focusedBorder: _inputBorder(Tokens.clayDark, width: Tokens.borderMd),
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
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Tokens.br16),
          side: BorderSide(
            color: scheme.outlineVariant,
            width: Tokens.borderSm,
          ),
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
        backgroundColor: scheme.surfaceContainerLowest,
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
  /// Цвет задаётся отдельно от акцента: на кнопке цвета clay кольцо того же
  /// clay невидимо, и фокус пропадает совсем.
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
        // Их же значения для наведения и нажатия.
        if (states.contains(WidgetState.pressed)) return Tokens.clayDark;
        if (states.contains(WidgetState.hovered)) return Tokens.clayHover;
        return Tokens.clay;
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
      side: _focusRing(scheme, focus: Tokens.clayDark, rest: scheme.outline),
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
        focus: Tokens.clayDark,
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

  /// Цвет своего пузыря: плотнее полотна.
  static Color ownBubble(ColorScheme scheme) =>
      scheme.brightness == Brightness.light ? Tokens.gray200 : Tokens.gray800;

  /// Цвет чужого пузыря: едва заметнее полотна.
  static Color otherBubble(ColorScheme scheme) =>
      scheme.brightness == Brightness.light ? Tokens.gray000 : Tokens.gray850;

  /// Текст в пузыре — обычный, оба пузыря нейтральные.
  static Color onOwnBubble(ColorScheme scheme) => scheme.onSurface;

  /// Мягкие заливки аватаров: те же акценты, разбавленные полотном.
  static const _washes = [
    Color(0xFFEBBEAE),
    Color(0xFFB9CFE3),
    Color(0xFFC0C8B1),
  ];

  /// Тёмные варианты акцентов для имён: насыщенные как текст не проходят по
  /// контрасту, эти дают не меньше 4.5:1.
  static const _textAccents = [
    Color(0xFFC0502B),
    Color(0xFF3C76B0),
    Color(0xFF677850),
  ];

  /// Цвет аватара, закреплённый за человеком.
  static Color accentFor(String id) => _washes[_slot(id)];

  /// Цвет имени отправителя — тёмный вариант того же акцента.
  static Color textAccentFor(String id) => _textAccents[_slot(id)];

  static int _slot(String id) {
    var hash = 0;
    for (var i = 0; i < id.length; i++) {
      hash = (hash * 31 + id.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash % _washes.length;
  }

  /// Текст поверх заливки аватара.
  static const onAccent = Tokens.gray950;
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
