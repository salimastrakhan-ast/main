import 'package:flutter/material.dart';

/// Тема приложения.
///
/// Тёплая палитра: кремовое полотно, почти чёрный текст, коралловый акцент.
/// Поверхности плоские, разделяются тонкими границами, а не тенями — так глаз
/// цепляется за сообщения, а не за интерфейс вокруг них.
abstract final class MayakTheme {
  /// Матовое стекло на шапках, поле ввода и диалогах.
  ///
  /// Размытие обходится дорого на слабых Android и в вебе. Выключение не
  /// меняет раскладку: те же поверхности становятся непрозрачными.
  static const glassEnabled = true;

  // --- Палитра ---

  static const _cream = Color(0xFFFAF9F5);
  static const _ink = Color(0xFF141413);
  static const _coral = Color(0xFFD97757);
  static const _warm = Color(0xFFE8E6DC);
  static const _blue = Color(0xFF6A9BCC);
  static const _green = Color(0xFF788C5D);

  /// Серый для границ и разделителей.
  ///
  /// Только для форм. Как текст на кремовом он даёт 2.1:1 — нечитаемо;
  /// для второстепенного текста есть [_inkMuted].
  static const _stone = Color(0xFFB0AEA5);

  /// Второстепенный текст на светлой теме: 5.2:1 на кремовом.
  static const _inkMuted = Color(0xFF6B6960);

  /// Он же на тёмной: 7.1:1 на чернильном.
  static const _creamMuted = Color(0xFFA3A199);

  // Ступени поверхностей: полотно, поля ввода, чужие пузыри.
  static const _creamLow = Color(0xFFF7F5EF);
  static const _creamMid = Color(0xFFF2F0E8);
  static const _creamHigh = Color(0xFFEDEAE0);
  static const _hairline = Color(0xFFDEDBCF);

  static const _inkLow = Color(0xFF1A1A19);
  static const _inkMid = Color(0xFF1F1F1E);
  static const _inkHigh = Color(0xFF232322);
  static const _inkTop = Color(0xFF262624);
  static const _inkHairline = Color(0xFF33322F);
  static const _inkOutline = Color(0xFF55534D);

  /// Мягкие заливки аватаров.
  ///
  /// Насыщенные акценты на каждом аватаре превращали список в пёстрое
  /// полотно. Здесь те же три цвета, разбавленные кремовым: узнавание
  /// остаётся, шум уходит. Тёмный текст поверх даёт больше 10:1.
  static const _washCoral = Color(0xFFEBBEAE);
  static const _washBlue = Color(0xFFB9CFE3);
  static const _washGreen = Color(0xFFC0C8B1);

  /// Тёмные варианты акцентов — для имён отправителей.
  ///
  /// Насыщенные как текст не проходят: коралл на кремовом даёт 3.1:1.
  /// Эти дают не меньше 4.5:1 и на кремовом, и на белом пузыре.
  static const _textCoral = Color(0xFFC0502B);
  static const _textBlue = Color(0xFF3C76B0);
  static const _textGreen = Color(0xFF677850);

  static const _errorLight = Color(0xFFA33A2A);
  static const _errorDark = Color(0xFFE9A08F);

  // --- Шрифты ---

  /// Заголовки. Не Poppins из фирменного набора: у него нет кириллицы —
  /// проверено по таблице символов, «Привет» не отрисовалось бы ни одной
  /// буквой. Manrope того же геометрического склада и с полной кириллицей.
  static const _display = 'Manrope';

  /// Текст сообщений.
  static const _body = 'Roboto';

  /// Цифры и метки: время, счётчики, статусы. Моноширинные цифры не
  /// прыгают по ширине при каждом обновлении минуты.
  static const _mono = 'JetBrainsMono';

  /// Запасные семейства: если в Manrope не найдётся редкий символ, его
  /// подставит Roboto, а не безымянный системный шрифт.
  static const _fallback = [_body];

  static ThemeData light() => _build(_lightScheme);
  static ThemeData dark() => _build(_darkScheme);

  static const _lightScheme = ColorScheme(
    brightness: Brightness.light,
    primary: _coral,
    // Тёмный, а не белый: белый на коралле даёт 3.1:1 и не проходит.
    onPrimary: _ink,
    primaryContainer: Color(0xFFF6DDD2),
    onPrimaryContainer: _ink,
    secondary: _blue,
    onSecondary: _ink,
    secondaryContainer: Color(0xFFDCE7F2),
    onSecondaryContainer: _ink,
    tertiary: _green,
    onTertiary: _ink,
    tertiaryContainer: Color(0xFFE0E5D5),
    onTertiaryContainer: _ink,
    error: _errorLight,
    onError: _cream,
    errorContainer: Color(0xFFF5DAD4),
    onErrorContainer: Color(0xFF4A1710),
    surface: _cream,
    onSurface: _ink,
    surfaceDim: _creamHigh,
    surfaceBright: Color(0xFFFFFFFF),
    surfaceContainerLowest: Color(0xFFFFFFFF),
    surfaceContainerLow: _creamLow,
    surfaceContainer: _creamMid,
    surfaceContainerHigh: _creamHigh,
    surfaceContainerHighest: _warm,
    onSurfaceVariant: _inkMuted,
    outline: _stone,
    outlineVariant: _hairline,
    shadow: _ink,
    scrim: _ink,
    inverseSurface: _ink,
    onInverseSurface: _cream,
    inversePrimary: _coral,
  );

  static const _darkScheme = ColorScheme(
    brightness: Brightness.dark,
    primary: _coral,
    onPrimary: _ink,
    primaryContainer: Color(0xFF5C3226),
    onPrimaryContainer: Color(0xFFF6DDD2),
    secondary: _blue,
    onSecondary: _ink,
    secondaryContainer: Color(0xFF2C4257),
    onSecondaryContainer: Color(0xFFDCE7F2),
    tertiary: _green,
    onTertiary: _ink,
    tertiaryContainer: Color(0xFF3A452B),
    onTertiaryContainer: Color(0xFFE0E5D5),
    error: _errorDark,
    onError: Color(0xFF3A1009),
    errorContainer: Color(0xFF5F2318),
    onErrorContainer: Color(0xFFF5DAD4),
    surface: _ink,
    onSurface: _cream,
    surfaceDim: Color(0xFF0F0F0E),
    surfaceBright: _inkTop,
    surfaceContainerLowest: Color(0xFF0F0F0E),
    surfaceContainerLow: _inkLow,
    surfaceContainer: _inkMid,
    surfaceContainerHigh: _inkHigh,
    surfaceContainerHighest: _inkTop,
    onSurfaceVariant: _creamMuted,
    outline: _inkOutline,
    outlineVariant: _inkHairline,
    shadow: Color(0xFF000000),
    scrim: Color(0xFF000000),
    inverseSurface: _cream,
    onInverseSurface: _ink,
    inversePrimary: _coral,
  );

  static ThemeData _build(ColorScheme scheme) {
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      // Шрифты лежат в сборке. Иначе движок в вебе пойдёт за ними на чужой
      // CDN и до ответа не покажет ни кадра — замерено пятнадцать секунд.
      fontFamily: _body,
      fontFamilyFallback: _fallback,
      textTheme: _textTheme,
      scaffoldBackgroundColor: scheme.surface,

      // Плоско и с волосяной линией внизу вместо тени.
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        surfaceTintColor: Colors.transparent,
        foregroundColor: scheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        // Заголовок спокойнее прежнего: шапка обрамляет содержимое, а не
        // соревнуется с ним.
        titleTextStyle: TextStyle(
          fontFamily: _display,
          fontFamilyFallback: _fallback,
          fontSize: 17,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.2,
          color: scheme.onSurface,
        ),
        iconTheme: IconThemeData(color: scheme.onSurface, size: 22),
        actionsIconTheme: IconThemeData(
          color: scheme.onSurfaceVariant,
          size: 22,
        ),
        shape: Border(bottom: BorderSide(color: scheme.outlineVariant)),
      ),

      // Иконки тонкие и не чернее текста: в спокойном интерфейсе они
      // подсказка, а не акцент.
      iconTheme: IconThemeData(color: scheme.onSurfaceVariant, size: 22),

      // Поле ввода светлее полотна и очерчено волосяной линией: так оно
      // читается как отдельная поверхность, а не как вдавленная плашка.
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scheme.surfaceContainerLowest,
        hintStyle: TextStyle(color: scheme.onSurfaceVariant, fontSize: 15),
        border: _inputBorder(scheme.outlineVariant),
        enabledBorder: _inputBorder(scheme.outlineVariant),
        focusedBorder: _inputBorder(scheme.primary, width: 1.5),
        errorBorder: _inputBorder(scheme.error),
        focusedErrorBorder: _inputBorder(scheme.error, width: 1.5),
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 16,
          vertical: 15,
        ),
        // Иконки в поле тише текста: они подсказка, а не содержание.
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
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),

      // Переходы между экранами: проявление со сдвигом, одинаково на всех
      // платформах. Задаётся один раз и работает на каждом Navigator.push.
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
        thickness: 1,
        space: 1,
      ),

      listTileTheme: const ListTileThemeData(
        contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      ),

      dialogTheme: DialogThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        titleTextStyle: TextStyle(
          fontFamily: _display,
          fontFamilyFallback: _fallback,
          fontSize: 19,
          fontWeight: FontWeight.w700,
          color: scheme.onSurface,
        ),
        contentTextStyle: TextStyle(
          fontFamily: _body,
          fontSize: 14,
          height: 1.4,
          color: scheme.onSurfaceVariant,
        ),
        insetPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
      ),

      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: scheme.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),

      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: scheme.primary,
        linearTrackColor: scheme.surfaceContainerHigh,
      ),
      // Чернильная волна Material чужая этому языку: нажатие показывается
      // ровной подсветкой, как на кнопках claude.ai.
      splashFactory: NoSplash.splashFactory,
    );
  }

  // --- Кнопки ---
  //
  // Состояния задаются через WidgetStateProperty. Фокус с клавиатуры —
  // не украшение: без видимого кольца по приложению нельзя ходить табом,
  // а веб-клиент у нас есть.

  static const _buttonText = TextStyle(
    fontFamily: _display,
    fontFamilyFallback: _fallback,
    fontSize: 16,
    fontWeight: FontWeight.w700,
  );

  /// Ровная подсветка вместо чернильной волны.
  static WidgetStateProperty<Color?> _overlay(Color base) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed)) {
        return base.withValues(alpha: 0.14);
      }
      if (states.contains(WidgetState.hovered) ||
          states.contains(WidgetState.focused)) {
        return base.withValues(alpha: 0.07);
      }
      return null;
    });
  }

  /// Кольцо фокуса с клавиатуры.
  ///
  /// Цвет кольца задаётся отдельно от акцента: на коралловой кнопке
  /// коралловое кольцо невидимо, и фокус пропадает совсем. На заливке кольцо
  /// рисуется цветом текста, на светлом фоне — акцентом.
  static WidgetStateProperty<BorderSide?> _focusRing(
    ColorScheme scheme, {
    required Color focus,
    required Color rest,
  }) {
    return WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) {
        return BorderSide(color: focus, width: 2);
      }
      if (states.contains(WidgetState.disabled)) {
        return BorderSide(color: scheme.outlineVariant);
      }
      return BorderSide(color: rest);
    });
  }

  static ButtonStyle _primaryButton(ColorScheme scheme) {
    return ButtonStyle(
      backgroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.surfaceContainerHigh;
        }
        return scheme.primary;
      }),
      foregroundColor: WidgetStateProperty.resolveWith((states) {
        if (states.contains(WidgetState.disabled)) {
          return scheme.onSurfaceVariant;
        }
        return scheme.onPrimary;
      }),
      overlayColor: _overlay(scheme.onPrimary),
      side: _focusRing(
        scheme,
        focus: scheme.onPrimary,
        rest: Colors.transparent,
      ),
      elevation: const WidgetStatePropertyAll(0),
      minimumSize: const WidgetStatePropertyAll(Size.fromHeight(52)),
      textStyle: const WidgetStatePropertyAll(_buttonText),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
      side: _focusRing(scheme, focus: scheme.primary, rest: scheme.outline),
      minimumSize: const WidgetStatePropertyAll(Size(64, 46)),
      textStyle: const WidgetStatePropertyAll(_buttonText),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
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
      side: _focusRing(scheme, focus: scheme.primary, rest: Colors.transparent),
      minimumSize: const WidgetStatePropertyAll(Size(64, 46)),
      textStyle: const WidgetStatePropertyAll(_buttonText),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(14),
      borderSide: BorderSide(color: color, width: width),
    );
  }

  /// Типографика.
  ///
  /// Цвета здесь не задаются намеренно: их подставит схема, и одна и та же
  /// таблица работает в обеих темах.
  static const _textTheme = TextTheme(
    headlineLarge: TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fallback,
      fontSize: 30,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.5,
    ),
    headlineMedium: TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fallback,
      fontSize: 26,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
    ),
    headlineSmall: TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fallback,
      fontSize: 22,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.3,
    ),
    titleLarge: TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fallback,
      fontSize: 20,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.2,
    ),
    titleMedium: TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fallback,
      fontSize: 16,
      fontWeight: FontWeight.w700,
    ),
    titleSmall: TextStyle(
      fontFamily: _display,
      fontFamilyFallback: _fallback,
      fontSize: 14,
      fontWeight: FontWeight.w700,
    ),
    bodyLarge: TextStyle(fontSize: 16, height: 1.4),
    bodyMedium: TextStyle(fontSize: 14, height: 1.4),
    bodySmall: TextStyle(fontSize: 13, height: 1.35),
    labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
    labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
    // Время, счётчики, статусы.
    labelSmall: TextStyle(
      fontFamily: _mono,
      fontFamilyFallback: _fallback,
      fontSize: 11,
      fontWeight: FontWeight.w400,
      letterSpacing: 0,
    ),
  );

  // --- Готовые куски для экранов ---

  /// Цвет своего пузыря.
  ///
  /// Тёплый серый, а не коралл. Стена коралловых пузырей перетягивала на
  /// себя всё внимание; терракот теперь работает как редкий акцент —
  /// кнопка отправки, счётчик непрочитанного, знак приложения.
  ///
  /// Цвета заданы явно, а не через ступени поверхностей Material: в тёмной
  /// теме ступени идут в обратную сторону, и чужой пузырь оказался бы
  /// темнее полотна. Правило одно в обеих темах — свой пузырь плотнее
  /// полотна, чужой едва заметнее.
  static Color ownBubble(ColorScheme scheme) =>
      scheme.brightness == Brightness.light
      ? const Color(0xFFE8E6DC)
      : const Color(0xFF2E2D2B);

  /// Цвет чужого пузыря.
  static Color otherBubble(ColorScheme scheme) =>
      scheme.brightness == Brightness.light
      ? const Color(0xFFFFFFFF)
      : const Color(0xFF1C1C1A);

  /// Текст в пузыре — обычный, потому что оба пузыря нейтральные.
  static Color onOwnBubble(ColorScheme scheme) => scheme.onSurface;

  /// Мягкие заливки аватаров и тёмные акценты для имён — по одному индексу.
  static const _washes = [_washCoral, _washBlue, _washGreen];
  static const _textAccents = [_textCoral, _textBlue, _textGreen];

  /// Стабильный цвет аватара по идентификатору.
  ///
  /// Один и тот же человек всегда одного цвета: цвет работает как опознавание
  /// в списке, и меняться между запусками он не должен.
  static Color accentFor(String id) => _washes[_slot(id)];

  /// Цвет имени отправителя — тёмный вариант того же акцента, что у аватара.
  static Color textAccentFor(String id) => _textAccents[_slot(id)];

  static int _slot(String id) {
    var hash = 0;
    for (var i = 0; i < id.length; i++) {
      hash = (hash * 31 + id.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return hash % _washes.length;
  }

  /// Текст поверх заливки аватара.
  static const onAccent = _ink;

  /// Шрифт для цифр и меток, когда нужен явно.
  static const monoFamily = _mono;
  static const monoFallback = _fallback;
}

/// Переход между экранами: проявление со сдвигом на восемь пикселей.
///
/// Стандартный андроидный переход выезжает снизу на всю высоту и в этом
/// языке выглядит грубо. Здесь движение короткое и почти незаметное — так же
/// сдержанно, как в веб-интерфейсах Claude.
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
