import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../data/ws/envelope.dart';
import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/tokens.dart';
import 'chat_media_screen.dart';

/// Сведения о чате: кто в нём, что в нём и что с ним можно сделать.
class ChatInfoScreen extends ConsumerWidget {
  const ChatInfoScreen({required this.chatId, super.key});

  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final chat = ref.watch(chatProvider(chatId)).value;
    final members = ref.watch(chatMembersProvider(chatId)).value ?? const [];
    final peer = ref.watch(chatPeersProvider).value?[chatId];
    final attachments =
        ref.watch(chatAttachmentsProvider(chatId)).value ?? const <Message>[];

    final isGroup = chat?.type == 'group';
    final myUserId = ref.watch(sessionProvider).value?.userId ?? '';

    // Владелец группы — тот, кто её создал: только он удаляет её у всех и
    // исключает участников. Право проверяет сервер; здесь мы лишь не
    // показываем заведомый отказ.
    final iOwn =
        isGroup &&
        members.any((e) => e.user.id == myUserId && e.member.role == 'owner');
    final title = isGroup
        ? (chat?.title.isNotEmpty ?? false ? chat!.title : 'Группа')
        : peer?.displayName ?? 'Чат';

    // Участники: сначала администраторы, дальше по имени. В группе из
    // дюжины человек это единственный порядок, в котором что-то ищется.
    final sorted = [...members]..sort((a, b) {
      final byRole = _rank(a.member.role).compareTo(_rank(b.member.role));
      return byRole != 0
          ? byRole
          : a.user.displayName.compareTo(b.user.displayName);
    });

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(isGroup ? 'Сведения о группе' : 'Профиль'),
        actions: [
          if (isGroup)
            IconButton(
              icon: const Icon(TitoIcons.edit, size: 20),
              tooltip: 'Изменить',
              onPressed: () => showNotReady(context, 'Изменение группы'),
            ),
        ],
      ),
      body: ListView(
        children: [
          const SizedBox(height: Tokens.space5),
          Center(
            child: PersonAvatar(
              id: peer?.id ?? chatId,
              name: title,
              radius: 44,
              photo: peer?.avatarUrl ?? chat?.avatarUrl,
              online: peer?.online ?? false,
              icon: isGroup ? TitoIcons.contacts : null,
            ),
          ),
          const SizedBox(height: Tokens.space4),
          Center(child: Text(title, style: theme.textTheme.titleLarge)),
          const SizedBox(height: Tokens.space1),
          Center(
            child: Text(
              isGroup
                  ? 'Группа · ${_plural(members.length)}'
                  : peer?.phone ?? 'Личный чат',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(height: Tokens.space5),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: Tokens.space4),
            child: Row(
              children: [
                // Позвонить можно и отсюда: сюда приходят, чтобы посмотреть
                // на человека, и звонок — первое, чего от такого экрана
                // ждут. В группах его нет, как и в шапке.
                if (!isGroup && peer != null) ...[
                  _CallAction(peer: peer, chatId: chatId),
                  const SizedBox(width: Tokens.space2),
                ],
                _Action(
                  icon: TitoIcons.search,
                  label: 'Поиск',
                  onTap: () => showNotReady(context, 'Поиск по переписке'),
                ),
                const SizedBox(width: Tokens.space2),
                _Action(
                  icon: TitoIcons.bell,
                  label: 'Уведомления',
                  onTap: () => showNotReady(context, 'Настройки уведомлений'),
                ),
                const SizedBox(width: Tokens.space2),
                if (isGroup)
                  _Action(
                    icon: TitoIcons.addPerson,
                    label: 'Добавить',
                    onTap: () => _addMembers(context, ref, members),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.space5),
          if (isGroup) ...[
            SectionLabel('Участники · ${members.length}'),
            for (final entry in sorted.take(6))
              ListTile(
                leading: PersonAvatar(
                  id: entry.user.id,
                  name: entry.user.displayName,
                  radius: 18,
                  photo: entry.user.avatarUrl,
                  online: entry.user.online,
                ),
                title: Text(
                  entry.user.displayName,
                  style: theme.textTheme.bodyLarge,
                ),
                subtitle: Text(
                  entry.member.role == 'owner'
                      ? 'Владелец'
                      : entry.member.role == 'admin'
                      ? 'Администратор'
                      : entry.user.online
                      ? 'в сети'
                      : 'не в сети',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: entry.user.online && entry.member.role == 'member'
                        ? Tokens.online
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                // Исключать может владелец, и не себя и не владельца. Право
                // проверяет сервер; здесь мы лишь не показываем заведомый
                // отказ.
                trailing: iOwn &&
                        entry.user.id != myUserId &&
                        entry.member.role != 'owner'
                    ? IconButton(
                        icon: Icon(
                          TitoIcons.removePerson,
                          size: 18,
                          color: theme.colorScheme.outline,
                        ),
                        tooltip: 'Исключить',
                        onPressed: () => _confirmRemove(
                          context,
                          ref,
                          entry.user.id,
                          entry.user.displayName,
                        ),
                      )
                    : null,
              ),
            if (sorted.length > 6)
              TextButton(
                onPressed: () => showNotReady(context, 'Полный список'),
                child: const Text('Показать всех'),
              ),
            const SizedBox(height: Tokens.space3),
          ],
          const RowDivider(indent: 0),
          SettingsRow(
            icon: TitoIcons.image,
            title: 'Медиа, файлы, ссылки',
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  '${_countAttachments(attachments)}',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(width: Tokens.space2),
                Icon(
                  TitoIcons.forward,
                  size: 18,
                  color: theme.colorScheme.outline,
                ),
              ],
            ),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => ChatMediaScreen(chatId: chatId, title: title),
              ),
            ),
          ),
          SettingsRow(
            icon: TitoIcons.settings,
            title: 'Настройки чата',
            onTap: () => showNotReady(context, 'Настройки чата'),
          ),
          if (isGroup)
            SettingsRow(
              icon: TitoIcons.logout,
              title: 'Покинуть группу',
              danger: true,
              onTap: () => _confirmLeave(context, ref),
            ),
          if (isGroup && iOwn)
            SettingsRow(
              icon: TitoIcons.delete,
              title: 'Удалить группу у всех',
              danger: true,
              onTap: () => _confirmDelete(context, ref, forEveryone: true),
            ),
          if (!isGroup)
            SettingsRow(
              icon: TitoIcons.delete,
              title: 'Удалить переписку',
              danger: true,
              onTap: () => _confirmDelete(context, ref),
            ),
          const SizedBox(height: Tokens.space6),
        ],
      ),
    );
  }

  /// Добавление участников: выбор из тех, кого ещё нет в группе.
  ///
  /// Берём контакты, а не весь сервер: добавляют знакомых, а искать по
  /// номеру ради группы — редкий случай, ради которого не стоит городить
  /// второй поиск внутри шторки.
  Future<void> _addMembers(
    BuildContext context,
    WidgetRef ref,
    List<({ChatMember member, User user})> members,
  ) async {
    final present = members.map((e) => e.user.id).toSet();
    final contacts = (ref.read(contactsProvider).value ?? const <User>[])
        .where((u) => !present.contains(u.id))
        .toList();

    if (contacts.isEmpty) {
      showMessage(context, 'Некого добавить: все уже в группе');
      return;
    }

    final chosen = <String>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: Tokens.space3),
              Text(
                'Кого добавить',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: contacts.length,
                  itemBuilder: (context, index) {
                    final person = contacts[index];
                    final picked = chosen.contains(person.id);
                    return CheckboxListTile(
                      value: picked,
                      title: Text(person.displayName),
                      secondary: PersonAvatar(
                        id: person.id,
                        name: person.displayName,
                        radius: 18,
                        photo: person.avatarUrl,
                      ),
                      onChanged: (_) => setSheetState(() {
                        if (picked) {
                          chosen.remove(person.id);
                        } else {
                          chosen.add(person.id);
                        }
                      }),
                    );
                  },
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(Tokens.space4),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: chosen.isEmpty
                        ? null
                        : () => Navigator.of(sheetContext).pop(true),
                    child: const Text('Добавить'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (ok != true || chosen.isEmpty || !context.mounted) return;
    try {
      await ref.read(repositoryProvider)?.addMembers(chatId, chosen.toList());
    } on ProtocolException catch (error) {
      if (context.mounted) showMessage(context, error.message);
    }
  }

  /// Удаление чата. «У всех» доступно только владельцу группы: стереть
  /// историю у собеседника без его ведома — не то, что человек вправе
  /// сделать чужими руками, и сервер такого не принимает.
  Future<void> _confirmDelete(
    BuildContext context,
    WidgetRef ref, {
    bool forEveryone = false,
  }) async {
    final ok = await _ask(
      context,
      title: forEveryone ? 'Удалить группу у всех?' : 'Удалить переписку?',
      body: forEveryone
          ? 'Она исчезнет у всех участников. Это нельзя отменить.'
          : 'Она исчезнет только у вас. У собеседника останется.',
      action: 'Удалить',
    );
    if (!ok || !context.mounted) return;

    try {
      await ref
          .read(repositoryProvider)
          ?.deleteChat(chatId, forEveryone: forEveryone);
    } on ProtocolException catch (error) {
      if (context.mounted) showMessage(context, error.message);
      return;
    }
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  Future<void> _confirmRemove(
    BuildContext context,
    WidgetRef ref,
    String userId,
    String name,
  ) async {
    final ok = await _ask(
      context,
      title: 'Исключить из группы?',
      body: '$name перестанет видеть переписку.',
      action: 'Исключить',
    );
    if (!ok || !context.mounted) return;
    try {
      await ref.read(repositoryProvider)?.removeMember(chatId, userId);
    } on ProtocolException catch (error) {
      if (context.mounted) showMessage(context, error.message);
    }
  }

  /// Общий вопрос «точно?». Один на все опасные действия: три копии одного
  /// диалога разошлись бы при первой правке.
  Future<bool> _ask(
    BuildContext context, {
    required String title,
    required String body,
    required String action,
  }) async {
    final answer = await showGlassDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          OutlinedButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(action),
          ),
        ],
      ),
    );
    return answer == true;
  }

  Future<void> _confirmLeave(BuildContext context, WidgetRef ref) async {
    final leave = await showGlassDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Покинуть группу?'),
        content: const Text(
          'Переписка останется на сервере, но вы перестанете получать '
          'новые сообщения.',
        ),
        actions: [
          OutlinedButton(
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
    if (leave != true || !context.mounted) return;
    await ref.read(repositoryProvider)?.leaveChat(chatId);
    if (context.mounted) Navigator.of(context).popUntil((r) => r.isFirst);
  }

  static int _rank(String role) => switch (role) {
    'owner' => 0,
    'admin' => 1,
    _ => 2,
  };

  static String _plural(int count) {
    final last = count % 10;
    final teen = count % 100 >= 11 && count % 100 <= 14;
    if (!teen && last == 1) return '$count участник';
    if (!teen && last >= 2 && last <= 4) return '$count участника';
    return '$count участников';
  }

  static int _countAttachments(List<Message> messages) {
    var total = 0;
    for (final message in messages) {
      final raw = message.attachmentsJson;
      if (raw == null) continue;
      try {
        total += (jsonDecode(raw) as List<dynamic>).length;
      } catch (_) {
        // Битый JSON во вложениях — не повод ронять экран сведений.
      }
    }
    return total;
  }
}

/// Крупная кнопка действия под шапкой.
class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;

  /// null — действие недоступно. Так гаснет «позвонить», пока идёт другой
  /// звонок.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Недоступное действие обязано выглядеть недоступным. Иначе человек
    // жмёт кнопку, ничего не происходит, и он решает, что сломалось
    // приложение, а не что занята линия.
    final ink = onTap == null
        ? theme.colorScheme.outline
        : theme.colorScheme.onSurfaceVariant;

    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Tokens.radiusShell),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: Tokens.space3),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest,
            borderRadius: BorderRadius.circular(Tokens.radiusShell),
          ),
          child: Column(
            children: [
              Icon(icon, size: 20, color: ink),
              const SizedBox(height: 5),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(color: ink),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


/// «Позвонить» среди действий профиля.
class _CallAction extends ConsumerWidget {
  const _CallAction({required this.peer, required this.chatId});

  final User peer;
  final String chatId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final busy = ref.watch(currentCallProvider).value != null;
    return _Action(
      icon: TitoIcons.callStart,
      label: 'Позвонить',
      onTap: busy
          ? null
          : () async {
              try {
                await ref.read(callServiceProvider).start(
                  peerId: peer.id,
                  peerName: peer.displayName,
                  chatId: chatId,
                );
              } catch (_) {
                if (context.mounted) {
                  showMessage(context, 'Нет доступа к микрофону');
                }
              }
            },
    );
  }
}
