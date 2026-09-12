/// Звонок в браузере.
///
/// Вся работа со звуком — на стороне WebRTC: он сам сжимает, шифрует и
/// подстраивается под сеть. Наше дело — свести две стороны через сервер и
/// не мешать.
///
/// Один звонок за раз. Второй в браузере означал бы два открытых микрофона
/// и путаницу, кому какой ответ; в телефоне так же, и люди этого ждут.

import { Cmd, type WsClient } from "./ws";

/// Что происходит со звонком прямо сейчас.
///
/// `ringing` у звонящего и `incoming` у принимающего — разные состояния
/// одного и того же момента: один слышит гудки, другой звонок.
export type CallState =
  | "idle"
  | "ringing"
  | "incoming"
  | "connecting"
  | "active"
  | "ended";

export type CallEndReason =
  | "hangup"
  | "declined"
  | "missed"
  | "busy"
  | "failed"
  | "offline";

/// Сколько звонить, прежде чем считать, что не ответили. Сорок пять секунд —
/// привычная величина: меньше похоже на сбой, больше человек уже не ждёт.
export const RING_TIMEOUT_MS = 45_000;

type Handlers = {
  onState: (state: CallState, reason?: CallEndReason) => void;
  onRemoteStream: (stream: MediaStream) => void;
};

export class CallSession {
  private pc: RTCPeerConnection | null = null;
  private local: MediaStream | null = null;

  /// Кандидаты, пришедшие раньше описания соединения.
  ///
  /// Порядок в сети не гарантирован: ICE-кандидат собеседника обгоняет его
  /// же SDP, и `addIceCandidate` до `setRemoteDescription` бросает
  /// исключение. Поэтому ранние кандидаты придерживаются здесь.
  private early: RTCIceCandidateInit[] = [];

  callId: string | null = null;
  chatId: string | null = null;
  peerId: string | null = null;
  state: CallState = "idle";
  startedAt = 0;

  constructor(
    private readonly ws: WsClient,
    private readonly handlers: Handlers,
  ) {}

  private setState(state: CallState, reason?: CallEndReason) {
    this.state = state;
    if (state === "active" && this.startedAt === 0) this.startedAt = Date.now();
    this.handlers.onState(state, reason);
  }

  /// Готовит соединение: микрофон, адреса серверов, обработчики.
  private async prepare(iceServers: RTCIceServer[]) {
    // Микрофон спрашивается до сигналинга: отказ в разрешении должен
    // остановить звонок здесь, а не после того, как у собеседника
    // зазвонил телефон.
    this.local = await navigator.mediaDevices.getUserMedia({ audio: true });

    const pc = new RTCPeerConnection({ iceServers });
    this.pc = pc;
    for (const track of this.local.getTracks()) pc.addTrack(track, this.local);

    pc.ontrack = (event) => {
      const stream = event.streams[0];
      if (stream) this.handlers.onRemoteStream(stream);
    };

    pc.onicecandidate = (event) => {
      if (!event.candidate || !this.callId) return;
      void this.ws
        .call(Cmd.callIce, {
          call_id: this.callId,
          candidate: event.candidate.candidate,
          sdp_mid: event.candidate.sdpMid ?? "",
          sdp_m_line_index: event.candidate.sdpMLineIndex ?? 0,
        })
        .catch(() => {
          // Один потерянный кандидат — не беда: их десятки, и соединение
          // встанет на любом другом.
        });
    };

    pc.onconnectionstatechange = () => {
      if (pc.connectionState === "connected") this.setState("active");
      // `disconnected` — часто временная потеря сети, WebRTC восстановится
      // сам. А вот `failed` — это конец: перебор кандидатов закончился, и
      // сказать об этом человеку надо словами.
      if (pc.connectionState === "failed") this.finish("failed");
    };
  }

  /// Звоним сами.
  ///
  /// Чата может ещё не быть — человека только что нашли в поиске. Тогда
  /// уходит собеседник, и сервер заводит переписку сам, как при отправке
  /// первого сообщения.
  async start(chatId: string, peerId: string, iceServers: RTCIceServer[]) {
    this.chatId = chatId;
    this.peerId = peerId;
    this.setState("connecting");

    await this.prepare(iceServers);
    const pc = this.pc;
    if (!pc) return;

    const offer = await pc.createOffer({ offerToReceiveAudio: true });
    await pc.setLocalDescription(offer);

    const reply = await this.ws.call(Cmd.callStart, {
      ...(chatId ? { chat_id: chatId } : { peer_id: peerId }),
      sdp: offer.sdp ?? "",
    });
    const startedId = String(reply.call_id ?? "");

    // Пока сервер отвечал, человек мог нажать «Завершить»: разрешение на
    // микрофон и ответ сервера занимают секунды. Тогда звонок уже завершён
    // здесь, а у собеседника телефон только зазвонил — его надо отбить,
    // иначе он звонит все 45 секунд в пустоту.
    if (this.state === "ended" || this.state === "idle") {
      if (startedId) {
        void this.ws
          .call(Cmd.callHangup, { call_id: startedId, reason: "hangup" })
          .catch(() => {});
      }
      return;
    }

    this.callId = startedId;
    // Чат мог быть заведён этим же звонком: до него переписки не было.
    this.chatId = String(reply.chat_id ?? chatId);

    if (reply.status === "offline") {
      this.finish("offline");
      return;
    }
    this.setState("ringing");
  }

  /// Нам звонят: запоминаем предложение и ждём, что решит человек.
  ///
  /// Микрофон здесь не трогается намеренно. Спросить разрешение до того,
  /// как человек снял трубку, значит включить микрофон у того, кто,
  /// возможно, отклонит звонок.
  receive(callId: string, chatId: string, peerId: string, offerSdp: string) {
    this.callId = callId;
    this.chatId = chatId;
    this.peerId = peerId;
    this.pendingOffer = offerSdp;
    this.setState("incoming");
  }

  private pendingOffer = "";

  /// Снимаем трубку.
  async accept(iceServers: RTCIceServer[]) {
    if (!this.callId || !this.pendingOffer) return;
    this.setState("connecting");

    await this.prepare(iceServers);
    const pc = this.pc;
    if (!pc) return;

    await pc.setRemoteDescription({ type: "offer", sdp: this.pendingOffer });
    await this.drainEarly();

    const answer = await pc.createAnswer();
    await pc.setLocalDescription(answer);
    await this.ws.call(Cmd.callAnswer, {
      call_id: this.callId,
      sdp: answer.sdp ?? "",
    });
  }

  /// Собеседник снял трубку — принимаем его описание соединения.
  async accepted(sdp: string) {
    const pc = this.pc;
    if (!pc) return;
    await pc.setRemoteDescription({ type: "answer", sdp });
    await this.drainEarly();
  }

  async addCandidate(candidate: RTCIceCandidateInit) {
    const pc = this.pc;
    if (!pc) return;
    if (!pc.remoteDescription) {
      this.early.push(candidate);
      return;
    }
    try {
      await pc.addIceCandidate(candidate);
    } catch {
      // Негодный кандидат — обычное дело: сеть могла исчезнуть, пока он
      // ехал. Соединение встанет на другом.
    }
  }

  private async drainEarly() {
    const pc = this.pc;
    if (!pc) return;
    const waiting = this.early;
    this.early = [];
    for (const candidate of waiting) {
      try {
        await pc.addIceCandidate(candidate);
      } catch {
        // См. addCandidate.
      }
    }
  }

  /// Кладём трубку сами — с уведомлением собеседника.
  hangup(reason: CallEndReason = "hangup") {
    if (this.callId) {
      void this.ws
        .call(Cmd.callHangup, { call_id: this.callId, reason })
        .catch(() => {
          // Сокет мог уже оборваться. Локально звонок всё равно закончен, а
          // у собеседника он отвалится по своему таймауту.
        });
    }
    this.finish(reason);
  }

  /// Звонок закончился — с нашей стороны или с той.
  finish(reason: CallEndReason) {
    this.release();
    this.setState("ended", reason);
  }

  /// Отпускает микрофон.
  ///
  /// Именно stop() у каждой дорожки, а не только закрытие соединения: иначе
  /// красный огонёк записи в браузере горит и после разговора, и человек
  /// справедливо решает, что его слушают.
  private release() {
    this.local?.getTracks().forEach((track) => track.stop());
    this.local = null;
    this.pc?.close();
    this.pc = null;
    this.early = [];
    this.pendingOffer = "";
  }

  /// Выключить и включить свой микрофон посреди разговора.
  setMuted(muted: boolean) {
    this.local?.getAudioTracks().forEach((track) => {
      track.enabled = !muted;
    });
  }

  reset() {
    this.release();
    this.callId = null;
    this.chatId = null;
    this.peerId = null;
    this.startedAt = 0;
    this.state = "idle";
  }
}
