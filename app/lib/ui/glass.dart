import 'package:flutter/material.dart';

import 'icons.dart';
import 'tokens.dart';

/// Панели поверх содержимого: шапки, поле ввода, модальные окна.
///
/// Раньше здесь было матовое стекло. Убрано после замера: в источнике
/// `backdrop-filter` и `blur()` не встречаются ни разу — все поверхности
/// плоские, с волосяной границей. Заодно ушла цена размытия: прокрутка
/// длинной ленты занимала 56 мс на кадр против 42 мс без него.
///
/// Имена файла и виджетов оставлены прежними: они про роль — «панель над
/// содержимым», — а не про эффект.
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    required this.child,
    this.borderSide = GlassBorder.bottom,
    this.borderRadius,
    super.key,
  });

  final Widget child;
  final GlassBorder borderSide;
  final BorderRadius? borderRadius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        // Цвет панели, а не полотна: в источнике шапки и поле ввода —
        // `bg-sidebar`, на полтона светлее того, над чем они стоят.
        color: scheme.surfaceContainer,
        borderRadius: borderRadius,
        border: switch (borderSide) {
          GlassBorder.none => null,
          GlassBorder.bottom => Border(
            bottom: BorderSide(
              color: scheme.outlineVariant,
              width: Tokens.borderSm,
            ),
          ),
          GlassBorder.top => Border(
            top: BorderSide(
              color: scheme.outlineVariant,
              width: Tokens.borderSm,
            ),
          ),
          GlassBorder.all => Border.all(
            color: scheme.outlineVariant,
            width: Tokens.borderSm,
          ),
        },
      ),
      child: child,
    );
  }
}

enum GlassBorder { none, bottom, top, all }

/// Шапка экрана.
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
                // Своя стрелка вместо материаловской: иначе в шапке окажется
                // иконка из чужого набора.
                leading: leading ?? const _BackButton(),
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

/// Кнопка «назад» из нашего набора.
///
/// Показывается только если есть куда возвращаться — на корневом экране
/// Flutter сам не рисует стрелку, и мы не должны.
class _BackButton extends StatelessWidget {
  const _BackButton();

  @override
  Widget build(BuildContext context) {
    if (!(ModalRoute.of(context)?.impliesAppBarDismissal ?? false)) {
      return const SizedBox.shrink();
    }
    return IconButton(
      icon: const Icon(TitoIcons.back),
      tooltip: MaterialLocalizations.of(context).backButtonTooltip,
      onPressed: () => Navigator.maybePop(context),
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

/// Модальное окно.
///
/// Затемнение без размытия — как в источнике. Появление за 200 мс,
/// единственная длительность перехода в его системе.
Future<T?> showGlassDialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
}) {
  final scheme = Theme.of(context).colorScheme;

  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: scheme.scrim.withValues(alpha: 0.32),
    transitionDuration: Tokens.duration,
    pageBuilder: (context, _, _) => builder(context),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.98, end: 1).animate(curved),
          child: child,
        ),
      );
    },
  );
}
