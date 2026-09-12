import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tito/data/api/api_client.dart';
import 'package:tito/data/api/session_store.dart';
import 'package:tito/data/calls/call_service.dart';
import 'package:tito/data/ws/envelope.dart';
import 'package:tito/data/ws/transport.dart';

/// Транспорт без сети: события подаёт тест.
class FakeTransport implements MessageTransport {
  final _events = StreamController<Envelope>.broadcast();
  final sent = <Map<String, dynamic>>[];

  @override
  Stream<Envelope> get events => _events.stream;

  @override
  WsStatus get currentState => WsStatus.online;

  @override
  Future<void> Function()? onReady;

  @override
  Future<Map<String, dynamic>> call(String type, Map<String, dynamic> data) async {
    sent.add({'type': type, ...data});
    return <String, dynamic>{};
  }

  @override
  void notify(String type, Map<String, dynamic> data) {
    sent.add({'type': type, ...data});
  }

  void emit(String type, Map<String, dynamic> data) {
    _events.add(Envelope(type: type, data: data));
  }

  Future<void> dispose() => _events.close();
}

void main() {
  // Входящий звонок доходит до экрана, не трогая WebRTC: микрофон
  // запрашивается только при ответе. Поэтому исход звонка проверяется без
  // устройства и без сервера.
  test('после завершения звонка экран разговора уходит сам', () async {
    final ws = FakeTransport();
    final service = CallService(ws: ws, api: ApiClient(sessions: SessionStore()));
    final seen = <CallView?>[];
    final sub = service.calls.listen(seen.add);

    ws.emit(Ev.callIncoming, {
      'call_id': 'call-1',
      'chat_id': 'chat-1',
      'sdp': 'offer',
      'from': {'id': 'user-1', 'display_name': 'Салим'},
    });
    await Future<void>.delayed(Duration.zero);
    expect(service.current?.state, CallState.incoming);

    ws.emit(Ev.callEnded, {'call_id': 'call-1', 'reason': 'hangup'});
    await Future<void>.delayed(Duration.zero);
    expect(service.current?.state, CallState.ended, reason: 'исход виден человеку');

    // Столько экран и держится; дальше он обязан исчезнуть сам — кнопок на
    // нём в этом состоянии нет.
    await Future<void>.delayed(CallService.endedLinger * 2);
    expect(service.current, isNull);
    expect(seen.last, isNull);

    await sub.cancel();
    service.dispose();
    await ws.dispose();
  });
}
