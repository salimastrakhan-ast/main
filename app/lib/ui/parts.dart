import 'package:flutter/material.dart';

import 'icons.dart';
import 'theme.dart';
import 'tokens.dart';

/// Кружок с буквой и точкой присутствия.
///
/// Один виджет на все экраны: в списке диалогов, в контактах, в шапке
/// переписки и в сведениях о чате он обязан выглядеть одинаково, иначе
/// одного и того же человека узнаёшь заново на каждом экране.
class PersonAvatar extends StatelessWidget {
  const PersonAvatar({
    required this.id,
    required this.name,
    this.radius = 24,
    this.online = false,
    this.icon,
    super.key,
  });

  final String id;
  final String name;
  final double radius;
  final bool online;

  /// Значок вместо буквы — для групп.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SizedBox(
      width: radius * 2,
      height: radius * 2,
      child: Stack(
        children: [
          CircleAvatar(
            radius: radius,
            backgroundColor: MayakTheme.accentFor(id),
            child: icon != null
                ? Icon(
                    icon,
                    size: radius * 0.9,
                    color: MayakTheme.onAccent,
                  )
                : Text(
                    name.isEmpty ? '?' : name.characters.first.toUpperCase(),
                    style: TextStyle(
                      color: MayakTheme.onAccent,
                      fontWeight: FontWeight.w700,
                      fontSize: radius * 0.72,
                    ),
                  ),
          ),
          if (online)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                width: radius * 0.46,
                height: radius * 0.46,
                decoration: BoxDecoration(
                  color: Tokens.olive,
                  shape: BoxShape.circle,
                  // Кольцо цветом полотна: без него точка сливается с
                  // аватаром, когда тот светлый.
                  border: Border.all(color: scheme.surface, width: 2),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Поле поиска в шапке.
class SearchField extends StatelessWidget {
  const SearchField({
    required this.hint,
    this.controller,
    this.onChanged,
    this.onTap,
    this.readOnly = false,
    this.autofocus = false,
    super.key,
  });

  final String hint;
  final TextEditingController? controller;
  final ValueChanged<String>? onChanged;
  final VoidCallback? onTap;
  final bool readOnly;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return TextField(
      controller: controller,
      onChanged: onChanged,
      onTap: onTap,
      readOnly: readOnly,
      autofocus: autofocus,
      textInputAction: TextInputAction.search,
      decoration: InputDecoration(
        hintText: hint,
        isDense: true,
        prefixIcon: Icon(
          MayakIcons.search,
          size: 18,
          color: scheme.onSurfaceVariant,
        ),
        prefixIconConstraints: const BoxConstraints(minWidth: 40),
        suffixIcon: controller != null && controller!.text.isNotEmpty
            ? IconButton(
                icon: const Icon(MayakIcons.close, size: 16),
                tooltip: 'Очистить',
                onPressed: () {
                  controller!.clear();
                  onChanged?.call('');
                },
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Tokens.space3,
          vertical: 10,
        ),
      ),
    );
  }
}

/// Ряд фильтров-пилюль.
class FilterChipsRow extends StatelessWidget {
  const FilterChipsRow({
    required this.labels,
    required this.index,
    required this.onSelect,
    super.key,
  });

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
        itemCount: labels.length,
        separatorBuilder: (_, _) => const SizedBox(width: Tokens.space2),
        itemBuilder: (context, i) {
          final selected = i == index;
          return GestureDetector(
            onTap: () => onSelect(i),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
              decoration: BoxDecoration(
                color: selected
                    ? theme.colorScheme.primary
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(Tokens.radiusShell),
              ),
              child: Text(
                labels[i],
                style: theme.textTheme.labelLarge?.copyWith(
                  color: selected
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onSurfaceVariant,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Строка раздела настроек: значок, название, пояснение, стрелка.
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.danger = false,
    super.key,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  /// Опасное действие — выход, удаление. Красным и без стрелки.
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = danger ? theme.colorScheme.error : theme.colorScheme.onSurface;

    return ListTile(
      onTap: onTap,
      leading: Icon(
        icon,
        size: 20,
        color: danger ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
      ),
      title: Text(title, style: theme.textTheme.bodyLarge?.copyWith(color: color)),
      subtitle: subtitle == null
          ? null
          : Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
      trailing: trailing ??
          (danger || onTap == null
              ? null
              : Icon(
                  MayakIcons.forward,
                  size: 18,
                  color: theme.colorScheme.outline,
                )),
    );
  }
}

/// Заголовок группы строк.
class SectionLabel extends StatelessWidget {
  const SectionLabel(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Tokens.space4,
        Tokens.space5,
        Tokens.space4,
        Tokens.space2,
      ),
      child: Text(
        text,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// Тонкая черта между строками списка — с отступом под текст, как у них.
class RowDivider extends StatelessWidget {
  const RowDivider({this.indent = 56, super.key});

  final double indent;

  @override
  Widget build(BuildContext context) {
    return Divider(
      height: Tokens.borderSm,
      thickness: Tokens.borderSm,
      indent: indent,
      color: Theme.of(context).colorScheme.outlineVariant,
    );
  }
}

/// Сообщает, что раздел ещё не сделан.
///
/// Честнее пустой кнопки, которая молча ничего не делает: человек видит, что
/// нажатие дошло, и что дело не в нём.
void showNotReady(BuildContext context, String what) {
  ScaffoldMessenger.of(context)
    ..clearSnackBars()
    ..showSnackBar(SnackBar(content: Text('$what появятся в следующей версии')));
}
