import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../data/ws/ws_client.dart';
import '../../ui/icons.dart';
import '../../ui/glass.dart';
import '../../ui/state_view.dart';
import '../../ui/theme.dart';
import '../chat/chat_screen.dart';
import '../profile/profile_screen.dart';

/// Список диалогов.
class ChatsScreen extends ConsumerWidget {
  const ChatsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider);
    final peers = ref.watch(chatPeersProvider).value ?? const {};
    final lastMessages = ref.watch(lastMessagesProvider).value ?? const {};
    final session = ref.watch(sessionProvider).value;

    return Scaffold(
      // Карточки уезжают под шапку — тогда стекло размывает содержимое,
      // а не пустой фон.
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('Маяк'),
        bottomHeight: 20,
        bottom: const _ConnectionBanner(),
        actions: [
          IconButton(
            icon: const Icon(MayakIcons.profile),
            tooltip: 'Профиль',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ProfileScreen()),
            ),
          ),
        ],
      ),
      body: chats.when(
        loading: () => const StateView.loading(),
        error: (e, _) =>
            StateView.error(e, title: 'Не удалось загрузить диалоги'),
        data: (list) {
          if (list.isEmpty) return const _EmptyChats();
          return ListView.builder(
            padding: EdgeInsets.only(
              top: glassAppBarHeight(context, extra: 20 + 8),
              bottom: 16,
            ),
            itemCount: list.length,
            itemBuilder: (context, index) => _ChatTile(
              chat: list[index],
              peer: peers[list[index].id],
              lastMessage: lastMessages[list[index].id],
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
class _ConnectionBanner extends ConsumerWidget {
  const _ConnectionBanner();

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
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSecondaryContainer,
        ),
      ),
    );
  }
}

class _ChatTile extends StatelessWidget {
  const _ChatTile({
    required this.chat,
    required this.peer,
    required this.lastMessage,
    required this.myUserId,
  });

  final Chat chat;
  final User? peer;
  final LastMessage? lastMessage;
  final String myUserId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _title();

    return ListTile(
      leading: CircleAvatar(
        radius: 25,
        // Цвет закреплён за собеседником: в списке он работает как
        // опознавание, и меняться между запусками не должен. У группы
        // человека нет — там опознаётся сам чат.
        backgroundColor: MayakTheme.accentFor(peer?.id ?? chat.id),
        child: Text(
          title.isEmpty ? '?' : title.characters.first.toUpperCase(),
          style: const TextStyle(
            color: MayakTheme.onAccent,
            fontWeight: FontWeight.w700,
            fontSize: 18,
          ),
        ),
      ),
      title: Text(
        title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.titleMedium,
      ),
      subtitle: Text(
        _preview(),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
      ),
      trailing: chat.unreadCount > 0
          ? Container(
              constraints: const BoxConstraints(minWidth: 22),
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Text(
                '${chat.unreadCount}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            )
          : Text(
              DateFormat.Hm().format(chat.updatedAt),
              style: theme.textTheme.labelSmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
    return peer?.displayName ?? 'Чат';
  }

  /// Вторая строка: начало последнего сообщения — как в любом мессенджере.
  ///
  /// Пока сообщений нет, вместо пустоты пишем, что это за чат: строка без
  /// подписи выглядит наполовину не загрузившейся.
  String _preview() {
    final last = lastMessage;
    if (last == null) return chat.type == 'group' ? 'Группа' : 'Личный чат';
    if (last.deleted) return 'Сообщение удалено';

    final body = last.body.isEmpty ? 'Вложение' : last.body;
    return last.senderId == myUserId ? 'Вы: $body' : body;
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    return const StateView(
      icon: MayakIcons.chats,
      title: 'Пока пусто',
      description:
          'Диалог появится здесь, как только вам напишут или вы напишете первым.',
    );
  }
}
