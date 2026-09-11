import { useEffect, useRef, useState } from "react";
import { Pause, Play } from "lucide-react";
import type { Attachment } from "@/lib/types";
import { cn } from "@/lib/utils";

/// Секунды в «м:сс».
function formatSeconds(total: number): string {
  const minutes = Math.floor(total / 60);
  const seconds = Math.floor(total % 60);
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

/// Голосовое сообщение в пузыре.
///
/// Свои кнопки вместо `<audio controls>`: родной проигрыватель браузера
/// занимает вдвое больше места, выглядит в каждом браузере по-своему и
/// тянет за собой громкость и скачивание, которым в пузыре не место.
export function VoiceMessage({
  attachment,
  mine,
}: {
  attachment: Attachment;
  mine: boolean;
}) {
  const audio = useRef<HTMLAudioElement | null>(null);
  const [playing, setPlaying] = useState(false);
  const [at, setAt] = useState(0);

  // Длительность приходит с сервера: её знал тот, кто записывал. Из файла
  // её тоже можно достать, но только после загрузки — а показать надо
  // сразу, ещё до нажатия.
  const total = attachment.duration ?? 0;
  const progress = total > 0 ? Math.min(1, at / total) : 0;

  useEffect(() => {
    const el = audio.current;
    if (!el) return;
    const onTime = () => setAt(el.currentTime);
    const onEnd = () => {
      setPlaying(false);
      setAt(0);
    };
    el.addEventListener("timeupdate", onTime);
    el.addEventListener("ended", onEnd);
    return () => {
      el.removeEventListener("timeupdate", onTime);
      el.removeEventListener("ended", onEnd);
    };
  }, []);

  function toggle() {
    const el = audio.current;
    if (!el) return;
    if (playing) {
      el.pause();
      setPlaying(false);
      return;
    }
    // Остальные проигрывания останавливаем: два голосовых разом — это шум,
    // в котором не разобрать ни одного.
    for (const other of document.querySelectorAll("audio")) {
      if (other !== el) other.pause();
    }
    void el.play().then(() => setPlaying(true));
  }

  return (
    <span className="flex min-w-52 items-center gap-2.5 py-0.5">
      <audio ref={audio} src={attachment.url} preload="none" />

      <button
        type="button"
        onClick={toggle}
        aria-label={playing ? "Пауза" : "Слушать"}
        className={cn(
          "flex size-9 shrink-0 items-center justify-center rounded-full transition-colors duration-150",
          mine ? "bg-accent text-accent-fg" : "bg-elevated text-fg",
        )}
      >
        {playing ? (
          <Pause className="size-4" fill="currentColor" />
        ) : (
          <Play className="size-4 translate-x-px" fill="currentColor" />
        )}
      </button>

      <span className="min-w-0 flex-1">
        {/* Полоска вместо звуковой волны: волну пришлось бы считать из
            файла после загрузки, то есть показывать пустое место до
            первого нажатия. */}
        <span className="block h-1 overflow-hidden rounded-full bg-fg/15">
          <span
            className="block h-full rounded-full bg-accent transition-[width] duration-150"
            style={{ width: `${progress * 100}%` }}
          />
        </span>
        <span className="mt-1 block text-xs tabular-nums text-muted">
          {formatSeconds(playing || at > 0 ? at : total)}
        </span>
      </span>
    </span>
  );
}
