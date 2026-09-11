import { useState } from "react";
import { FileText, ImageOff, Music, Video } from "lucide-react";
import type { Attachment } from "@/lib/types";

/// Человеческий размер файла: «2,4 МБ» вместо 2516582.
function humanSize(bytes: number, uiLang: "ru" | "en"): string {
  const units = uiLang === "ru" ? ["Б", "КБ", "МБ", "ГБ"] : ["B", "KB", "MB", "GB"];
  let value = bytes;
  let unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit += 1;
  }
  const shown = value >= 10 || unit === 0 ? Math.round(value) : value.toFixed(1);
  return `${String(shown).replace(".", uiLang === "ru" ? "," : ".")} ${units[unit]}`;
}

const icons = {
  image: ImageOff,
  video: Video,
  audio: Music,
  file: FileText,
} as const;

/// Вложение в пузыре.
///
/// Картинка показывается сама, остальное — строкой с именем и размером.
/// Ссылка на файл временная: её подписывает сервер при выдаче, и после
/// перезагрузки страницы приезжает новая.
export function AttachmentView({
  attachment,
  uiLang,
}: {
  attachment: Attachment;
  uiLang: "ru" | "en";
}) {
  const [broken, setBroken] = useState(false);
  const Icon = icons[attachment.kind] ?? FileText;

  if (attachment.kind === "image" && attachment.url && !broken) {
    return (
      <img
        src={attachment.url}
        alt={attachment.fileName ?? ""}
        loading="lazy"
        onError={() => setBroken(true)}
        // Не `w-full`: маленькая картинка растянулась бы во всю ширину
        // пузыря и превратилась в мыло.
        className="max-h-80 max-w-full rounded-md object-contain"
      />
    );
  }

  const name = attachment.fileName || (uiLang === "ru" ? "Файл" : "File");

  return (
    <a
      href={attachment.url}
      target="_blank"
      rel="noreferrer"
      className="flex items-center gap-2.5 rounded-md bg-elevated px-2.5 py-2 transition-colors duration-150 hover:bg-surface"
    >
      <span className="flex size-9 shrink-0 items-center justify-center rounded-md bg-surface text-accent">
        <Icon className="size-4" />
      </span>
      <span className="min-w-0">
        <span className="block truncate text-sm">{name}</span>
        <span className="block text-xs text-muted">
          {humanSize(attachment.size, uiLang)}
        </span>
      </span>
    </a>
  );
}
