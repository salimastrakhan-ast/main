import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/state_view.dart';
import '../../ui/tokens.dart';
import '../chat/chat_screen.dart';

/// Адресная книга.
///
/// Книга приезжает с сервера, но экран читает её из локальной базы: список
/// должен открываться мгновенно и работать в метро, а обновление — это
/// фоновая задача, а не условие показа.
class ContactsScreen extends ConsumerStatefulWidget {
  const ContactsScreen({super.key});

  @override
  ConsumerState<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends ConsumerState<ContactsScreen> {
  static const _filters = ['Все', 'Онлайн', 'Избранные', 'Группы'];

  final _query = TextEditingController();
  final _scroll = ScrollController();
  final _letterKeys = <String, GlobalKey>{};
  int _filter = 0;

  @override
  void initState() {
    super.initState();
    // Обновляем книгу при открытии экрана, не блокируя показ.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(repositoryProvider)?.refreshContacts().ignore();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _jumpTo(String letter) {
    final key = _letterKeys[letter];
    final context = key?.currentContext;
    if (context == null) return;
    Scrollable.ensureVisible(
      context,
      duration: Tokens.duration,
      curve: Curves.easeOutCubic,
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider);
    final chats = ref.watch(chatsProvider).value ?? const <Chat>[];

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Контакты'),
        leading: const SizedBox.shrink(),
        bottomHeight: 34 + 44 + Tokens.space3,
        bottom: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Tokens.space4,
                0,
                Tokens.space4,
                Tokens.space3,
              ),
              child: SearchField(
                hint: 'Поиск',
                controller: _query,
                onChanged: (_) => setState(() {}),
              ),
            ),
            FilterChipsRow(
              labels: _filters,
              index: _filter,
              onSelect: (i) => setState(() => _filter = i),
            ),
            const SizedBox(height: Tokens.space3),
          ],
        ),
      ),
      body: contacts.when(
        loading: () => const StateView.loading(),
        error: (e, _) => StateView.error(e, title: 'Не удалось загрузить'),
        data: (list) => _filter == 3
            ? _Groups(chats: chats, query: _query.text)
            : _People(
                people: _filtered(list),
                query: _query.text,
                scroll: _scroll,
                letterKeys: _letterKeys,
                onJump: _jumpTo,
              ),
      ),
    );
  }

  List<User> _filtered(List<User> all) {
    final needle = _query.text.trim().toLowerCase();
    return all.where((u) {
      if (_filter == 1 && !u.online) return false;
      if (_filter == 2 && !u.isFavorite) return false;
      if (needle.isEmpty) return true;
      return u.displayName.toLowerCase().contains(needle) ||
          (u.phone ?? '').contains(needle);
    }).toList();
  }
}

/// Люди, разложенные по буквам, с указателем справа.
class _People extends ConsumerWidget {
  const _People({
    required this.people,
    required this.query,
    required this.scroll,
    required this.letterKeys,
    required this.onJump,
  });

  final List<User> people;
  final String query;
  final ScrollController scroll;
  final Map<String, GlobalKey> letterKeys;
  final ValueChanged<String> onJump;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (people.isEmpty) {
      return StateView(
        icon: TitoIcons.contacts,
        title: query.isEmpty ? 'Контактов пока нет' : 'Никого не нашлось',
        description: query.isEmpty
            ? 'Контакты появятся, когда кто-то из ваших знакомых '
                  'зарегистрируется в «Titoе».'
            : 'Попробуйте другое имя или номер.',
      );
    }

    // Разложение по буквам делаем здесь, а не в базе: список короткий, а
    // SQL-группировка по первому символу в SQLite зависит от локали.
    final byLetter = <String, List<User>>{};
    for (final person in people) {
      final letter = person.displayName.isEmpty
          ? '#'
          : person.displayName.characters.first.toUpperCase();
      byLetter.putIfAbsent(letter, () => []).add(person);
    }
    final letters = byLetter.keys.toList()..sort();

    return Stack(
      children: [
        ListView.builder(
          controller: scroll,
          padding: const EdgeInsets.only(bottom: Tokens.space4, right: 20),
          itemCount: letters.length,
          itemBuilder: (context, index) {
            final letter = letters[index];
            final key = letterKeys.putIfAbsent(letter, GlobalKey.new);
            return Column(
              key: key,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SectionLabel(letter),
                for (final person in byLetter[letter]!)
                  _PersonRow(person: person),
              ],
            );
          },
        ),
        Positioned(
          top: 0,
          bottom: 0,
          right: 2,
          child: _LetterIndex(letters: letters, onTap: onJump),
        ),
      ],
    );
  }
}

class _PersonRow extends ConsumerWidget {
  const _PersonRow({required this.person});

  final User person;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return ListTile(
      leading: PersonAvatar(
        id: person.id,
        name: person.displayName,
        online: person.online,
      ),
      title: Text(person.displayName, style: theme.textTheme.titleMedium),
      subtitle: Text(
        person.online ? 'в сети' : _lastSeen(person.lastSeenAt),
        style: theme.textTheme.bodySmall?.copyWith(
          color: person.online
              ? Tokens.olive
              : theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: IconButton(
        icon: Icon(
          TitoIcons.star,
          size: 18,
          color: person.isFavorite
              ? theme.colorScheme.primary
              : theme.colorScheme.outline,
        ),
        tooltip: person.isFavorite ? 'Убрать из избранного' : 'В избранное',
        onPressed: () => ref
            .read(databaseProvider)
            .setFavorite(person.id, !person.isFavorite),
      ),
      onTap: () => openChatWith(context, ref, person),
    );
  }

  static String _lastSeen(DateTime? at) {
    if (at == null) return 'не в сети';
    final ago = DateTime.now().difference(at);
    if (ago.inMinutes < 1) return 'был(а) только что';
    if (ago.inHours < 1) return 'был(а) ${ago.inMinutes} мин назад';
    if (ago.inDays < 1) return 'был(а) ${ago.inHours} ч назад';
    if (ago.inDays == 1) return 'был(а) вчера';
    return 'был(а) ${ago.inDays} дн назад';
  }
}

/// Группы в той же книге: в мессенджере это такой же адресат.
class _Groups extends StatelessWidget {
  const _Groups({required this.chats, required this.query});

  final List<Chat> chats;
  final String query;

  @override
  Widget build(BuildContext context) {
    final needle = query.trim().toLowerCase();
    final groups = chats
        .where((c) => c.type == 'group')
        .where((c) => needle.isEmpty || c.title.toLowerCase().contains(needle))
        .toList();

    if (groups.isEmpty) {
      return const StateView(
        icon: TitoIcons.contacts,
        title: 'Групп пока нет',
        description: 'Создайте группу из списка диалогов.',
      );
    }

    return ListView.builder(
      itemCount: groups.length,
      itemBuilder: (context, index) {
        final group = groups[index];
        return ListTile(
          leading: PersonAvatar(
            id: group.id,
            name: group.title,
            icon: TitoIcons.contacts,
          ),
          title: Text(
            group.title.isEmpty ? 'Группа' : group.title,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          subtitle: const Text('Группа'),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => ChatScreen(chatId: group.id, title: group.title),
            ),
          ),
        );
      },
    );
  }
}

/// Полоса букв справа.
class _LetterIndex extends StatelessWidget {
  const _LetterIndex({required this.letters, required this.onTap});

  final List<String> letters;
  final ValueChanged<String> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (letters.length < 4) return const SizedBox.shrink();

    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final letter in letters)
            GestureDetector(
              onTap: () => onTap(letter),
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 1.5,
                ),
                child: Text(
                  letter,
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    fontSize: 10,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
