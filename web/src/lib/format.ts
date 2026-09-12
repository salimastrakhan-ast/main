import { format, isToday, isYesterday, isThisYear, differenceInMinutes } from "date-fns";
import { ru, enUS } from "date-fns/locale";
import { t } from "./i18n";
import type { Chat, Contact, UiLang } from "./types";

function locale(lang: UiLang) {
  return lang === "ru" ? ru : enUS;
}

export function formatListTime(ts: number, lang: UiLang): string {
  const d = new Date(ts);
  const loc = locale(lang);
  if (isToday(d)) return format(d, "HH:mm");
  if (isYesterday(d)) return t(lang, "yesterday").toLowerCase();
  if (isThisYear(d)) return format(d, lang === "ru" ? "d MMM" : "MMM d", { locale: loc });
  return format(d, lang === "ru" ? "d.MM.yy" : "MM/dd/yy");
}

export function formatBubbleTime(ts: number): string {
  return format(new Date(ts), "HH:mm");
}

export function formatDayLabel(ts: number, lang: UiLang): string {
  const d = new Date(ts);
  const loc = locale(lang);
  if (isToday(d)) return t(lang, "today");
  if (isYesterday(d)) return t(lang, "yesterday");
  if (isThisYear(d)) return format(d, lang === "ru" ? "d MMMM" : "MMMM d", { locale: loc });
  return format(d, lang === "ru" ? "d MMMM yyyy" : "MMMM d, yyyy", { locale: loc });
}

export function formatLastSeen(
  lang: UiLang,
  contact: Pick<Contact, "online" | "lastSeenAt" | "gender"> | undefined,
): string {
  if (!contact) return "";
  if (contact.online) return t(lang, "online");
  if (!contact.lastSeenAt) return "";
  const d = new Date(contact.lastSeenAt);
  const loc = locale(lang);
  const prefix = contact.gender === "f" ? t(lang, "lastSeenF") : t(lang, "lastSeenM");
  const mins = differenceInMinutes(Date.now(), d);
  if (mins < 1) return `${prefix} ${t(lang, "justNow")}`;
  if (mins < 60) return `${prefix} ${mins} ${t(lang, "minutesAgo")}`;
  if (isToday(d)) return `${prefix} ${t(lang, "at")} ${format(d, "HH:mm")}`;
  if (isYesterday(d)) return `${prefix} ${t(lang, "yesterday").toLowerCase()} ${t(lang, "at")} ${format(d, "HH:mm")}`;
  return `${prefix} ${format(d, lang === "ru" ? "d MMM" : "MMM d", { locale: loc })}`;
}

export function chatStatus(
  lang: UiLang,
  chat: Chat,
  contacts: Record<string, Contact>,
): string {
  if (chat.kind === "ai") return t(lang, "aiStatus");
  if (chat.kind === "saved") return t(lang, "savedStatus");
  if (chat.kind === "group") {
    const n = (chat.memberIds?.length ?? 0) + 1;
    if (lang === "en") return `${n} ${n === 1 ? t(lang, "membersOne") : t(lang, "members")}`;
    const n10 = n % 10;
    const n100 = n % 100;
    const word =
      n10 === 1 && n100 !== 11
        ? t(lang, "membersOne")
        : n10 >= 2 && n10 <= 4 && (n100 < 12 || n100 > 14)
          ? t(lang, "members")
          : t(lang, "membersMany");
    return `${n} ${word}`;
  }
  if (chat.peerId) return formatLastSeen(lang, contacts[chat.peerId]);
  return "";
}

export function dayKey(ts: number): string {
  return format(new Date(ts), "yyyy-MM-dd");
}
