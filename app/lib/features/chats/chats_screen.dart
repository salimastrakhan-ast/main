import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../data/ws/ws_client.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';

/// Список диалогов.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider);
    final users = ref.watch(usersProvider).value ?? const {};
    final session = ref.watch(sessionProvider).value;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Маяк'),
        bottom: const _ConnectionBanner(),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline),
            tooltip: 'Профиль',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      body: chats.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Ошибка: $e')),
        data: (list) {
          if (list.isEmpty) return const _EmptyChats();
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) => _ChatTile(
              chat: list[index],
              users: users,
              myUserId: session?.userId ?? '',
            ),
          );
        },
      ),
    );
  }
}

/// Полоса состояния связи.
///
/// В мессенджере молчание двусмысленно: непонятно, никто не пишет или связь
/// пропала. Полоса снимает этот вопрос.
class _ConnectionBanner extends ConsumerWidget implements PreferredSizeWidget {
  const _ConnectionBanner();

  @override
  Size get preferredSize => const Size.fromHeight(20);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(connectionStateProvider).value;
    if (state == null || state == WsStatus.online) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final connecting = state == WsStatus.connecting;
    return Container(
      width: double.infinity,
      height: 20,
      color: theme.colorScheme.secondaryContainer,
      alignment: Alignment.center,
      child: Text(
        connecting ? 'Соединение…' : 'Нет сети',
        style: theme.textTheme.labelSmall
            ?.copyWith(color: theme.colorScheme.onSecondaryContainer),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.users,
    required this.myUserId,
  });

  final Chat chat;
  final Map<String, User> users;
  final String myUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _title();

    return ListTile(
      leading: CircleAvatar(
        radius: 26,
        backgroundColor: theme.colorScheme.primaryContainer,
        child: Text(
          title.isEmpty ? '?' : title.characters.first.toUpperCase(),
          style: TextStyle(
            color: theme.colorScheme.onPrimaryContainer,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
      ),
      title: Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        chat.type == 'group' ? 'Группа' : 'Личный чат',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: chat.unreadCount > 0
          ? Badge(
              label: Text('${chat.unreadCount}'),
              backgroundColor: theme.colorScheme.primary,
            )
          : Text(
              DateFormat.Hm().format(chat.updatedAt),
              style: theme.textTheme.labelSmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChatScreen(chatId: chat.id, title: title),
        ),
      ),
    );
  }

  /// У группы есть название, а у личного чата его нет: там заголовок —
  /// это имя собеседника.
  String _title() {
    if (chat.title.isNotEmpty) return chat.title;
    for (final user in users.values) {
      if (user.id != myUserId) return user.displayName;
    }
    return 'Чат';
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.forum_outlined,
                size: 64, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 16),
            Text('Пока пусто',
                style: theme.textTheme.titleMedium
                    ?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Диалог появится здесь, как только вам напишут\nили вы напишете первым.',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
