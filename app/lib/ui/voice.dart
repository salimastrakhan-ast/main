import 'dart:async';

import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

import 'icons.dart';
import 'tokens.dart';

/// Голосовое сообщение в пузыре.
///
/// Свои кнопки, а не системный проигрыватель: тот занимает вдвое больше
/// места и тянет за собой громкость со скачиванием, которым в пузыре не
/// место.
class VoiceBubble extends StatefulWidget {
  const VoiceBubble({
    required this.url,
    required this.seconds,
    required this.isMine,
    super.key,
  });

  final String url;

  /// Длительность с сервера: её знал тот, кто записывал. Показывается до
  /// первого нажатия — иначе непонятно, минуту слушать или три секунды.
  final int seconds;

  final bool isMine;

  @override
  State<VoiceBubble> createState() => _VoiceBubbleState();
}

class _VoiceBubbleState extends State<VoiceBubble> {
  final _player = AudioPlayer();
  StreamSubscription<PlayerState>? _states;
  Duration _at = Duration.zero;
  bool _playing = false;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _player.positionStream.listen((at) {
      if (mounted) setState(() => _at = at);
    });
    _states = _player.playerStateStream.listen((state) {
      if (!mounted) return;
      if (state.processingState == ProcessingState.completed) {
        // Дослушали: возвращаем в начало, иначе следующее нажатие ничего
        // не делает — головка уже в конце.
        _player.seek(Duration.zero);
        _player.pause();
        setState(() {
          _playing = false;
          _at = Duration.zero;
        });
        return;
      }
      setState(() => _playing = state.playing);
    });
  }

  @override
  void dispose() {
    _states?.cancel();
    _player.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    if (_playing) {
      await _player.pause();
      return;
    }
    try {
      // Файл подтягиваем при первом нажатии, а не при отрисовке ленты:
      // иначе открытие переписки тянуло бы все голосовые разом.
      if (!_loaded) {
        await _player.setUrl(widget.url);
        _loaded = true;
      }
      await _player.play();
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('Не удалось включить запись')));
    }
  }

  String _time(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final total = widget.seconds;
    final at = _at.inSeconds;
    final progress = total > 0 ? (at / total).clamp(0.0, 1.0) : 0.0;

    return SizedBox(
      width: 210,
      child: Row(
        children: [
          Material(
            color: widget.isMine ? scheme.primary : scheme.surfaceContainerHighest,
            shape: const CircleBorder(),
            child: InkWell(
              customBorder: const CircleBorder(),
              onTap: _toggle,
              child: Padding(
                padding: const EdgeInsets.all(Tokens.space2 + 2),
                child: Icon(
                  _playing ? TitoIcons.pause : TitoIcons.play,
                  size: 18,
                  color: widget.isMine ? scheme.onPrimary : scheme.onSurface,
                ),
              ),
            ),
          ),
          const SizedBox(width: Tokens.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Полоска вместо звуковой волны: волну пришлось бы считать
                // из файла после загрузки, то есть показывать пустое место
                // до первого нажатия.
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 3,
                    backgroundColor: scheme.onSurface.withValues(alpha: 0.15),
                    color: scheme.primary,
                  ),
                ),
                const SizedBox(height: Tokens.space1 + 2),
                Text(
                  _time(at > 0 ? at : total),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
