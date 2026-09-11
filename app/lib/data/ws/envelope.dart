import 'dart:convert';

import '../../core/config.dart';

/// Конверт протокола — зеркало internal/ws/envelope.go на сервере.
///
///     {"v":1,"t":"message.send","id":"c-42","d":{...}}
class Envelope {
  const Envelope({required this.type, this.id, this.data});

  final String type;
  final String? id;
  final Map<String, dynamic>? data;

  static Envelope decode(String raw) {
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return Envelope(
      type: map['t'] as String? ?? '',
      id: map['id'] as String?,
      data: map['d'] as Map<String, dynamic>?,
    );
  }

  String encode() {
    return jsonEncode({
      'v': AppConfig.protocolVersion,
      't': type,
      if (id != null) 'id': id,
      if (data != null) 'd': data,
    });
  }
}

/// Команды клиента.
abstract final class Cmd {
  static const auth = 'auth';
  static const sync = 'sync';
  static const messageSend = 'message.send';
  static const messageEdit = 'message.edit';
  static const messageDelete = 'message.delete';
  static const read = 'read';
  static const typing = 'typing';
  static const chatCreate = 'chat.create';
  static const chatAddMember = 'chat.addMember';
  static const chatLeave = 'chat.leave';
  static const chatPin = 'chat.pin';
  static const chatMute = 'chat.mute';
  static const ping = 'ping';

  // Звонки. Сервер в них только посредник: он сводит две стороны и
  // пересылает описания соединения, а разговор идёт мимо него.
  static const callStart = 'call.start';
  static const callAnswer = 'call.answer';
  static const callIce = 'call.ice';
  static const callHangup = 'call.hangup';
}

/// Ответы и события сервера.
abstract final class Ev {
  static const ack = 'ack';
  static const error = 'error';
  static const pong = 'pong';

  static const ready = 'ready';
  static const syncResult = 'sync.result';
  static const messageNew = 'message.new';
  static const messageEdited = 'message.edited';
  static const messageDeleted = 'message.deleted';
  static const readUpdate = 'read.update';
  static const typing = 'typing';
  static const presence = 'presence';
  static const chatUpdate = 'chat.update';

  static const callIncoming = 'call.incoming';
  static const callAccepted = 'call.accepted';
  static const callIce = 'call.ice';
  static const callEnded = 'call.ended';
}

/// Ошибка, пришедшая от сервера в ответ на команду.
class ProtocolException implements Exception {
  const ProtocolException(this.code, this.message);

  final String code;
  final String message;

  /// Повторять такую команду бессмысленно: результат не изменится.
  bool get isPermanent => const {
    'forbidden',
    'not_found',
    'bad_request',
    'unauthorized',
  }.contains(code);

  @override
  String toString() => 'ProtocolException($code): $message';
}
