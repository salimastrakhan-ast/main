import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/providers.dart';
import '../../ui/glass.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/tokens.dart';

/// Аккаунт: фотография, имя и номер.
///
/// Имя и фотография редактируются по-настоящему — уходят на сервер и
/// возвращаются всем, кто с вами переписывается. Номер менять нельзя: на
/// нём держится вход.
class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});

  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  final _name = TextEditingController();
  bool _saving = false;
  bool _busyPhoto = false;
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

  /// Ставит фотографию профиля.
  ///
  /// Предел сервера — восемь мегабайт. Выбор ограничен галереей: снимок с
  /// камеры тоже попадает туда, а отдельная кнопка «сфотографировать» на
  /// экране настроек только занимает место.
  Future<void> _pickPhoto() async {
    if (_busyPhoto) return;
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      // Уменьшаем ещё до отправки: в кружок сорок на сорок точек
      // десятимегапиксельный снимок не нужен, а по мобильной сети он
      // поедет минуту.
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 85,
    );
    if (picked == null) return;
    if (!mounted) return;

    // Ссылку на ScaffoldMessenger берём до выбора файла: пока открыт
    // системный выбор, экран может исчезнуть, и контекст станет чужим.
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busyPhoto = true);
    try {
      final updated = await ref.read(apiProvider).setAvatar(
        fileName: picked.name,
        bytes: await picked.readAsBytes(),
      );
      await ref.read(repositoryProvider)?.upsertUser(updated);
    } catch (_) {
      messenger
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Не удалось поставить фото')));
    } finally {
      if (mounted) setState(() => _busyPhoto = false);
    }
  }

  Future<void> _removePhoto() async {
    if (_busyPhoto) return;
    setState(() => _busyPhoto = true);
    try {
      final updated = await ref.read(apiProvider).removeAvatar();
      await ref.read(repositoryProvider)?.upsertUser(updated);
    } catch (_) {
      // Молчим: фотография осталась на месте, и человек это видит сам.
    } finally {
      if (mounted) setState(() => _busyPhoto = false);
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
          Center(
            child: Column(
              children: [
                Stack(
                  alignment: Alignment.bottomRight,
                  children: [
                    PersonAvatar(
                      id: session?.userId ?? '',
                      name: me?.displayName ?? '?',
                      radius: 48,
                      photo: me?.avatarUrl,
                    ),
                    Material(
                      color: theme.colorScheme.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _busyPhoto ? null : _pickPhoto,
                        child: Padding(
                          padding: const EdgeInsets.all(Tokens.space2),
                          child: _busyPhoto
                              ? SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: theme.colorScheme.onPrimary,
                                  ),
                                )
                              : Icon(
                                  TitoIcons.image,
                                  size: 16,
                                  color: theme.colorScheme.onPrimary,
                                ),
                        ),
                      ),
                    ),
                  ],
                ),
                if ((me?.avatarUrl ?? '').isNotEmpty)
                  TextButton(
                    onPressed: _busyPhoto ? null : _removePhoto,
                    child: const Text('Убрать фото'),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Tokens.space5),
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
