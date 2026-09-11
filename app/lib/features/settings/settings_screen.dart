import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/ws/ws_client.dart';
import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/tokens.dart';
import 'account_screen.dart';
import 'appearance_screen.dart';

/// Настройки.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider).value;
    final me = ref.watch(usersProvider).value?[session?.userId];
    final connection = ref.watch(connectionStateProvider).value;
    final mode = ref.watch(themeModeProvider).value ?? ThemeMode.system;

    return Scaffold(
      appBar: const GlassAppBar(
        title: Text('Настройки'),
        leading: SizedBox.shrink(),
      ),
      body: ListView(
        children: [
          const SizedBox(height: Tokens.space5),
          Center(
            child: PersonAvatar(
              id: session?.userId ?? '',
              name: me?.displayName ?? '?',
              radius: 44,
              online: connection == WsStatus.online,
            ),
          ),
          const SizedBox(height: Tokens.space4),
          Center(
            child: Text(
              me?.displayName ?? '',
              style: theme.textTheme.titleLarge,
            ),
          ),
          const SizedBox(height: Tokens.space1),
          Center(
            child: Text(
              switch (connection) {
                WsStatus.online => 'в сети',
                WsStatus.connecting => 'соединение…',
                _ => 'нет сети',
              },
              style: theme.textTheme.bodySmall?.copyWith(
                color: connection == WsStatus.online
                    ? Tokens.olive
                    : theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: Tokens.space6),
          SettingsRow(
            icon: MayakIcons.account,
            title: 'Аккаунт',
            subtitle: me?.phone ?? 'Номер телефона',
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AccountScreen()),
            ),
          ),
          SettingsRow(
            icon: MayakIcons.bell,
            title: 'Уведомления',
            subtitle: 'Звуки, вибрация, предпросмотр',
            onTap: () => showNotReady(context, 'Настройки уведомлений'),
          ),
          SettingsRow(
            icon: MayakIcons.privacy,
            title: 'Конфиденциальность',
            subtitle: 'Кто видит мой профиль, чаты',
            onTap: () => showNotReady(context, 'Настройки приватности'),
          ),
          SettingsRow(
            icon: MayakIcons.storage,
            title: 'Данные и хранилище',
            subtitle: 'Использование сети, автозагрузка',
            onTap: () => showNotReady(context, 'Управление хранилищем'),
          ),
          SettingsRow(
            icon: MayakIcons.appearance,
            title: 'Внешний вид',
            subtitle: switch (mode) {
              ThemeMode.light => 'Светлая тема',
              ThemeMode.dark => 'Тёмная тема',
              ThemeMode.system => 'Как в системе',
            },
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const AppearanceScreen()),
            ),
          ),
          SettingsRow(
            icon: MayakIcons.language,
            title: 'Язык',
            subtitle: 'Русский',
            onTap: () => showNotReady(context, 'Другие языки'),
          ),
          SettingsRow(
            icon: MayakIcons.help,
            title: 'Помощь',
            subtitle: 'Вопросы и поддержка',
            onTap: () => showNotReady(context, 'Справка'),
          ),
          const SizedBox(height: Tokens.space3),
          const RowDivider(indent: 0),
          SettingsRow(
            icon: MayakIcons.logout,
            title: 'Выйти',
            danger: true,
            onTap: () => _signOut(context, ref),
          ),
          const SizedBox(height: Tokens.space6),
        ],
      ),
    );
  }

  Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text(
          'Переписка останется на сервере, но с этого устройства '
          'будет удалена.',
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            // Кнопка в диалоге не должна растягиваться на всю ширину, как
            // главная кнопка на экране входа.
            style: FilledButton.styleFrom(minimumSize: const Size(96, 46)),
            child: const Text('Выйти'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    await ref.read(apiProvider).logout();
    // Локальные данные стираем: устройство может быть общим.
    await ref.read(databaseProvider).clearAll();
    ref.invalidate(sessionProvider);
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }
}
