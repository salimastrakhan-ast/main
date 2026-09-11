import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/state_view.dart';
import '../../ui/tokens.dart';
import '../chat/chat_screen.dart';

/// Поиск по всему сразу.
///
/// Ищет в локальной базе: диалоги, контакты, сообщения и вложения уже лежат
/// на устройстве. Отсюда мгновенный ответ и работа без сети — и отсюда же
/// граница: то, что ещё не синхронизировалось, не найдётся.
class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({this.initial = '', super.key});

  /// Запрос, с которым экран открыли. Панель уже что-то искала, и заставлять
  /// набирать это второй раз незачем.
  final String initial;

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  static const _tabs = ['Чаты', 'Контакты', 'Сообщения', 'Медиа'];

  final _query = TextEditingController();
  int _tab = 0;
  List<Message> _messages = const [];

  @override
  void initState() {
    super.initState();
    if (widget.initial.isNotEmpty) {
      _query.text = widget.initial;
      WidgetsBinding.instance.addPostFrameCallback((_) => _onQuery(widget.initial));
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _onQuery(String value) async {
    setState(() {});
    final needle = value.trim();
    if (needle.length < 2) {
      setState(() => _messages = const []);
      return;
    }
    final found = await ref.read(databaseProvider).searchMessages(needle);
    if (mounted) setState(() => _messages = found);
  }

  @override
  Widget build(BuildContext context) {
    final needle = _query.text.trim().toLowerCase();

    return Scaffold(
      appBar: GlassAppBar(
        title: SearchField(
          hint: 'Поиск',
          controller: _query,
          autofocus: true,
          onChanged: _onQuery,
        ),
        actions: const [SizedBox.shrink()],
        bottomHeight: 34 + Tokens.space3,
        bottom: Column(
          children: [
            FilterChipsRow(
              labels: _tabs,
              index: _tab,
              onSelect: (i) => setState(() => _tab = i),
            ),
            const SizedBox(height: Tokens.space3),
          ],
        ),
      ),
      body: needle.length < 2
          ? const StateView(
              icon: TitoIcons.search,
              title: 'Что ищем?',
              description: 'Введите хотя бы две буквы — '
                  'найдём среди диалогов, людей и сообщений.',
            )
          : switch (_tab) {
              0 => _Chats(needle: needle),
              1 => _People(needle: needle),
              2 => _Messages(messages: _messages, needle: needle),
              _ => const _Media(),
            },
    );
  }
}

class _Chats extends ConsumerWidget {
  const _Chats({required this.needle});

  final String needle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final chats = ref.watch(chatsProvider).value ?? const <Chat>[];
    final peers = ref.watch(chatPeersProvider).value ?? const {};

    final found = chats.where((chat) {
      final title = chat.title.isNotEmpty
          ? chat.title
          : peers[chat.id]?.displayName ?? '';
      return title.toLowerCase().contains(needle);
    }).toList();

    if (found.isEmpty) return const _Nothing();

    return ListView.builder(
      itemCount: found.length,
      itemBuilder: (context, index) {
        final chat = found[index];
        final peer = peers[chat.id];
        final title = chat.title.isNotEmpty
            ? chat.title
            : peer?.displayName ?? 'Чат';
        return ListTile(
          leading: PersonAvatar(
            id: peer?.id ?? chat.id,
            name: title,
            online: peer?.online ?? false,
            icon: chat.type == 'group' ? TitoIcons.contacts : null,
          ),
          title: Text(title),
          subtitle: Text(chat.type == 'group' ? 'Группа' : 'Личный чат'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatScreen(chatId: chat.id, title: title),
            ),
          ),
        );
      },
    );
  }
}

class _People extends ConsumerWidget {
  const _People({required this.needle});

  final String needle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(usersProvider).value ?? const <String, User>{};
    final me = ref.watch(sessionProvider).value?.userId;

    final found = all.values
        .where((u) => u.id != me)
        .where(
          (u) =>
              u.displayName.toLowerCase().contains(needle) ||
              (u.phone ?? '').contains(needle),
        )
        .toList();

    if (found.isEmpty) return const _Nothing();

    return ListView.builder(
      itemCount: found.length,
      itemBuilder: (context, index) {
        final person = found[index];
        return ListTile(
          leading: PersonAvatar(
            id: person.id,
            name: person.displayName,
            online: person.online,
          ),
          title: Text(person.displayName),
          subtitle: Text(
            person.online ? 'в сети' : 'не в сети',
            style: TextStyle(
              color: person.online
                  ? Tokens.online
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => openChatWith(context, ref, person),
        );
      },
    );
  }
}

class _Messages extends ConsumerWidget {
  const _Messages({required this.messages, required this.needle});

  final List<Message> messages;
  final String needle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (messages.isEmpty) return const _Nothing();

    final theme = Theme.of(context);
    final peers = ref.watch(chatPeersProvider).value ?? const {};
    final chats = {
      for (final chat in ref.watch(chatsProvider).value ?? const <Chat>[])
        chat.id: chat,
    };

    return ListView.separated(
      itemCount: messages.length,
      separatorBuilder: (_, _) => const RowDivider(),
      itemBuilder: (context, index) {
        final message = messages[index];
        final chat = chats[message.chatId];
        final peer = peers[message.chatId];
        final title = chat != null && chat.title.isNotEmpty
            ? chat.title
            : peer?.displayName ?? 'Чат';

        return ListTile(
          leading: PersonAvatar(id: peer?.id ?? message.chatId, name: title),
          title: Text(title, style: theme.textTheme.titleMedium),
          subtitle: Text(
            message.body,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          trailing: Text(
            DateFormat('dd.MM').format(message.createdAt),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) =>
                  ChatScreen(chatId: message.chatId, title: title),
            ),
          ),
        );
      },
    );
  }
}

/// Поиск по вложениям.
///
/// Пока без содержимого файлов: имя вложения лежит в сообщении, а сами
/// файлы на сервере, и искать по ним нечем.
class _Media extends StatelessWidget {
  const _Media();

  @override
  Widget build(BuildContext context) {
    return const StateView(
      icon: TitoIcons.image,
      title: 'Поиск по медиа появится позже',
      description: 'Пока файлы можно найти на экране сведений о чате.',
    );
  }
}

class _Nothing extends StatelessWidget {
  const _Nothing();

  @override
  Widget build(BuildContext context) {
    return const StateView(
      icon: TitoIcons.search,
      title: 'Ничего не нашлось',
      description: 'Попробуйте другое слово.',
    );
  }
}
