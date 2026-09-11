/// Соединение с сервером.
///
/// Отвечает за три вещи, которые в живой сети происходят постоянно:
/// переподключение с нарастающей паузой, сопоставление ответов с командами и
/// heartbeat, который замечает молча умершее соединение.
///
/// Повторяет `app/lib/data/ws/ws_client.dart` — те же паузы, тот же конверт,
/// те же коды ошибок.

import { api, freshAccessToken } from "./api";

/// Конверт протокола: версия, тип, идентификатор запроса, данные.
///
/// Версия — первое поле не случайно: по ней сервер решает, как читать
/// остальное, и старый клиент можно отвергнуть, не разбирая кадр целиком.
export type Envelope = {
  v: number;
  t: string;
  id?: string;
  d?: Record<string, unknown>;
};

export const Cmd = {
  auth: "auth",
  sync: "sync",
  messageSend: "message.send",
  messageEdit: "message.edit",
  messageDelete: "message.delete",
  read: "read",
  typing: "typing",
  chatCreate: "chat.create",
  chatAddMember: "chat.addMember",
  chatLeave: "chat.leave",
  chatPin: "chat.pin",
  chatMute: "chat.mute",
  ping: "ping",
  callStart: "call.start",
  callAnswer: "call.answer",
  callIce: "call.ice",
  callHangup: "call.hangup",
} as const;

export const Ev = {
  ack: "ack",
  error: "error",
  pong: "pong",
  ready: "ready",
  syncResult: "sync.result",
  messageNew: "message.new",
  messageEdited: "message.edited",
  messageDeleted: "message.deleted",
  readUpdate: "read.update",
  typing: "typing",
  presence: "presence",
  chatUpdate: "chat.update",
  callIncoming: "call.incoming",
  callAccepted: "call.accepted",
  callIce: "call.ice",
  callEnded: "call.ended",
} as const;

export type WsStatus = "offline" | "connecting" | "online";

export class ProtocolError extends Error {
  constructor(
    readonly code: string,
    message: string,
  ) {
    super(message);
    this.name = "ProtocolError";
  }

  /// Стоит ли повторять. Обрыв и таймаут — да; отказ по существу — нет,
  /// повтор даст тот же ответ и только задержит очередь.
  get retriable(): boolean {
    return this.code === "offline" || this.code === "timeout";
  }
}

const MIN_BACKOFF = 1_000;
const MAX_BACKOFF = 30_000;
const PING_INTERVAL = 30_000;
const CALL_TIMEOUT = 20_000;

function wsUrl(): string {
  const url = new URL(api.base);
  url.protocol = url.protocol === "https:" ? "wss:" : "ws:";
  url.pathname = "/v1/ws";
  return url.toString();
}

type Pending = {
  resolve: (data: Record<string, unknown>) => void;
  reject: (error: ProtocolError) => void;
  timer: number;
};

export class WsClient {
  private socket: WebSocket | null = null;
  private reconnectTimer = 0;
  private pingTimer = 0;
  private attempt = 0;
  private callSeq = 0;
  private closedByUs = false;

  private readonly pending = new Map<string, Pending>();
  private readonly listeners = new Set<(envelope: Envelope) => void>();
  private readonly stateListeners = new Set<(status: WsStatus) => void>();

  status: WsStatus = "offline";

  /// Вызывается после успешной авторизации соединения — здесь стор
  /// запускает синхронизацию и дошлёт очередь.
  onReady: (() => Promise<void> | void) | null = null;

  onEvent(listener: (envelope: Envelope) => void): () => void {
    this.listeners.add(listener);
    return () => this.listeners.delete(listener);
  }

  onStatus(listener: (status: WsStatus) => void): () => void {
    this.stateListeners.add(listener);
    return () => this.stateListeners.delete(listener);
  }

  connect() {
    this.closedByUs = false;
    if (this.status !== "offline") return;
    void this.open();
  }

  private setStatus(status: WsStatus) {
    if (this.status === status) return;
    this.status = status;
    for (const listener of this.stateListeners) listener(status);
  }

  private async open() {
    this.setStatus("connecting");

    const token = await freshAccessToken();
    if (!token) {
      // Без токена подключаться некуда: человек не вошёл или сессия истекла.
      this.setStatus("offline");
      return;
    }

    let socket: WebSocket;
    try {
      socket = new WebSocket(wsUrl());
    } catch {
      this.scheduleReconnect();
      return;
    }
    this.socket = socket;

    socket.onmessage = (event) => this.onFrame(String(event.data));
    socket.onclose = () => this.scheduleReconnect();
    socket.onerror = () => socket.close();
    socket.onopen = () => {
      // Первый кадр — всегда авторизация: сервер не примет ничего другого,
      // пока не узнает, кто на том конце.
      this.send({ v: 1, t: Cmd.auth, d: { token } });
    };
  }

  private onFrame(raw: string) {
    let envelope: Envelope;
    try {
      envelope = JSON.parse(raw) as Envelope;
    } catch {
      // Нечитаемый кадр — не повод рвать соединение: остальные дойдут.
      return;
    }

    if (envelope.t === Ev.ready) {
      this.attempt = 0;
      this.setStatus("online");
      this.startPing();
      void this.onReady?.();
      return;
    }

    if (envelope.id) {
      const waiting = this.pending.get(envelope.id);
      if (waiting) {
        this.pending.delete(envelope.id);
        window.clearTimeout(waiting.timer);
        if (envelope.t === Ev.error) {
          const error = (envelope.d ?? {}) as { code?: string; message?: string };
          waiting.reject(
            new ProtocolError(error.code ?? "unknown", error.message ?? "Отказ"),
          );
        } else {
          waiting.resolve(envelope.d ?? {});
        }
        return;
      }
    }

    for (const listener of this.listeners) listener(envelope);
  }

  private startPing() {
    window.clearInterval(this.pingTimer);
    // Соединение умирает молча: мобильная сеть закрывает сокет, не сообщая
    // об этом ни одной стороне. Heartbeat — единственный способ заметить.
    this.pingTimer = window.setInterval(() => {
      this.send({ v: 1, t: Cmd.ping });
    }, PING_INTERVAL);
  }

  private scheduleReconnect() {
    window.clearInterval(this.pingTimer);
    this.socket = null;
    this.setStatus("offline");
    this.failPending();
    if (this.closedByUs) return;

    // Пауза растёт вдвое и заканчивается разбросом: без него тысяча
    // клиентов после падения сервера вернётся одной волной и уронит его
    // снова.
    const backoff = Math.min(MIN_BACKOFF * 2 ** this.attempt, MAX_BACKOFF);
    const jitter = Math.random() * backoff * 0.3;
    this.attempt += 1;

    window.clearTimeout(this.reconnectTimer);
    this.reconnectTimer = window.setTimeout(() => void this.open(), backoff + jitter);
  }

  private failPending() {
    for (const [, waiting] of this.pending) {
      window.clearTimeout(waiting.timer);
      waiting.reject(new ProtocolError("offline", "Нет соединения"));
    }
    this.pending.clear();
  }

  private send(envelope: Envelope) {
    this.socket?.send(JSON.stringify(envelope));
  }

  /// Команда с ответом. Отказ приходит тем же идентификатором, поэтому
  /// ожидание всегда завершается — либо ответом, либо таймаутом.
  call(type: string, data: Record<string, unknown> = {}): Promise<Record<string, unknown>> {
    if (this.status !== "online" || !this.socket) {
      return Promise.reject(new ProtocolError("offline", "Нет соединения"));
    }

    const id = `c${++this.callSeq}`;
    return new Promise((resolve, reject) => {
      const timer = window.setTimeout(() => {
        this.pending.delete(id);
        reject(new ProtocolError("timeout", "Сервер не ответил"));
      }, CALL_TIMEOUT);

      this.pending.set(id, { resolve, reject, timer });
      this.send({ v: 1, t: type, id, d: data });
    });
  }

  /// Команда без ответа — «печатает» и подобное: ответ на неё не нужен, а
  /// ожидание висело бы в памяти до таймаута.
  notify(type: string, data: Record<string, unknown> = {}) {
    if (this.status !== "online") return;
    this.send({ v: 1, t: type, d: data });
  }

  close() {
    this.closedByUs = true;
    window.clearTimeout(this.reconnectTimer);
    window.clearInterval(this.pingTimer);
    this.failPending();
    this.socket?.close();
    this.socket = null;
    this.setStatus("offline");
  }
}

export const ws = new WsClient();
