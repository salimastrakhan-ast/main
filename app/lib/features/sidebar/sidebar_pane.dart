import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../data/ws/ws_client.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/state_view.dart';
import '../../ui/tokens.dart';
import '../chats/new_chat_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';

/// Боковая панель: список диалогов или настройки.
///
/// Устроена как в веб-клиенте: настройки занимают место списка, а не
/// открываются поверх всего. На широком экране панель стоит рядом с
/// перепиской и никуда не уезжает, поэтому переход поверх неё выглядел бы
/// так, будто переписку накрыли настройками.
class SidebarPane extends ConsumerWidget {
  const SidebarPane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final view = ref.watch(sidebarViewProvider);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerLow,
      ),
      child: switch (view) {
        SidebarView.chats => const _ChatsView(),
        SidebarView.settings => const SettingsScreen(),
      },
    );
  }
}

class _ChatsView extends ConsumerStatefulWidget {
  const _ChatsView();

  @override
  ConsumerState<_ChatsView> createState() => _ChatsViewState();
}

class _ChatsViewState extends ConsumerState<_ChatsView> {
  final _query = TextEditingController();

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chats = ref.watch(chatsProvider);
    final peers = ref.watch(chatPeersProvider).value ?? const {};
    final lastMessages = ref.watch(lastMessagesProvider).value ?? const {};
    final session = ref.watch(sessionProvider).value;
    final folder = ref.watch(chatFolderProvider);
    final needle = ref.watch(sidebarSearchProvider).trim().toLowerCase();

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          _Header(
            onSettings: () =>
                ref.read(sidebarViewProvider.notifier).state =
                    SidebarView.settings,
            onNewChat: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const NewChatScreen()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Tokens.space3,
              Tokens.space1,
              Tokens.space3,
              Tokens.space2,
            ),
            child: SearchField(
              hint: 'Поиск',
              controller: _query,
              onChanged: (value) =>
                  ref.read(sidebarSearchProvider.notifier).state = value,
            ),
          ),
          _Folders(
            value: folder,
            onSelect: (next) =>
                ref.read(chatFolderProvider.notifier).state = next,
          ),
          const _ConnectionBanner(),
          Expanded(
            child: chats.when(
              loading: () => const StateView.loading(),
              error: (e, _) =>
                  StateView.error(e, title: 'Не удалось загрузить диалоги'),
              data: (list) {
                final shown = list.where((chat) {
                  final peer = peers[chat.id];
                  if (!_matchesFolder(chat, folder)) return false;
                  if (needle.isEmpty) return true;
                  final title = chat.title.isNotEmpty
                      ? chat.title
                      : peer?.displayName ?? '';
                  return title.toLowerCase().contains(needle);
                }).toList();

                if (shown.isEmpty) {
                  return _Empty(
                    searching: needle.isNotEmpty,
                    onNewChat: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => const NewChatScreen(),
                      ),
                    ),
                  );
                }

                return ListView.builder(
                  padding: const EdgeInsets.only(bottom: Tokens.space4),
                  itemCount: shown.length + (needle.isEmpty ? 0 : 1),
                  itemBuilder: (context, index) {
                    if (index == shown.length) {
                      // Поиск по переписке живёт на своём экране: там вкладки
                      // и результаты по людям и сообщениям, а здесь панель
                      // фильтрует только сами диалоги.
                      return ListTile(
                        leading: Icon(
                          TitoIcons.search,
                          size: 20,
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          'Искать в сообщениях',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                        onTap: () => Navigator.of(context).push(
                          MaterialPageRoute<void>(
                            builder: (_) => SearchScreen(initial: _query.text),
                          ),
                        ),
                      );
                    }
                    final chat = shown[index];
                    return _ChatTile(
                      chat: chat,
                      peer: peers[chat.id],
                      lastMessage: lastMessages[chat.id],
                      myUserId: session?.userId ?? '',
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  static bool _matchesFolder(Chat chat, ChatFolder folder) => switch (folder) {
    ChatFolder.all => true,
    ChatFolder.personal => chat.type != 'group',
    ChatFolder.groups => chat.type == 'group',
  };
}

/// Шапка панели: настройки, знак с названием, новый чат.
class _Header extends StatelessWidget {
  const _Header({required this.onSettings, required this.onNewChat});

  final VoidCallback onSettings;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(Tokens.space2, Tokens.space2, Tokens.space2, 0),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(TitoIcons.settings, size: 20),
            tooltip: 'Настройки',
            onPressed: onSettings,
          ),
          Expanded(
            child: Row(
              children: [
                Container(
                  width: 26,
                  height: 26,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(Tokens.br8),
                  ),
                  child: Text(
                    'T',
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: theme.colorScheme.onPrimary,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                Text('Tito', style: theme.textTheme.titleMedium),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(TitoIcons.compose, size: 20),
            tooltip: 'Новый чат',
            onPressed: onNewChat,
          ),
        ],
      ),
    );
  }
}

/// Папки: все, личные, группы.
class _Folders extends StatelessWidget {
  const _Folders({required this.value, required this.onSelect});

  final ChatFolder value;
  final ValueChanged<ChatFolder> onSelect;

  static const _labels = ['Все', 'Личные', 'Группы'];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: Tokens.space2),
      child: FilterChipsRow(
        labels: _labels,
        index: ChatFolder.values.indexOf(value),
        onSelect: (i) => onSelect(ChatFolder.values[i]),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.searching, required this.onNewChat});

  final bool searching;
  final VoidCallback onNewChat;

  @override
  Widget build(BuildContext context) {
    if (searching) {
      return const StateView(
        icon: TitoIcons.search,
        title: 'Ничего не нашлось',
        description: 'Попробуйте другое название.',
      );
    }
    return StateView(
      icon: TitoIcons.chats,
      title: 'Пока пусто',
      description: 'Напишите первым — выберите, кому.',
      actionLabel: 'Новый чат',
      onAction: onNewChat,
    );
  }
}
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

class _ChatTile extends ConsumerWidget {
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

  /// «Избранное» — личный чат, в котором участник один: я сам.
  bool get _isSaved => !_isGroup && peer == null && lastMessage != null;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      // Выбор, а не переход: на широком экране переписка открывается
      // рядом с панелью, и стек навигации тут ни при чём.
      selected: ref.watch(selectedChatProvider) == chat.id,
      selectedTileColor: theme.colorScheme.surfaceContainerHighest,
      onTap: () =>
          ref.read(selectedChatProvider.notifier).state = chat.id,
    );
  }

  /// У группы есть название, а у личного чата его нет: там заголовок —
  /// это имя собеседника.
  String _title() {
    if (chat.title.isNotEmpty) return chat.title;
    if (_isSaved) return 'Избранное';
    return peer?.displayName ?? 'Чат';
  }

  /// Вторая строка: начало последнего сообщения — как в любом мессенджере.
  ///
  /// Пока сообщений нет, вместо пустоты пишем, что это за чат: строка без
  /// подписи выглядит наполовину не загрузившейся.
  String _preview() {
    final last = lastMessage;
    if (last == null) {
      return _isGroup ? 'Группа' : (_isSaved ? 'Заметки себе' : 'Личный чат');
    }
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

