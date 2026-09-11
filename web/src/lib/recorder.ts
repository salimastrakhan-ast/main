/// Запись голосового сообщения.
///
/// Отдельно от компонента: разрешение на микрофон, поток и таймер живут
/// дольше одного рендера, и держать их в состоянии React значит однажды
/// оставить микрофон включённым после закрытия вкладки.

export type RecorderState = {
  /// Сколько секунд идёт запись. Обновляется раз в секунду.
  seconds: number;
};

/// Что вышло из записи. Пусто — человек отменил или ничего не записалось.
export type Recording = {
  blob: Blob;
  seconds: number;
};

/// Формат записи.
///
/// Opus в контейнере webm: он есть во всех браузерах, где вообще работает
/// MediaRecorder, и даёт вменяемый голос при 24 килобитах — важно для
/// мобильной сети. Safari до недавнего умел только mp4, поэтому формат
/// выбирается из того, что браузер подтверждает сам.
function pickMime(): string {
  const candidates = [
    "audio/webm;codecs=opus",
    "audio/webm",
    "audio/mp4",
    "audio/ogg;codecs=opus",
  ];
  for (const mime of candidates) {
    if (MediaRecorder.isTypeSupported(mime)) return mime;
  }
  return "";
}

export class VoiceRecorder {
  private recorder: MediaRecorder | null = null;
  private stream: MediaStream | null = null;
  private chunks: Blob[] = [];
  private startedAt = 0;
  private ticker = 0;

  /// Идёт ли запись прямо сейчас.
  get active(): boolean {
    return this.recorder !== null;
  }

  /// Начинает запись. Бросает, если человек не дал доступ к микрофону.
  async start(onTick: (seconds: number) => void): Promise<void> {
    if (this.recorder) return;

    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        // Голос, а не музыка: эхо и шум лучше убрать до записи, чем
        // разбираться с ними на той стороне.
        echoCancellation: true,
        noiseSuppression: true,
        autoGainControl: true,
      },
    });

    const mime = pickMime();
    this.recorder = new MediaRecorder(
      this.stream,
      mime ? { mimeType: mime, audioBitsPerSecond: 24000 } : undefined,
    );
    this.chunks = [];
    this.recorder.ondataavailable = (e) => {
      if (e.data.size > 0) this.chunks.push(e.data);
    };
    this.recorder.start();
    this.startedAt = Date.now();

    onTick(0);
    this.ticker = window.setInterval(
      () => onTick(Math.floor((Date.now() - this.startedAt) / 1000)),
      500,
    );
  }

  /// Останавливает запись и отдаёт результат.
  async stop(): Promise<Recording | null> {
    const recorder = this.recorder;
    if (!recorder) return null;

    const seconds = Math.max(1, Math.round((Date.now() - this.startedAt) / 1000));
    const done = new Promise<Blob>((resolve) => {
      recorder.onstop = () =>
        resolve(new Blob(this.chunks, { type: recorder.mimeType }));
    });
    recorder.stop();
    const blob = await done;
    this.release();

    // Меньше секунды — это случайное касание, а не сообщение.
    return blob.size > 0 && seconds >= 1 ? { blob, seconds } : null;
  }

  /// Отменяет запись: результат не нужен, микрофон отпускаем.
  cancel(): void {
    const recorder = this.recorder;
    if (!recorder) return;
    recorder.onstop = null;
    try {
      recorder.stop();
    } catch {
      // Уже остановлен — отпустить поток всё равно надо.
    }
    this.release();
  }

  /// Отпускает микрофон.
  ///
  /// Без этого в браузере остаётся гореть красная точка записи, и человек
  /// справедливо решает, что его слушают.
  private release(): void {
    window.clearInterval(this.ticker);
    this.ticker = 0;
    this.stream?.getTracks().forEach((track) => track.stop());
    this.stream = null;
    this.recorder = null;
    this.chunks = [];
  }
}
