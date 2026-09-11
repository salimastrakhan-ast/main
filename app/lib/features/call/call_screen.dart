import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../data/calls/call_service.dart';
import '../../ui/icons.dart';
import '../../ui/parts.dart';
import '../../ui/tokens.dart';

/// Экран разговора.
///
/// Во весь экран, а не полоской сверху: на телефоне звонок — единственное,
/// что нельзя отложить, и всё остальное на это время не нужно. В браузере
/// он окном поверх страницы по той же причине.
class CallScreen extends ConsumerWidget {
  const CallScreen({required this.call, super.key});

  final CallView call;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final service = ref.read(callServiceProvider);
    final incoming = call.state == CallState.incoming;
    final ended = call.state == CallState.ended;

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        child: Column(
          children: [
            const Spacer(flex: 2),
            PersonAvatar(id: call.peerId, name: call.peerName, radius: 56),
            const SizedBox(height: Tokens.space5),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Tokens.space5),
              child: Text(
                call.peerName,
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineSmall,
              ),
            ),
            const SizedBox(height: Tokens.space2),
            _Status(call: call),
            const Spacer(flex: 3),
            Padding(
              padding: const EdgeInsets.only(bottom: Tokens.space6),
              child: ended
                  ? const SizedBox(height: 72)
                  : incoming
                  ? _IncomingButtons(service: service)
                  : _ActiveButtons(call: call, service: service),
            ),
          ],
        ),
      ),
    );
  }
}

/// Подпись под именем: гудки, «входящий», длительность или исход.
class _Status extends StatefulWidget {
  const _Status({required this.call});

  final CallView call;

  @override
  State<_Status> createState() => _StatusState();
}

class _StatusState extends State<_Status> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    // Секундная стрелка идёт только в разговоре: в остальных состояниях
    // обновлять нечего, а таймер будил бы экран впустую.
    if (widget.call.state == CallState.active) {
      _tick = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void didUpdateWidget(_Status old) {
    super.didUpdateWidget(old);
    if (widget.call.state != old.call.state) {
      _tick?.cancel();
      _tick = widget.call.state == CallState.active
          ? Timer.periodic(const Duration(seconds: 1), (_) {
              if (mounted) setState(() {});
            })
          : null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      _text(widget.call),
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }

  static String _text(CallView call) {
    switch (call.state) {
      case CallState.connecting:
        return 'Соединение…';
      case CallState.ringing:
        return 'Вызов…';
      case CallState.incoming:
        return 'Входящий звонок';
      case CallState.active:
        // Считается от соединения, а не от нажатия «позвонить»: гудки
        // разговором не были.
        final since = call.startedAt;
        if (since == null) return '0:00';
        final total = DateTime.now().difference(since).inSeconds;
        final minutes = total ~/ 60;
        final seconds = (total % 60).toString().padLeft(2, '0');
        return '$minutes:$seconds';
      case CallState.ended:
        return switch (call.reason) {
          CallEndReason.declined => 'Звонок отклонён',
          CallEndReason.missed => 'Не ответили',
          CallEndReason.busy => 'Занято',
          CallEndReason.failed => 'Не удалось соединиться',
          CallEndReason.offline => 'Не в сети',
          _ => 'Звонок завершён',
        };
      case CallState.idle:
        return '';
    }
  }
}

class _IncomingButtons extends StatelessWidget {
  const _IncomingButtons({required this.service});

  final CallService service;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          icon: TitoIcons.callEnd,
          label: 'Отклонить',
          color: Theme.of(context).colorScheme.error,
          onPressed: service.decline,
        ),
        _RoundButton(
          icon: TitoIcons.callStart,
          label: 'Ответить',
          color: Tokens.online,
          onPressed: () async {
            try {
              await service.accept();
            } catch (_) {
              if (context.mounted) {
                showMessage(context, 'Нет доступа к микрофону');
              }
            }
          },
        ),
      ],
    );
  }
}

class _ActiveButtons extends StatelessWidget {
  const _ActiveButtons({required this.call, required this.service});

  final CallView call;
  final CallService service;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          icon: call.muted ? TitoIcons.voiceOff : TitoIcons.voice,
          label: call.muted ? 'Включить микрофон' : 'Выключить микрофон',
          color: scheme.surfaceContainerHighest,
          foreground: scheme.onSurface,
          onPressed: () => service.setMuted(!call.muted),
        ),
        _RoundButton(
          icon: TitoIcons.callEnd,
          label: 'Завершить',
          color: scheme.error,
          onPressed: service.hangup,
        ),
        _RoundButton(
          icon: TitoIcons.speaker,
          label: call.speaker ? 'Выключить громкую связь' : 'Громкая связь',
          color: call.speaker ? scheme.primary : scheme.surfaceContainerHighest,
          foreground: call.speaker ? scheme.onPrimary : scheme.onSurface,
          onPressed: () => service.setSpeaker(!call.speaker),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  const _RoundButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onPressed,
    this.foreground,
  });

  final IconData icon;
  final String label;
  final Color color;
  final Color? foreground;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    // IconButton, а не своя связка Semantics + Tooltip + InkWell: та
    // объявляла подпись дважды, и озвучка читала «Завершить Завершить».
    // Tooltip проставляет её сам, и спорить с ним незачем.
    return IconButton(
      onPressed: onPressed,
      tooltip: label,
      icon: Icon(icon, size: 28),
      style: IconButton.styleFrom(
        backgroundColor: color,
        foregroundColor: foreground ?? Theme.of(context).colorScheme.onPrimary,
        fixedSize: const Size(72, 72),
        shape: const CircleBorder(),
      ),
    );
  }
}
