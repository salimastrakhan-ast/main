import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../ui/icons.dart';
import '../../data/api/api_client.dart';
import 'code_screen.dart';

/// Ввод номера телефона.
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  /// Сервер сам приводит номер к единому виду, поэтому здесь достаточно
  /// проверить, что цифр набралось на российский номер.
  bool get _looksComplete =>
      _controller.text.replaceAll(RegExp(r'\D'), '').length >= 10;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = _controller.text;
      final result = await ref.read(apiProvider).requestCode(phone);
      if (!mounted) return;
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => CodeScreen(
            phone: result['phone'] as String? ?? phone,
            // В разработке сервер возвращает код в ответе, чтобы не поднимать
            // SMS-провайдера. В проде поле пустое.
            devCode: result['dev_code'] as String?,
          ),
        ),
      );
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Знак приложения: коралловый круг с первой буквой.
                  // Проще стандартной иконки и сразу узнаётся в тёмной теме.
                  Center(
                    child: Container(
                      width: 64,
                      height: 64,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        'М',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Маяк',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Введите номер телефона',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: TextInputType.phone,
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'[\d+\-() ]')),
                      LengthLimitingTextInputFormatter(20),
                    ],
                    decoration: const InputDecoration(
                      hintText: '+7 999 123-45-67',
                      prefixIcon: Icon(MayakIcons.phone, size: 20),
                    ),
                    onChanged: (_) => setState(() {}),
                    onSubmitted: (_) => _looksComplete ? _submit() : null,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy || !_looksComplete ? null : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Получить код'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
