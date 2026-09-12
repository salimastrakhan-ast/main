import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/contacts/device_contacts.dart';
import '../../data/db/database.dart';
import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/state_view.dart';
import '../../ui/tokens.dart';
import '../chat/chat_screen.dart';

/// Новый чат: выбрать человека или собрать группу.
class NewChatScreen extends ConsumerStatefulWidget {
  const NewChatScreen({super.key});

  @override
  ConsumerState<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends ConsumerState<NewChatScreen> {
  final _query = TextEditingController();

  /// Выбранные для группы. Пусто — значит идёт обычный выбор собеседника.
  final _picked = <String>{};
  bool _group = false;

  /// Найденные на сервере — те, кого нет в адресной книге.
  List<User> _found = const [];
  bool _searching = false;
  bool _syncing = false;
  Timer? _searchDebounce;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(repositoryProvider)?.refreshContacts().ignore();
    });
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _query.dispose();
    super.dispose();
  }

  /// Забирает адресную книгу телефона и сверяет её с сервером.
  ///
  /// Спрашиваем разрешение здесь, а не при запуске: о том, что просят до
  /// объяснения зачем, люди жалеют и отказывают.
  Future<void> _syncBook() async {
    setState(() => _syncing = true);
    try {
      final count = await ref.read(repositoryProvider)?.syncDeviceContacts();
      if (!mounted) return;
      showMessage(context, switch (count) {
        null || 0 => 'Никого из вашей книги в Tito пока нет',
        1 => 'Нашёлся один знакомый',
        _ => 'Нашлось знакомых: $count',
      });
    } catch (_) {
      if (mounted) showMessage(context, 'Не удалось прочитать контакты');
    } finally {
      if (mounted) setState(() => _syncing = false);
    }
  }

  void _choose(User person) {
    if (!_group) {
      openChatWith(context, ref, person);
      return;
    }
    setState(() {
      if (!_picked.add(person.id)) _picked.remove(person.id);
    });
  }

  /// Ищет на сервере, когда в книге ничего не нашлось.
  ///
  /// С задержкой: иначе на каждую букву уходит запрос, а по мобильной сети
  /// это заметно и человеку, и серверу.
  void _searchOnServer(String query) {
    _searchDebounce?.cancel();
    final needle = query.trim();
    // Два знака, как в вебе и как у сервера (auth_handlers.go: «не короче
    // двух»). С тремя знаками поиск по последним цифрам номера в приложении
    // молчал, а в браузере находил.
    if (needle.length < 2) {
      setState(() {
        _found = const [];
        _searching = false;
      });
      return;
    }

    setState(() => _searching = true);
    _searchDebounce = Timer(const Duration(milliseconds: 350), () async {
      final people =
          await ref.read(repositoryProvider)?.searchPeople(needle) ?? const [];
      if (!mounted) return;
      setState(() {
        _found = people;
        _searching = false;
      });
    });
  }

  /// «Избранное» — личный чат с самим собой. Сервер заводит его первым
  /// сообщением, как любой другой личный чат.
  void _openSaved() {
    final me = ref.read(sessionProvider).value?.userId;
    if (me == null) return;
    final existing = ref.read(privateChatWithProvider(me)).value;
    ref.read(selectedChatProvider.notifier).state = existing;
    ref.read(draftPeerProvider.notifier).state = existing == null ? me : null;
    Navigator.of(context).popUntil((route) => route.isFirst);
  }

  Future<void> _createGroup() async {
    if (_picked.isEmpty) return;
    final title = await _askTitle();
    if (title == null || !mounted) return;

    final chatId = await ref
        .read(repositoryProvider)
        ?.createGroup(title, _picked.toList());
    if (!mounted || chatId == null) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(
        builder: (_) => ChatScreen(chatId: chatId, title: title),
      ),
    );
  }

  Future<String?> _askTitle() {
    final controller = TextEditingController();
    return showGlassDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Название группы'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Например, Рабочий чат'),
        ),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              final title = controller.text.trim();
              Navigator.of(context).pop(title.isEmpty ? null : title);
            },
            style: FilledButton.styleFrom(minimumSize: const Size(96, 46)),
            child: const Text('Создать'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final contacts = ref.watch(contactsProvider).value ?? const <User>[];
    final needle = _query.text.trim().toLowerCase();
    final shown = contacts
        .where(
          (u) =>
              needle.isEmpty ||
              u.displayName.toLowerCase().contains(needle) ||
              (u.phone ?? '').contains(needle),
        )
        .toList();

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(_group ? 'Новая группа' : 'Новый чат'),
        bottomHeight: 44 + Tokens.space3,
        bottom: Padding(
          padding: const EdgeInsets.fromLTRB(
            Tokens.space4,
            0,
            Tokens.space4,
            Tokens.space3,
          ),
          child: SearchField(
            hint: 'Имя или номер телефона',
            controller: _query,
            onChanged: (value) {
              setState(() {});
              _searchOnServer(value);
            },
          ),
        ),
      ),
      floatingActionButton: _group && _picked.isNotEmpty
          ? FloatingActionButton.extended(
              onPressed: _createGroup,
              icon: const Icon(TitoIcons.sent, size: 18),
              label: Text('Создать · ${_picked.length}'),
            )
          : null,
      body: contacts.isEmpty && shown.isEmpty && _found.isEmpty
          ? StateView(
              icon: TitoIcons.contacts,
              title: DeviceContacts.supported
                  ? 'Найдите знакомых'
                  : 'Начните новый чат',
              description: DeviceContacts.supported
                  ? 'Посмотрим, кто из вашей адресной книги уже в Tito. '
                        'Наружу уйдут только номера.'
                  : 'Введите номер телефона или имя — найдём на сервере.',
              actionLabel: DeviceContacts.supported
                  ? (_syncing ? 'Читаю книгу…' : 'Найти в контактах')
                  : 'Создать группу',
              onAction: DeviceContacts.supported
                  ? (_syncing ? null : _syncBook)
                  : () => setState(() => _group = true),
            )
          : ListView(
              children: [
                if (!_group) ...[
                  SettingsRow(
                    icon: TitoIcons.star,
                    title: 'Избранное',
                    subtitle: 'Заметки себе: ссылки, черновики, напоминания',
                    onTap: _openSaved,
                  ),
                  SettingsRow(
                    icon: TitoIcons.contacts,
                    title: 'Создать группу',
                    subtitle: 'Несколько человек в одной переписке',
                    onTap: () => setState(() => _group = true),
                  ),
                ],
                const RowDivider(indent: 0),
                if (shown.isNotEmpty)
                  for (final person in shown)
                    _PersonRow(
                      person: person,
                      group: _group,
                      picked: _picked.contains(person.id),
                      onTap: () => _choose(person),
                    ),

                // Найденные на сервере — отдельным разделом: человек должен
                // видеть, что это не из его книги, а из общего поиска.
                if (_searching)
                  const Padding(
                    padding: EdgeInsets.all(Tokens.space5),
                    child: Center(
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    ),
                  )
                else if (_found.isNotEmpty) ...[
                  const SectionLabel('Найдены на сервере'),
                  for (final person in _found)
                    if (!contacts.any((c) => c.id == person.id))
                      _PersonRow(
                        person: person,
                        group: _group,
                        picked: _picked.contains(person.id),
                        onTap: () => _choose(person),
                      ),
                ] else if (shown.isEmpty && _query.text.trim().length >= 3)
                  Padding(
                    padding: const EdgeInsets.all(Tokens.space5),
                    child: Text(
                      'Никого не нашли. Номер нужен целиком — по части '
                      'номера поиск не работает намеренно.',
                      textAlign: TextAlign.center,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),

                if (DeviceContacts.supported) ...[
                  const RowDivider(indent: 0),
                  SettingsRow(
                    icon: TitoIcons.contacts,
                    title: 'Обновить из адресной книги',
                    subtitle: _syncing
                        ? 'Читаю книгу…'
                        : 'Посмотреть, кто из знакомых уже в Tito',
                    onTap: _syncing ? null : _syncBook,
                  ),
                ],
              ],
            ),
    );
  }
}

class _PersonRow extends StatelessWidget {
  const _PersonRow({
    required this.person,
    required this.group,
    required this.picked,
    required this.onTap,
  });

  final User person;
  final bool group;
  final bool picked;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return ListTile(
      onTap: onTap,
      leading: PersonAvatar(
        id: person.id,
        name: person.displayName,
        photo: person.avatarUrl,
        online: person.online,
      ),
      title: Text(person.displayName, style: theme.textTheme.titleMedium),
      subtitle: Text(
        person.phone ?? (person.online ? 'в сети' : 'не в сети'),
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
      trailing: group
          ? Icon(
              picked ? TitoIcons.sent : TitoIcons.attach,
              size: 20,
              color: picked
                  ? theme.colorScheme.primary
                  : theme.colorScheme.outline,
            )
          : null,
    );
  }
}
