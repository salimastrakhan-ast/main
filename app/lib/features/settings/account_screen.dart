import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/tokens.dart';

/// Аккаунт: имя и номер.
///
/// Имя редактируется по-настоящему — уходит на сервер и возвращается всем,
/// кто с вами переписывается. Номер менять нельзя: на нём держится вход.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _name = TextEditingController();
  bool _saving = false;
  bool _filled = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    if (name.isEmpty || _saving) return;

    setState(() => _saving = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await ref
          .read(apiProvider)
          .updateMe(displayName: name);
      await ref.read(repositoryProvider)?.upsertUser(updated);
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Имя сохранено')));
    } catch (_) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Не удалось сохранить')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final session = ref.watch(sessionProvider).value;
    final me = ref.watch(usersProvider).value?[session?.userId];

    // Поле заполняем один раз: иначе каждое обновление профиля с сервера
    // затирало бы то, что человек печатает прямо сейчас.
    if (!_filled && me != null) {
      _name.text = me.displayName;
      _filled = true;
    }

    return Scaffold(
      appBar: const GlassAppBar(title: Text('Аккаунт')),
      body: ListView(
        padding: const EdgeInsets.all(Tokens.space4),
        children: [
          Text('Имя', style: theme.textTheme.labelLarge),
          const SizedBox(height: Tokens.space2),
          TextField(
            controller: _name,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(hintText: 'Как вас зовут'),
            onSubmitted: (_) => _save(),
          ),
          const SizedBox(height: Tokens.space2),
          Text(
            'Его видят те, с кем вы переписываетесь.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: Tokens.space5),
          FilledButton(
            onPressed: _saving ? null : _save,
            child: Text(_saving ? 'Сохраняю…' : 'Сохранить'),
          ),
          const SizedBox(height: Tokens.space8),
          const RowDivider(indent: 0),
          SettingsRow(
            icon: TitoIcons.phone,
            title: 'Номер телефона',
            subtitle: me?.phone ?? '—',
          ),
          SettingsRow(
            icon: TitoIcons.privacy,
            title: 'Сменить номер',
            subtitle: 'На нём держится вход в аккаунт',
            onTap: () => showNotReady(context, 'Смена номера'),
          ),
          SettingsRow(
            icon: TitoIcons.delete,
            title: 'Удалить аккаунт',
            danger: true,
            onTap: () => showNotReady(context, 'Удаление аккаунта'),
          ),
        ],
      ),
    );
  }
}
