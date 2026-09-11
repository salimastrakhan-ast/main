import 'dart:developer' as developer;

import 'package:flutter/material.dart';

import 'icons.dart';

/// Пустой экран, загрузка и ошибка — одним языком.
///
/// Раньше на этих местах стояли `CircularProgressIndicator` посреди пустоты и
/// `Text('Ошибка: $e')`. Второе показывало человеку текст исключения: ему это
/// ничего не объясняет, а разработчику всё равно нужен полный стек, которого
/// в такой строке нет.
class StateView extends StatelessWidget {
  const StateView({
    required this.icon,
    required this.title,
    this.description,
    this.actionLabel,
    this.onAction,
    super.key,
  });

  /// Загрузка. Спокойная и без заголовка: подпись к спиннеру, который висит
  /// долю секунды, только мельтешит.
  const StateView.loading({super.key})
    : icon = null,
      title = '',
      description = null,
      actionLabel = null,
      onAction = null;

  /// Ошибка. Подробности уходят в лог, человеку — понятный текст и действие.
  factory StateView.error(
    Object error, {
    String title = 'Не удалось загрузить',
    VoidCallback? onRetry,
  }) {
    developer.log('ошибка на экране', error: error, name: 'mayak.ui');
    return StateView(
      icon: MayakIcons.offline,
      title: title,
      description: 'Проверьте соединение и попробуйте ещё раз.',
      actionLabel: onRetry == null ? null : 'Повторить',
      onAction: onRetry,
    );
  }

  final IconData? icon;
  final String title;
  final String? description;
  final String? actionLabel;
  final VoidCallback? onAction;

  bool get _isLoading => icon == null && title.isEmpty;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    if (_isLoading) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2.5),
        ),
      );
    }

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 56, color: theme.colorScheme.outline),
            const SizedBox(height: 18),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.titleMedium,
            ),
            if (description != null) ...[
              const SizedBox(height: 8),
              Text(
                description!,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            if (actionLabel != null) ...[
              const SizedBox(height: 22),
              OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
            ],
          ],
        ),
      ),
    );
  }
}
