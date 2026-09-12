import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/phone.dart';
import '../../core/providers.dart';
import '../../ui/icons.dart';
import '../../ui/theme.dart';
import '../../data/api/api_client.dart';
import 'code_screen.dart';

/// Ввод номера телефона.
class PhoneScreen extends ConsumerStatefulWidget {
  const PhoneScreen({super.key});

  @override
  ConsumerState<PhoneScreen> createState() => _PhoneScreenState();
}

class _PhoneScreenState extends ConsumerState<PhoneScreen> {
  // Поле начинается с кода страны: человек в России набирает номер, а не
  // выбирает страну, и первое, что он вводит, — своя девятка.
  final _controller = TextEditingController(text: '+7');
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  bool get _looksComplete => phoneIsComplete(_controller.text);

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final phone = phoneForServer(_controller.text);
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
                  // Знак приложения: акцентный круг с первой буквой.
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
                        'T',
                        style: theme.textTheme.headlineMedium?.copyWith(
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Tito',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium?.copyWith(
                      fontFamily: TitoTheme.display,
                    ),
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
                    inputFormatters: const [RuPhoneFormatter()],
                    decoration: const InputDecoration(
                      hintText: '+7 (999) 123-45-67',
                      prefixIcon: Icon(TitoIcons.phone, size: 20),
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
