import 'dart:ui';

import 'package:flutter/material.dart';

import 'theme.dart';

/// Матовое стекло: размытая полупрозрачная поверхность.
///
/// Работает только там, где под поверхностью реально проезжает содержимое.
/// Над пустым фоном размывать нечего — получится матовая плашка с полной
/// ценой по производительности, поэтому экраны специально перестроены так,
/// чтобы лента уходила под шапку и под поле ввода.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.borderSide = GlassBorder.bottom,
    this.borderRadius,
    this.opacity = 0.72,
    super.key,
  });

  final Widget child;
  final GlassBorder borderSide;
  final BorderRadius? borderRadius;

  /// Плотность заливки поверх размытия.
  ///
  /// Ниже 0.7 текст на шапке перестаёт читаться над пёстрым содержимым —
  /// на коралловых пузырях это заметно сразу.
  final double opacity;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final decoration = BoxDecoration(
      color: scheme.surface.withValues(
        alpha: MayakTheme.glassEnabled ? opacity : 1,
      ),
      borderRadius: borderRadius,
      border: switch (borderSide) {
        GlassBorder.none => null,
        GlassBorder.bottom => Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
        GlassBorder.top => Border(
          top: BorderSide(color: scheme.outlineVariant),
        ),
        GlassBorder.all => Border.all(color: scheme.outlineVariant),
      },
    );

    // Запасной путь: та же раскладка, просто без размытия. Раскладка обязана
    // совпадать — иначе пришлось бы поддерживать две вёрстки, и вторая
    // неизбежно отстала бы.
    if (!MayakTheme.glassEnabled) {
      return DecoratedBox(decoration: decoration, child: child);
    }

    // RepaintBoundary не даёт перерисовке списка тянуть за собой пересчёт
    // размытия на каждом кадре прокрутки.
    return RepaintBoundary(
      child: ClipRRect(
        // Без обрезки размытие растекается за пределы виджета на весь слой.
        borderRadius: borderRadius ?? BorderRadius.zero,
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: DecoratedBox(decoration: decoration, child: child),
        ),
      ),
    );
  }
}

enum GlassBorder { none, bottom, top, all }

/// Шапка на стекле.
///
/// Обычный [AppBar] поверх прозрачного фона, обёрнутый в [GlassSurface].
/// Экран при этом должен стоять с `extendBodyBehindAppBar: true`.
class GlassAppBar extends StatelessWidget implements PreferredSizeWidget {
  const GlassAppBar({
    required this.title,
    this.actions,
    this.leading,
    this.bottomHeight = 0,
    this.bottom,
    super.key,
  });

  final Widget title;
  final List<Widget>? actions;
  final Widget? leading;
  final double bottomHeight;
  final Widget? bottom;

  @override
  Size get preferredSize => Size.fromHeight(kToolbarHeight + bottomHeight);

  @override
  Widget build(BuildContext context) {
    return GlassSurface(
      child: SafeArea(
        bottom: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              height: kToolbarHeight,
              child: AppBar(
                title: title,
                actions: actions,
                leading: leading,
                backgroundColor: Colors.transparent,
                surfaceTintColor: Colors.transparent,
                elevation: 0,
                scrolledUnderElevation: 0,
                // Границу рисует GlassSurface, иначе их будет две.
                shape: const Border(),
              ),
            ),
            if (bottom != null) bottom!,
          ],
        ),
      ),
    );
  }
}

/// Высота шапки вместе с системной строкой состояния.
///
/// Нужна для отступа сверху у списка: тот уезжает под шапку, и без отступа
/// первый элемент окажется под ней.
double glassAppBarHeight(BuildContext context, {double extra = 0}) {
  return kToolbarHeight + MediaQuery.paddingOf(context).top + extra;
}

/// Диалог на стекле: фон за ним по-настоящему размывается.
///
/// Обычный showDialog рисует под окном сплошную заливку. Здесь в барьер
/// добавлен BackdropFilter, поэтому приложение позади видно сквозь стекло —
/// тот же язык, что у шапок.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final scheme = Theme.of(context).colorScheme;

  if (!MayakTheme.glassEnabled) {
    return showDialog<T>(context: context, builder: builder);
  }

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    // Заливка мягче стандартной: размытие само по себе отделяет окно от фона.
    barrierColor: scheme.scrim.withValues(alpha: 0.28),
    transitionDuration: const Duration(milliseconds: 180),
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return BackdropFilter(
        filter: ImageFilter.blur(
          sigmaX: 14 * curved.value,
          sigmaY: 14 * curved.value,
        ),
        child: FadeTransition(
          opacity: curved,
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.97, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}
