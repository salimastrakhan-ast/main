import 'dart:async';
import 'dart:math';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../../core/config.dart';
import 'envelope.dart';
import 'transport.dart';

export 'transport.dart' show MessageTransport, WsStatus;

/// Соединение с сервером.
///
/// Отвечает за три вещи, которые в мобильной сети происходят постоянно:
/// переподключение с нарастающей паузой, сопоставление ответов с командами и
/// heartbeat, который замечает молча умершее соединение.
class WsClient implements MessageTransport {
  WsClient({required this.tokenProvider});

  /// Возвращает свежий access-токен. Именно функция, а не строка: токен живёт
  /// пятнадцать минут, а соединение переживает его несколько раз.
  final Future<String?> Function() tokenProvider;

  static const _minBackoff = Duration(seconds: 1);
  static const _maxBackoff = Duration(seconds: 30);
  static const _pingInterval = Duration(seconds: 30);
  static const _callTimeout = Duration(seconds: 20);

  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _subscription;
  Timer? _reconnectTimer;
  Timer? _pingTimer;

  final _events = StreamController<Envelope>.broadcast();
  final _state = StreamController<WsStatus>.broadcast();
  final _pending = <String, Completer<Map<String, dynamic>>>{};

  final _random = Random();
  int _attempt = 0;
  int _callSeq = 0;
  bool _closedByUs = false;
  WsStatus _current = WsStatus.offline;

  @override
  Stream<Envelope> get events => _events.stream;
  Stream<WsStatus> get state => _state.stream;
  @override
  WsStatus get currentState => _current;

  /// Вызывается после успешной авторизации соединения — здесь репозиторий
  /// запускает синхронизацию и дошлёт очередь.
  @override
  Future<void> Function()? onReady;

  Future<void> connect() async {
    _closedByUs = false;
    if (_current != WsStatus.offline) return;
    await _open();
  }

  Future<void> _open() async {
    _setState(WsStatus.connecting);

    final token = await tokenProvider();
    if (token == null) {
      // Без токена подключаться некуда: человек не вошёл или сессия истекла.
      _setState(WsStatus.offline);
      return;
    }

    try {
      final channel = WebSocketChannel.connect(Uri.parse(AppConfig.wsUrl));
      await channel.ready;
      _channel = channel;

      _subscription = channel.stream.listen(
        _onFrame,
        onError: (Object _) => _scheduleReconnect(),
        onDone: _scheduleReconnect,
        cancelOnError: true,
      );

      // Авторизация обязана быть первым кадром: до неё сервер не примет
      // ничего и закроет соединение через несколько секунд.
      _sendRaw(Envelope(type: Cmd.auth, data: {'token': token}));
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _onFrame(dynamic raw) {
    final Envelope envelope;
    try {
      envelope = Envelope.decode(raw as String);
    } catch (_) {
      return; // Битый кадр — не повод рвать соединение.
    }

    if (envelope.type == Ev.ready) {
      _attempt = 0;
      _setState(WsStatus.online);
      _startHeartbeat();
      _events.add(envelope);
      unawaited(onReady?.call() ?? Future.value());
      return;
    }

    // Ответ на команду: будим того, кто её отправил.
    final id = envelope.id;
    if (id != null && _pending.containsKey(id)) {
      final completer = _pending.remove(id)!;
      if (envelope.type == Ev.error) {
        final data = envelope.data ?? const {};
        completer.completeError(
          ProtocolException(
            data['code'] as String? ?? 'unknown',
            data['message'] as String? ?? 'Неизвестная ошибка',
          ),
        );
      } else {
        completer.complete(envelope.data ?? const {});
      }
      return;
    }

    _events.add(envelope);
  }

  /// Отправляет команду и ждёт ответ именно на неё.
  @override
  Future<Map<String, dynamic>> call(String type, Map<String, dynamic> data) {
    if (_current != WsStatus.online) {
      return Future.error(const ProtocolException('offline', 'Нет соединения'));
    }

    final id = 'c-${++_callSeq}';
    final completer = Completer<Map<String, dynamic>>();
    _pending[id] = completer;

    _sendRaw(Envelope(type: type, id: id, data: data));

    return completer.future.timeout(
      _callTimeout,
      onTimeout: () {
        _pending.remove(id);
        // Ответ не пришёл — соединение, скорее всего, уже мертво, просто мы
        // об этом ещё не знаем.
        _scheduleReconnect();
        throw const ProtocolException('timeout', 'Сервер не ответил');
      },
    );
  }

  /// Отправляет команду, не дожидаясь ответа. Для «печатает», у которого
  /// подтверждения нет по устройству протокола.
  @override
  void notify(String type, Map<String, dynamic> data) {
    if (_current != WsStatus.online) return;
    _sendRaw(Envelope(type: type, data: data));
  }

  void _sendRaw(Envelope envelope) {
    try {
      _channel?.sink.add(envelope.encode());
    } catch (_) {
      _scheduleReconnect();
    }
  }

  void _startHeartbeat() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(_pingInterval, (_) async {
      try {
        await call(Cmd.ping, const {});
      } catch (_) {
        // call сам переподключится по таймауту.
      }
    });
  }

  void _scheduleReconnect() {
    _teardown();
    if (_closedByUs) return;

    _setState(WsStatus.offline);
    _failPending();

    // Пауза удваивается до тридцати секунд, плюс случайная добавка: без неё
    // все клиенты, отвалившиеся при перезапуске сервера, вернутся одной
    // волной и положат его снова.
    final base = _minBackoff * pow(2, _attempt).toInt();
    final capped = base > _maxBackoff ? _maxBackoff : base;
    final jitter = Duration(milliseconds: _random.nextInt(1000));
    _attempt = (_attempt + 1).clamp(0, 6);

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(capped + jitter, _open);
  }

  void _failPending() {
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(
          const ProtocolException('offline', 'Соединение потеряно'),
        );
      }
    }
    _pending.clear();
  }

  void _teardown() {
    _pingTimer?.cancel();
    _pingTimer = null;
    _subscription?.cancel();
    _subscription = null;
    _channel?.sink.close();
    _channel = null;
  }

  void _setState(WsStatus next) {
    if (_current == next) return;
    _current = next;
    _state.add(next);
  }

  Future<void> dispose() async {
    _closedByUs = true;
    _reconnectTimer?.cancel();
    _teardown();
    _failPending();
    await _events.close();
    await _state.close();
  }
}
