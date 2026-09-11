import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../ui/icons.dart';
import '../../ui/theme.dart';
import '../../ui/tokens.dart';
import '../auth/phone_screen.dart';

/// Первый экран при первом запуске.
///
/// Показывается один раз: дальше человеку нужен список диалогов, а не
/// рассказ о приложении. Отметку о показе держим в локальной базе.
class WelcomeScreen extends ConsumerWidget {
  const WelcomeScreen({super.key});

  Future<void> _continue(WidgetRef ref, BuildContext context) async {
    await ref
        .read(databaseProvider)
        .setPref(PrefKeys.welcomeSeen, 'true');
    if (!context.mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const PhoneScreen()),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Tokens.space6),
          child: Column(
            children: [
              const Spacer(flex: 3),
              Container(
                width: 104,
                height: 104,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary,
                  borderRadius: BorderRadius.circular(30),
                ),
                child: const Icon(
                  MayakIcons.chat,
                  size: 48,
                  color: MayakTheme.onAccent,
                ),
              ),
              const SizedBox(height: Tokens.space8),
              Text(
                'Общайся\nбез границ',
                textAlign: TextAlign.center,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: Tokens.space4),
              Text(
                'Быстрый, удобный и надёжный мессенджер '
                'для тебя и твоих близких.',
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  height: 1.5,
                ),
              ),
              const Spacer(flex: 4),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => _continue(ref, context),
                  child: const Text('Начать'),
                ),
              ),
              const SizedBox(height: Tokens.space3),
              TextButton(
                onPressed: () => _continue(ref, context),
                child: const Text('У меня уже есть аккаунт'),
              ),
              const SizedBox(height: Tokens.space5),
            ],
          ),
        ),
      ),
    );
  }
}
