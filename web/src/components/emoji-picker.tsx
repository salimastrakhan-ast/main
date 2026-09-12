import { useEffect, useRef, useState } from "react";
import { emojiGroups, recentLimit } from "@/lib/emoji";
import { t } from "@/lib/i18n";
import { useMessenger } from "@/lib/store";
import { cn } from "@/lib/utils";

const RECENT_KEY = "tito.emoji.recent";

/// Недавние живут в браузере, а не на сервере.
///
/// Они про руку, а не про переписку: на чужом устройстве свой список
/// бесполезен, а синхронизировать его — значит возить туда-сюда полсотни
/// байт ради удобства, которое и так восстановится за десяток сообщений.
function readRecent(): string[] {
  try {
    const raw = localStorage.getItem(RECENT_KEY);
    const list = raw ? (JSON.parse(raw) as unknown) : [];
    return Array.isArray(list) ? list.filter((x): x is string => typeof x === "string") : [];
  } catch {
    // Приватное окно, запрещённые куки, переполнение — недавних просто не
    // будет, и это не повод ломать панель.
    return [];
  }
}

function writeRecent(list: string[]) {
  try {
    localStorage.setItem(RECENT_KEY, JSON.stringify(list));
  } catch {
    // См. readRecent.
  }
}

export function EmojiPicker({
  onPick,
  onClose,
}: {
  onPick: (emoji: string) => void;
  onClose: () => void;
}) {
  const uiLang = useMessenger((s) => s.uiLang);
  const [recent, setRecent] = useState<string[]>(() => readRecent());
  const boxRef = useRef<HTMLDivElement>(null);

  // Клик мимо и Escape закрывают панель: она перекрывает ленту, и оставлять
  // её висеть после выбора значит заставлять целиться в крестик.
  useEffect(() => {
    const onDown = (e: MouseEvent) => {
      if (!boxRef.current?.contains(e.target as Node)) onClose();
    };
    const onKey = (e: KeyboardEvent) => {
      if (e.key === "Escape") onClose();
    };
    // Со следующего тика: клик, который её открыл, ещё не завершился.
    const id = window.setTimeout(() => {
      document.addEventListener("mousedown", onDown);
      document.addEventListener("keydown", onKey);
    }, 0);
    return () => {
      window.clearTimeout(id);
      document.removeEventListener("mousedown", onDown);
      document.removeEventListener("keydown", onKey);
    };
  }, [onClose]);

  function pick(emoji: string) {
    onPick(emoji);
    const next = [emoji, ...recent.filter((x) => x !== emoji)].slice(0, recentLimit);
    setRecent(next);
    writeRecent(next);
  }

  return (
    <div
      ref={boxRef}
      role="dialog"
      aria-label={t(uiLang, "emoji")}
      className="absolute right-0 bottom-full z-30 mb-2 w-[min(20rem,calc(100vw-2rem))] rounded-xl bg-sidebar p-2 shadow-float shadow-[var(--shadow-border)]"
    >
      <div className="scroll-thin max-h-72 overflow-y-auto">
        {recent.length > 0 ? (
          <Section title={t(uiLang, "recent")} items={recent} onPick={pick} />
        ) : null}
        {emojiGroups.map((group) => (
          <Section
            key={group.id}
            title={group.title[uiLang]}
            items={group.items}
            onPick={pick}
          />
        ))}
      </div>
    </div>
  );
}

function Section({
  title,
  items,
  onPick,
}: {
  title: string;
  items: string[];
  onPick: (emoji: string) => void;
}) {
  return (
    <section className="mb-1">
      <h3 className="px-1 pt-1 pb-0.5 text-xs font-semibold text-muted">{title}</h3>
      <div className="grid grid-cols-8">
        {items.map((emoji) => (
          <button
            key={emoji}
            type="button"
            onClick={() => onPick(emoji)}
            aria-label={emoji}
            className={cn(
              "flex size-9 items-center justify-center rounded-md text-xl leading-none",
              "transition-colors duration-100 hover:bg-elevated",
            )}
          >
            {emoji}
          </button>
        ))}
      </div>
    </section>
  );
}
