import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/ws/ws_client.dart';
import '../../ui/icons.dart';
import '../../ui/glass.dart';
import '../../ui/theme.dart';

/// Профиль и выход.
class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider).value;
    final me = ref.watch(usersProvider).value?[session?.userId];
    final connection = ref.watch(connectionStateProvider).value;

    return Scaffold(
      appBar: AppBar(title: const Text('Профиль')),
      body: ListView(
        children: [
          const SizedBox(height: 16),
          Center(
            child: CircleAvatar(
              radius: 44,
              backgroundColor: MayakTheme.accentFor(session?.userId ?? ''),
              child: Text(
                (me?.displayName ?? '?').characters.first.toUpperCase(),
                style: theme.textTheme.headlineMedium?.copyWith(
                  color: MayakTheme.onAccent,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(
              me?.displayName ?? 'Профиль',
              style: theme.textTheme.titleLarge,
            ),
          ),
          if (me?.phone != null)
            Center(
              child: Text(
                '+${me!.phone}',
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 13,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          const SizedBox(height: 24),
          ListTile(
            leading: Icon(
              connection == WsStatus.online
                  ? MayakIcons.online
                  : MayakIcons.offline,
            ),
            title: const Text('Соединение'),
            subtitle: Text(switch (connection) {
              WsStatus.online => 'На связи',
              WsStatus.connecting => 'Подключение…',
              _ => 'Нет сети',
            }),
          ),
          const Divider(),
          ListTile(
            leading: Icon(MayakIcons.logout, color: theme.colorScheme.error),
            title: Text(
              'Выйти',
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showGlassDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text(
          'Переписка останется на сервере, но с этого устройства будет удалена.',
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
