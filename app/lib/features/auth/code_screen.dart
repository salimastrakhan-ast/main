import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/api/api_client.dart';
import '../../ui/theme.dart';

/// Ввод кода из SMS.
class CodeScreen extends ConsumerStatefulWidget {
  const CodeScreen({required this.phone, this.devCode, super.key});

  final String phone;
  final String? devCode;

  @override
  ConsumerState<CodeScreen> createState() => _CodeScreenState();
}

class _CodeScreenState extends ConsumerState<CodeScreen> {
  final _controller = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    // В разработке код подставляется сам: вводить его руками при каждом
    // запуске — трата времени.
    if (widget.devCode != null) _controller.text = widget.devCode!;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref
          .read(apiProvider)
          .verifyCode(
            phone: widget.phone,
            code: _controller.text.trim(),
            platform: Theme.of(context).platform.name,
          );
      // Обновление сессии перестроит дерево: появится список чатов.
      ref.invalidate(sessionProvider);
      if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
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
      appBar: AppBar(),
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
                  Text(
                    'Код из SMS',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineSmall,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Отправили на +${widget.phone}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextField(
                    controller: _controller,
                    autofocus: true,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    // Моноширинный: цифры не прыгают по мере ввода.
                    style: const TextStyle(
                      fontFamily: MayakTheme.monoFamily,
                      fontFamilyFallback: MayakTheme.monoFallback,
                      fontSize: 26,
                      letterSpacing: 10,
                    ),
                    inputFormatters: [
                      FilteringTextInputFormatter.digitsOnly,
                      LengthLimitingTextInputFormatter(6),
                    ],
                    decoration: const InputDecoration(hintText: '••••••'),
                    onChanged: (value) {
                      setState(() {});
                      if (value.length == 6) _submit();
                    },
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      _error!,
                      textAlign: TextAlign.center,
                      style: TextStyle(color: theme.colorScheme.error),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: _busy || _controller.text.length < 6
                        ? null
                        : _submit,
                    child: _busy
                        ? const SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Войти'),
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
