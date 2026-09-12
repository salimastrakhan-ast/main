import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/db/database.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/tokens.dart';

/// Куда переслать.
///
/// Список тех же переписок, что на главном экране, а не отдельная книга
/// контактов: пересылают обычно в то, что под рукой, и лишний шаг «сначала
/// выбери человека» тут ни к чему.
///
/// Возвращает идентификатор выбранного чата или null, если передумали.
Future<String?> showForwardSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    builder: (_) => const _ForwardSheet(),
  );
}

class _ForwardSheet extends ConsumerStatefulWidget {
  const _ForwardSheet();

  @override
  ConsumerState<_ForwardSheet> createState() => _ForwardSheetState();
}

class _ForwardSheetState extends ConsumerState<_ForwardSheet> {
  final _search = TextEditingController();

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final chats = ref.watch(chatsProvider).value ?? const <Chat>[];
    final peers = ref.watch(chatPeersProvider).value ?? const <String, User>{};

    final needle = _search.text.trim().toLowerCase();
    final rows = chats.where((chat) {
      if (needle.isEmpty) return true;
      return _title(chat, peers).toLowerCase().contains(needle);
    }).toList();

    return SizedBox(
      height: MediaQuery.sizeOf(context).height * 0.6,
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            const SizedBox(height: Tokens.space3),
            Text('Кому переслать', style: theme.textTheme.titleMedium),
            Padding(
              padding: const EdgeInsets.all(Tokens.space3),
              child: SearchField(
                hint: 'Поиск',
                controller: _search,
                onChanged: (_) => setState(() {}),
              ),
            ),
            Expanded(
              child: rows.isEmpty
                  ? Center(
                      child: Text(
                        'Ничего не нашлось',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final chat = rows[index];
                        final peer = peers[chat.id];
                        final title = _title(chat, peers);
                        return ListTile(
                          leading: PersonAvatar(
                            id: chat.id,
                            name: title,
                            radius: 20,
                            photo: peer?.avatarUrl ?? chat.avatarUrl,
                            icon: chat.type == 'group'
                                ? TitoIcons.contacts
                                : null,
                          ),
                          title: Text(title),
                          onTap: () => Navigator.of(context).pop(chat.id),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  String _title(Chat chat, Map<String, User> peers) {
    if (chat.type == 'group') {
      return chat.title.isNotEmpty ? chat.title : 'Группа';
    }
    return peers[chat.id]?.displayName ?? 'Чат';
  }
}
