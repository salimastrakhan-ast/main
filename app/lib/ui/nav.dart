import 'package:flutter/material.dart';

import 'tokens.dart';

/// Раздел приложения в панели навигации.
class NavItem {
  const NavItem({required this.icon, required this.label});

  final IconData icon;
  final String label;
}

/// Панель разделов.
///
/// Своя, а не `NavigationBar` из Material: у того под выбранным значком
/// лежит таблетка-подложка, которой в нашем оформлении нет нигде больше.
/// Здесь выбранное отмечено только цветом — так же, как выбранная вкладка
/// в остальном интерфейсе.
class TitoNavBar extends StatelessWidget {
  const TitoNavBar({
    required this.items,
    required this.index,
    required this.onSelect,
    super.key,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant, width: Tokens.borderSm),
        ),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 56,
          child: Row(
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _BarItem(
                    item: items[i],
                    selected: i == index,
                    onTap: () => onSelect(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BarItem extends StatelessWidget {
  const _BarItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = selected
        ? theme.colorScheme.primary
        : theme.colorScheme.onSurfaceVariant;

    return Semantics(
      button: true,
      selected: selected,
      label: item.label,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(item.icon, size: 22, color: color),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: color,
                fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Та же навигация для широкого экрана — узкой полосой слева.
///
/// На планшете и в браузере нижняя панель уезжает к краю экрана, до неё
/// далеко тянуться, и место под неё всё равно отнимается по всей ширине.
class TitoNavRail extends StatelessWidget {
  const TitoNavRail({
    required this.items,
    required this.index,
    required this.onSelect,
    this.header,
    super.key,
  });

  final List<NavItem> items;
  final int index;
  final ValueChanged<int> onSelect;
  final Widget? header;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          right: BorderSide(
            color: scheme.outlineVariant,
            width: Tokens.borderSm,
          ),
        ),
      ),
      child: SafeArea(
        right: false,
        child: SizedBox(
          width: 72,
          child: Column(
            children: [
              if (header != null) ...[
                const SizedBox(height: Tokens.space4),
                header!,
                const SizedBox(height: Tokens.space4),
              ] else
                const SizedBox(height: Tokens.space5),
              for (var i = 0; i < items.length; i++)
                _RailItem(
                  item: items[i],
                  selected: i == index,
                  onTap: () => onSelect(i),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final NavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Tokens.space3,
        vertical: Tokens.space1,
      ),
      child: Semantics(
        button: true,
        selected: selected,
        label: item.label,
        child: Tooltip(
          message: item.label,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(Tokens.radiusShell),
            child: Container(
              height: 44,
              decoration: BoxDecoration(
                // На рейке подписей нет, поэтому одного цвета мало:
                // без подложки непонятно, какой раздел открыт.
                color: selected ? scheme.secondaryContainer : null,
                borderRadius: BorderRadius.circular(Tokens.radiusShell),
              ),
              child: Icon(
                item.icon,
                size: 22,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
