import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:tito/core/config.dart';
import 'package:tito/data/ws/envelope.dart';

void main() {
  group('Конверт протокола', () {
    test('кодируется с версией протокола', () {
      final raw = const Envelope(
        type: Cmd.messageSend,
        id: 'c-1',
        data: {'text': 'привет'},
      ).encode();

      final json = jsonDecode(raw) as Map<String, dynamic>;
      expect(json['v'], AppConfig.protocolVersion);
      expect(json['t'], Cmd.messageSend);
      expect(json['id'], 'c-1');
      expect((json['d'] as Map)['text'], 'привет');
    });

    test('у события нет идентификатора запроса', () {
      final json = jsonDecode(const Envelope(type: Ev.typing).encode())
          as Map<String, dynamic>;
      expect(json.containsKey('id'), isFalse);
    });

    test('разбирается ответ сервера', () {
      final envelope = Envelope.decode(
        '{"v":1,"t":"ack","id":"c-7","d":{"message":{"seq":42}}}',
      );
      expect(envelope.type, Ev.ack);
      expect(envelope.id, 'c-7');
      expect((envelope.data!['message'] as Map)['seq'], 42);
    });

    test('переживает кириллицу без потерь', () {
      const text = 'Привет! Как дела? — Ёжик 🦔';
      final decoded = Envelope.decode(
        const Envelope(type: Cmd.messageSend, data: {'text': text}).encode(),
      );
      expect(decoded.data!['text'], text);
    });
  });

  group('Ошибки протокола', () {
    test('отказы по существу повторять бессмысленно', () {
      for (final code in ['forbidden', 'not_found', 'bad_request', 'unauthorized']) {
        expect(
          ProtocolException(code, '').isPermanent,
          isTrue,
          reason: 'ошибка $code не должна ретраиться',
        );
      }
    });

    test('обрыв связи и таймаут стоит повторить', () {
      for (final code in ['offline', 'timeout', 'internal', 'rate_limited']) {
        expect(
          ProtocolException(code, '').isPermanent,
          isFalse,
          reason: 'ошибка $code должна ретраиться',
        );
      }
    });
  });

  group('Адрес сокета', () {
    test('выводится из адреса API', () {
      // Схема обязана переключаться вместе с HTTP: ws поверх https браузер
      // не пустит.
      expect(AppConfig.wsUrl, startsWith('ws'));
      expect(AppConfig.wsUrl, endsWith('/v1/ws'));
    });
  });
}
