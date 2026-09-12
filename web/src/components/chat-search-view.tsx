import { useMemo, useState } from "react";
import { ChevronLeft, Search, X } from "lucide-react";
import { formatListTime } from "@/lib/format";
import { t } from "@/lib/i18n";
import { useMe, useMessenger } from "@/lib/store";
import type { Chat } from "@/lib/types";

/// Поиск по переписке.
///
/// Ищет по уже загруженным сообщениям, а не спрашивает сервер: в чате их
/// столько, сколько человек пролистал, и отдельный запрос ради подстроки
/// добавил бы задержку там, где ответ есть мгновенно. Когда переписка
/// станет длиннее памяти клиента, сюда встанет серверный поиск — и это
/// будет видно по тому, что находится не всё.
export function ChatSearchView({ chat }: { chat: Chat }) {
  const uiLang = useMessenger((s) => s.uiLang);
  const me = useMe();
  const contacts = useMessenger((s) => s.contacts);
  const messages = useMessenger((s) => s.messages);
  const setSidebarView = useMessenger((s) => s.setSidebarView);

  const [query, setQuery] = useState("");
  const needle = query.trim().toLowerCase();

  const found = useMemo(() => {
    if (needle.length < 2) return [];
    return messages
      .filter(
        (m) =>
          m.chatId === chat.id &&
          !m.deleted &&
          m.text.toLowerCase().includes(needle),
      )
      .slice()
      .reverse();
  }, [messages, chat.id, needle]);

  return (
    <div className="flex h-full min-h-0 flex-col bg-sidebar">
      <header className="flex items-center gap-1 px-2 py-2">
        <button
          type="button"
          aria-label={t(uiLang, "back")}
          onClick={() => setSidebarView("chats")}
          className="flex size-9 items-center justify-center rounded-md text-muted hover:text-fg"
        >
          <ChevronLeft className="size-5" />
        </button>
        <h1 className="px-1 text-base font-medium">
          {t(uiLang, "searchInChat")}
        </h1>
      </header>

      <div className="px-3 pb-2">
        <label className="relative block">
          <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-subtle" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t(uiLang, "searchInChatHint")}
            autoFocus
            aria-label={t(uiLang, "searchInChat")}
            className="h-10 w-full rounded-md bg-elevated pr-9 pl-9 text-sm text-fg placeholder:text-subtle shadow-[var(--shadow-border)] outline-none focus-visible:ring-2 focus-visible:ring-ring/60"
          />
          {query ? (
            <button
              type="button"
              aria-label={t(uiLang, "close")}
              onClick={() => setQuery("")}
              className="absolute top-1/2 right-1 flex size-8 -translate-y-1/2 items-center justify-center rounded-sm text-subtle hover:text-fg"
            >
              <X className="size-4" />
            </button>
          ) : null}
        </label>
      </div>

      <div className="scroll-thin min-h-0 flex-1 overflow-y-auto px-3 pb-3">
        {found.length === 0 ? (
          <p className="px-1 py-8 text-center text-sm text-subtle">
            {needle.length < 2
              ? t(uiLang, "inThisChat")
              : t(uiLang, "nothingFound")}
          </p>
        ) : (
          <ul>
            {found.map((message) => {
              const mine = message.senderId === me.id;
              const author = mine
                ? t(uiLang, "you")
                : (contacts[message.senderId]?.name ?? "");
              return (
                <li key={message.id}>
                  <div className="rounded-lg px-2 py-2">
                    <div className="flex items-baseline justify-between gap-2">
                      <span className="truncate text-xs font-medium text-accent">
                        {author}
                      </span>
                      <span className="shrink-0 text-xs text-subtle">
                        {formatListTime(message.createdAt, uiLang)}
                      </span>
                    </div>
                    <p className="mt-0.5 line-clamp-2 text-sm text-fg">
                      <Highlighted text={message.text} needle={needle} />
                    </p>
                  </div>
                </li>
              );
            })}
          </ul>
        )}
      </div>
    </div>
  );
}

/// Подсвечивает найденное. Без подсветки в длинном сообщении приходится
/// искать глазами то, что уже нашла машина.
function Highlighted({ text, needle }: { text: string; needle: string }) {
  const at = text.toLowerCase().indexOf(needle);
  if (at < 0) return <>{text}</>;
  return (
    <>
      {text.slice(0, at)}
      <mark className="rounded-xs bg-accent/25 text-fg">
        {text.slice(at, at + needle.length)}
      </mark>
      {text.slice(at + needle.length)}
    </>
  );
}
