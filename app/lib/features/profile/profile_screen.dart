import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/ws/ws_client.dart';

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
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Icon(Icons.person,
                  size: 44, color: theme.colorScheme.onPrimaryContainer),
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text(me?.displayName ?? 'Профиль',
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w600)),
          ),
          if (me?.phone != null)
            Center(
              child: Text('+${me!.phone}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
            ),
          const SizedBox(height: 24),
          ListTile(
            leading: Icon(
              connection == WsStatus.online
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_off_outlined,
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
            leading: Icon(Icons.logout, color: theme.colorScheme.error),
            title: Text('Выйти', style: TextStyle(color: theme.colorScheme.error)),
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Выйти из аккаунта?'),
        content: const Text(
          'Переписка останется на сервере, но с этого устройства будет удалена.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
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
