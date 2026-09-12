import 'dart:async';

import 'package:flutter_webrtc/flutter_webrtc.dart';

import '../api/api_client.dart';
import '../ws/envelope.dart';
import '../ws/transport.dart';

/// Звонок на телефоне.
///
/// Повторяет `web/src/lib/calls.ts`: тот же порядок согласования, те же
/// причины завершения, та же осторожность с микрофоном. Расхождение между
/// клиентами здесь означало бы, что звонок с телефона в браузер ведёт себя
/// иначе, чем обратно, — а так быть не должно.
///
/// Один звонок за раз. Второй означал бы два открытых микрофона и путаницу,
/// кому какой ответ.

/// Что происходит со звонком прямо сейчас.
///
/// `ringing` у звонящего и `incoming` у принимающего — разные состояния
/// одного момента: один слышит гудки, другой звонок.
enum CallState { idle, ringing, incoming, connecting, active, ended }

enum CallEndReason { hangup, declined, missed, busy, failed, offline }

CallEndReason _reasonFrom(String? raw) => switch (raw) {
  'declined' => CallEndReason.declined,
  'missed' => CallEndReason.missed,
  'busy' => CallEndReason.busy,
  'failed' => CallEndReason.failed,
  'offline' => CallEndReason.offline,
  _ => CallEndReason.hangup,
};

String _reasonTo(CallEndReason reason) => reason.name;

/// Звонок глазами экрана.
class CallView {
  const CallView({
    required this.peerId,
    required this.peerName,
    required this.outgoing,
    required this.state,
    this.chatId,
    this.reason,
    this.muted = false,
    this.speaker = false,
    this.startedAt,
  });

  final String peerId;
  final String peerName;
  final String? chatId;

  /// Мы звоним или нам звонят. Видно и по состоянию, но различие переживает
  /// переход в разговор, где состояния уже одинаковы.
  final bool outgoing;
  final CallState state;
  final CallEndReason? reason;
  final bool muted;

  /// Громкая связь. На телефоне разговор по умолчанию идёт в разговорный
  /// динамик — тот, что у уха; иначе человек подносит трубку и не слышит.
  final bool speaker;
  final DateTime? startedAt;

  CallView copyWith({
    CallState? state,
    CallEndReason? reason,
    bool? muted,
    bool? speaker,
    DateTime? startedAt,
    String? chatId,
  }) {
    return CallView(
      peerId: peerId,
      peerName: peerName,
      chatId: chatId ?? this.chatId,
      outgoing: outgoing,
      state: state ?? this.state,
      reason: reason ?? this.reason,
      muted: muted ?? this.muted,
      speaker: speaker ?? this.speaker,
      startedAt: startedAt ?? this.startedAt,
    );
  }
}

/// Сколько звонить, прежде чем считать, что не ответили.
const ringTimeout = Duration(seconds: 45);

class CallService {
  CallService({required this.ws, required this.api}) {
    _events = ws.events.listen(_onEvent);
  }

  final MessageTransport ws;
  final ApiClient api;

  late final StreamSubscription<Envelope> _events;

  final _state = StreamController<CallView?>.broadcast();
  Stream<CallView?> get calls => _state.stream;

  CallView? _current;
  CallView? get current => _current;

  RTCPeerConnection? _pc;
  MediaStream? _local;
  String? _callId;

  /// Кандидаты, пришедшие раньше описания соединения.
  ///
  /// Порядок в сети не гарантирован: кандидат обгоняет SDP, а добавить его
  /// до описания нельзя — WebRTC бросит исключение.
  final _early = <RTCIceCandidate>[];
  String _pendingOffer = '';
  Timer? _ringTimer;
  Timer? _dismissTimer;

  /// Сколько экран с исходом висит перед тем, как уйти сам.
  ///
  /// Столько же держится окно в вебе: «занято» и «не отвечает» человек должен
  /// успеть прочитать. Без этого экран разговора остаётся на месте навсегда —
  /// кнопок на нём в этом состоянии нет, и выйти из приложения некуда.
  static const endedLinger = Duration(milliseconds: 2500);

  void dispose() {
    unawaited(_events.cancel());
    _clearDismiss();
    _release();
    unawaited(_state.close());
  }

  void _emit(CallView? view) {
    _current = view;
    if (!_state.isClosed) _state.add(view);
  }

  // --- Исходящий ---

  /// Звоним человеку.
  ///
  /// Чата может ещё не быть — человека нашли в поиске. Тогда уходит
  /// собеседник, и сервер заводит переписку сам.
  Future<void> start({
    required String peerId,
    required String peerName,
    String? chatId,
  }) async {
    if (_current != null) return;
    _emit(CallView(
      peerId: peerId,
      peerName: peerName,
      chatId: chatId,
      outgoing: true,
      state: CallState.connecting,
    ));

    try {
      await _prepare();
      final offer = await _pc!.createOffer({'offerToReceiveAudio': true});
      await _pc!.setLocalDescription(offer);

      final reply = await ws.call(Cmd.callStart, {
        if (chatId != null && chatId.isNotEmpty) 'chat_id': chatId else 'peer_id': peerId,
        'sdp': offer.sdp ?? '',
      });
      _callId = reply['call_id'] as String?;
      // Чат мог быть заведён этим же звонком: до него переписки не было.
      final realChat = reply['chat_id'] as String?;
      if (realChat != null && realChat.isNotEmpty) {
        _emit(_current?.copyWith(chatId: realChat));
      }

      if (reply['status'] == 'offline') {
        _finish(CallEndReason.offline);
        return;
      }
      _emit(_current?.copyWith(state: CallState.ringing));
      _armRingTimeout();
    } catch (_) {
      // Отказ в микрофоне выглядит именно так. Молчать нельзя: человек
      // нажал «позвонить» и должен узнать, почему не вышло.
      _finish(CallEndReason.failed);
      rethrow;
    }
  }

  // --- Входящий ---

  /// Снимаем трубку.
  Future<void> accept() async {
    if (_current?.state != CallState.incoming || _pendingOffer.isEmpty) return;
    _clearRingTimeout();
    _emit(_current?.copyWith(state: CallState.connecting));

    try {
      await _prepare();
      await _pc!.setRemoteDescription(RTCSessionDescription(_pendingOffer, 'offer'));
      await _drainEarly();

      final answer = await _pc!.createAnswer();
      await _pc!.setLocalDescription(answer);
      await ws.call(Cmd.callAnswer, {
        'call_id': _callId,
        'sdp': answer.sdp ?? '',
      });
    } catch (_) {
      hangup(CallEndReason.failed);
    }
  }

  void decline() => hangup(CallEndReason.declined);

  /// Кладём трубку сами.
  void hangup([CallEndReason reason = CallEndReason.hangup]) {
    _clearRingTimeout();
    final id = _callId;
    if (id != null) {
      unawaited(
        ws.call(Cmd.callHangup, {'call_id': id, 'reason': _reasonTo(reason)}).catchError(
          // Соединение могло уже оборваться. Локально звонок всё равно
          // закончен, а у собеседника он отвалится по своему таймауту.
          (_) => <String, dynamic>{},
        ),
      );
    }
    _finish(reason);
  }

  /// Убирает окно разговора после того, как человек увидел исход.
  void dismiss() {
    _clearRingTimeout();
    _clearDismiss();
    _release();
    _emit(null);
  }

  Future<void> setMuted(bool muted) async {
    for (final track in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enabled = !muted;
    }
    _emit(_current?.copyWith(muted: muted));
  }

  /// Громкая связь.
  Future<void> setSpeaker(bool on) async {
    for (final track in _local?.getAudioTracks() ?? const <MediaStreamTrack>[]) {
      track.enableSpeakerphone(on);
    }
    _emit(_current?.copyWith(speaker: on));
  }

  // --- Внутреннее ---

  Future<void> _prepare() async {
    // Микрофон спрашивается до сигналинга: отказ в разрешении должен
    // остановить звонок здесь, а не после того, как у собеседника
    // зазвонил телефон.
    _local = await navigator.mediaDevices.getUserMedia({'audio': true, 'video': false});

    final servers = await _iceServers();
    final pc = await createPeerConnection({'iceServers': servers});
    _pc = pc;

    for (final track in _local!.getTracks()) {
      await pc.addTrack(track, _local!);
    }

    pc.onIceCandidate = (candidate) {
      final id = _callId;
      if (id == null) return;
      unawaited(
        ws.call(Cmd.callIce, {
          'call_id': id,
          'candidate': candidate.candidate ?? '',
          'sdp_mid': candidate.sdpMid ?? '',
          'sdp_m_line_index': candidate.sdpMLineIndex ?? 0,
        }).catchError(
          // Один потерянный кандидат — не беда: их десятки, и соединение
          // встанет на любом другом.
          (_) => <String, dynamic>{},
        ),
      );
    };

    pc.onConnectionState = (state) {
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _clearRingTimeout();
        _emit(_current?.copyWith(
          state: CallState.active,
          startedAt: _current?.startedAt ?? DateTime.now(),
        ));
      }
      // `disconnected` — часто временная потеря сети, WebRTC восстановится
      // сам. А `failed` — это конец, и сказать об этом надо словами.
      if (state == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _finish(CallEndReason.failed);
      }
    };
  }

  /// Адреса серверов. Без TURN звонок встанет не у всех, но встанет —
  /// поэтому отказ сервера в списке не повод не звонить.
  Future<List<Map<String, dynamic>>> _iceServers() async {
    try {
      final raw = await api.iceServers();
      return raw.cast<Map<String, dynamic>>();
    } catch (_) {
      return const [];
    }
  }

  void _onEvent(Envelope envelope) {
    final data = envelope.data ?? const <String, dynamic>{};
    switch (envelope.type) {
      case Ev.callIncoming:
        _onIncoming(data);
      case Ev.callAccepted:
        unawaited(_onAccepted(data));
      case Ev.callIce:
        unawaited(_onCandidate(data));
      case Ev.callEnded:
        if (data['call_id'] == _callId) {
          _finish(_reasonFrom(data['reason'] as String?));
        }
    }
  }

  void _onIncoming(Map<String, dynamic> data) {
    final callId = data['call_id'] as String?;
    final from = data['from'] as Map<String, dynamic>?;
    if (callId == null || from == null) return;

    // Заняты — отклоняем сразу, а не даём второму звонку перебить первый.
    // Звонящий услышит «занято», как и ждёт.
    if (_current != null) {
      unawaited(
        ws.call(Cmd.callHangup, {
          'call_id': callId,
          'reason': _reasonTo(CallEndReason.busy),
        }).catchError((_) => <String, dynamic>{}),
      );
      return;
    }

    _callId = callId;
    _pendingOffer = data['sdp'] as String? ?? '';
    _emit(CallView(
      peerId: from['id'] as String? ?? '',
      peerName: from['display_name'] as String? ?? 'Неизвестный',
      chatId: data['chat_id'] as String?,
      outgoing: false,
      state: CallState.incoming,
    ));
    _armRingTimeout();
  }

  Future<void> _onAccepted(Map<String, dynamic> data) async {
    if (data['call_id'] != _callId) return;
    _clearRingTimeout();
    final pc = _pc;
    if (pc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(data['sdp'] as String? ?? '', 'answer'),
    );
    await _drainEarly();
  }

  Future<void> _onCandidate(Map<String, dynamic> data) async {
    if (data['call_id'] != _callId) return;
    final candidate = RTCIceCandidate(
      data['candidate'] as String? ?? '',
      data['sdp_mid'] as String?,
      (data['sdp_m_line_index'] as num?)?.toInt(),
    );

    final pc = _pc;
    if (pc == null || (await pc.getRemoteDescription()) == null) {
      _early.add(candidate);
      return;
    }
    try {
      await pc.addCandidate(candidate);
    } catch (_) {
      // Негодный кандидат — обычное дело: сеть могла исчезнуть, пока он
      // ехал. Соединение встанет на другом.
    }
  }

  Future<void> _drainEarly() async {
    final pc = _pc;
    if (pc == null) return;
    final waiting = List<RTCIceCandidate>.from(_early);
    _early.clear();
    for (final candidate in waiting) {
      try {
        await pc.addCandidate(candidate);
      } catch (_) {
        // См. _onCandidate.
      }
    }
  }

  void _finish(CallEndReason reason) {
    _release();
    _emit(_current?.copyWith(state: CallState.ended, reason: reason));
    _armDismiss();
  }

  void _armDismiss() {
    _clearDismiss();
    _dismissTimer = Timer(endedLinger, () {
      // Мог начаться новый звонок: тогда убирать нечего.
      if (_current?.state == CallState.ended) dismiss();
    });
  }

  void _clearDismiss() {
    _dismissTimer?.cancel();
    _dismissTimer = null;
  }

  /// Отпускает микрофон.
  ///
  /// Именно stop() у каждой дорожки, а не только закрытие соединения: иначе
  /// значок записи в строке состояния горит и после разговора, и человек
  /// справедливо решает, что его слушают.
  void _release() {
    for (final track in _local?.getTracks() ?? const <MediaStreamTrack>[]) {
      unawaited(track.stop());
    }
    unawaited(_local?.dispose());
    _local = null;
    unawaited(_pc?.close());
    _pc = null;
    _early.clear();
    _pendingOffer = '';
    _callId = null;
  }

  void _armRingTimeout() {
    _clearRingTimeout();
    _ringTimer = Timer(ringTimeout, () {
      final state = _current?.state;
      if (state == CallState.ringing || state == CallState.incoming) {
        hangup(CallEndReason.missed);
      }
    });
  }

  void _clearRingTimeout() {
    _ringTimer?.cancel();
    _ringTimer = null;
  }
}
