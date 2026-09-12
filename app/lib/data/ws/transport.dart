import 'envelope.dart';

/// Что репозиторию нужно от соединения.
///
/// Интерфейс существует ради тестов: подменив его, поведение очереди
/// отправки можно проверить без сервера и сети — а именно очередь отвечает
/// за то, что написанное не теряется.
abstract interface class MessageTransport {
  /// События от сервера, не привязанные к командам.
  Stream<Envelope> get events;

  /// Текущее состояние соединения.
  WsStatus get currentState;

  /// Вызывается после успешной авторизации соединения.
  set onReady(Future<void> Function()? callback);

  /// Отправляет команду и ждёт ответ именно на неё.
  Future<Map<String, dynamic>> call(String type, Map<String, dynamic> data);

  /// Отправляет команду, не дожидаясь ответа.
  void notify(String type, Map<String, dynamic> data);
}

/// Состояние соединения.
///
/// Названо не ConnectionState: так называется перечисление во Flutter, и
/// импорт material.dart рядом стал бы неоднозначным.
enum WsStatus { offline, connecting, online }
