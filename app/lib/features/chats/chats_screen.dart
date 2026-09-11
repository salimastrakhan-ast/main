import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../data/ws/ws_client.dart';
import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/state_view.dart';
import '../../ui/tokens.dart';
import '../chat/chat_screen.dart';
import '../search/search_screen.dart';
import 'new_chat_screen.dart';

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
      appBar: GlassAppBar(
        title: const Text('Сообщения'),
        leading: const SizedBox.shrink(),
        bottomHeight: 44 + Tokens.space3 + 20,
        bottom: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.space4,
                0,
                Tokens.space4,
                Tokens.space3,
              ),
              // Поле только открывает поиск: искать по всему сразу удобнее
              // на отдельном экране, где есть вкладки и клавиатура не
              // перекрывает результаты.
              child: SearchField(
                hint: 'Поиск',
                readOnly: true,
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const SearchScreen()),
                ),
              ),
            ),
            const _ConnectionBanner(),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(TitoIcons.compose, size: 20),
            tooltip: 'Новый чат',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NewChatScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(TitoIcons.menu, size: 20),
            tooltip: 'Ещё',
            onPressed: () => showNotReady(context, 'Дополнительные действия'),
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
            padding: const EdgeInsets.only(top: Tokens.space2, bottom: 16),
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
      return const SizedBox(height: 20);
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

  bool get _isGroup => chat.type == 'group';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = _title();
    final unread = chat.unreadCount > 0;

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Tokens.space4,
        vertical: Tokens.space1,
      ),
      leading: PersonAvatar(
        id: peer?.id ?? chat.id,
        name: title,
        online: peer?.online ?? false,
        icon: _isGroup ? TitoIcons.contacts : null,
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
        style: theme.textTheme.bodyMedium?.copyWith(
          color: unread
              ? theme.colorScheme.onSurface
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Text(
            _time(chat.updatedAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: unread
                  ? theme.colorScheme.primary
                  : theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 5),
          if (unread)
            Container(
              constraints: const BoxConstraints(minWidth: 20),
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '${chat.unreadCount}',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onPrimary,
                  fontWeight: FontWeight.w600,
                ),
              ),
            )
          else
            const SizedBox(height: 18),
        ],
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
    if (last == null) return _isGroup ? 'Группа' : 'Личный чат';
    if (last.deleted) return 'Сообщение удалено';

    final body = last.body.isEmpty ? 'Вложение' : last.body;
    return last.senderId == myUserId ? 'Вы: $body' : body;
  }

  /// Сегодняшнее — часами, вчерашнее — словом, старое — датой. Как в любом
  /// списке переписок: точное время недельной давности никому не нужно.
  static String _time(DateTime at) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(at.year, at.month, at.day);
    final ago = today.difference(day).inDays;

    if (ago == 0) return DateFormat.Hm().format(at);
    if (ago == 1) return 'Вчера';
    if (ago < 7) return DateFormat.E('ru').format(at);
    return DateFormat('dd.MM.yy').format(at);
  }
}

class _EmptyChats extends StatelessWidget {
  const _EmptyChats();

  @override
  Widget build(BuildContext context) {
    return StateView(
      icon: TitoIcons.chats,
      title: 'Начните новый чат',
      description: 'Выберите контакт из списка или создайте группу.',
      actionLabel: 'Выбрать контакт',
      onAction: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const NewChatScreen()),
      ),
    );
  }
}
