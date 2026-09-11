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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(repositoryProvider)?.refreshContacts().ignore();
    });
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
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
            hint: 'Поиск по контактам',
            controller: _query,
            onChanged: (_) => setState(() {}),
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
      body: contacts.isEmpty
          ? StateView(
              icon: TitoIcons.chats,
              title: 'Начните новый чат',
              description:
                  'Контакты появятся, когда кто-то из ваших знакомых '
                  'зарегистрируется в «Titoе».',
              actionLabel: 'Создать группу',
              onAction: () => setState(() => _group = true),
            )
          : ListView(
              children: [
                if (!_group)
                  SettingsRow(
                    icon: TitoIcons.contacts,
                    title: 'Создать группу',
                    subtitle: 'Несколько человек в одной переписке',
                    onTap: () => setState(() => _group = true),
                  ),
                const RowDivider(indent: 0),
                for (final person in shown)
                  _PersonRow(
                    person: person,
                    group: _group,
                    picked: _picked.contains(person.id),
                    onTap: () {
                      if (!_group) {
                        openChatWith(context, ref, person);
                        return;
                      }
                      setState(() {
                        if (!_picked.add(person.id)) _picked.remove(person.id);
                      });
                    },
                  ),
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
