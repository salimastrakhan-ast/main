import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
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
                _Action(
                  icon: TitoIcons.addPerson,
                  label: 'Добавить',
                  onTap: () => showNotReady(context, 'Добавление участников'),
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
                  online: entry.user.online,
                ),
                title: Text(
                  entry.user.displayName,
                  style: theme.textTheme.bodyLarge,
                ),
                subtitle: Text(
                  entry.member.role == 'owner' || entry.member.role == 'admin'
                      ? 'Администратор'
                      : entry.user.online
                      ? 'в сети'
                      : 'не в сети',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: entry.user.online && entry.member.role == 'member'
                        ? Tokens.olive
                        : theme.colorScheme.onSurfaceVariant,
                  ),
                ),
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
          const SizedBox(height: Tokens.space6),
        ],
      ),
    );
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
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

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
              Icon(icon, size: 20, color: theme.colorScheme.onSurfaceVariant),
              const SizedBox(height: 5),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
