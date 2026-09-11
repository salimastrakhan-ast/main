import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/tokens.dart';

/// Внешний вид: выбор темы.
///
/// Выбор сохраняется в локальной базе и применяется сразу — приложение
/// подписано на ту же настройку, что здесь пишется.
class AppearanceScreen extends ConsumerWidget {
  const AppearanceScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return Scaffold(
      appBar: const GlassAppBar(title: Text('Внешний вид')),
      body: ListView(
        children: [
          const SectionLabel('Тема'),
          _Choice(
            icon: MayakIcons.settings,
            title: 'Как в системе',
            subtitle: 'Меняется вместе с настройками устройства',
            selected: mode == ThemeMode.system,
            onTap: () => setThemeMode(ref, ThemeMode.system),
          ),
          _Choice(
            icon: MayakIcons.themeLight,
            title: 'Светлая',
            selected: mode == ThemeMode.light,
            onTap: () => setThemeMode(ref, ThemeMode.light),
          ),
          _Choice(
            icon: MayakIcons.themeDark,
            title: 'Тёмная',
            selected: mode == ThemeMode.dark,
            onTap: () => setThemeMode(ref, ThemeMode.dark),
          ),
          const SectionLabel('Прочее'),
          SettingsRow(
            icon: MayakIcons.appearance,
            title: 'Размер текста',
            subtitle: 'Как в системе',
            onTap: () => showNotReady(context, 'Настройка размера текста'),
          ),
          SettingsRow(
            icon: MayakIcons.image,
            title: 'Фон переписки',
            subtitle: 'Однотонный',
            onTap: () => showNotReady(context, 'Выбор фона'),
          ),
        ],
      ),
    );
  }
}

class _Choice extends StatelessWidget {
  const _Choice({
    required this.icon,
    required this.title,
    required this.selected,
    required this.onTap,
    this.subtitle,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return SettingsRow(
      icon: icon,
      title: title,
      subtitle: subtitle,
      onTap: onTap,
      trailing: selected
          ? Icon(MayakIcons.sent, size: 20, color: scheme.primary)
          : const SizedBox(width: Tokens.space5),
    );
  }
}
