import { useMemo, useState } from "react";
import { Search, X } from "lucide-react";
import { toast } from "sonner";
import { UserAvatar } from "@/components/user-avatar";
import { t } from "@/lib/i18n";
import { ProtocolError } from "@/lib/ws";
import { chatTitle, useMessenger } from "@/lib/store";

/// Куда переслать.
///
/// Список тех же переписок, что в панели слева, а не отдельная книга
/// контактов: пересылают обычно в то, что под рукой, и лишний уровень
/// «сначала выбери человека» тут не нужен.
export function ForwardDialog({
  messageId,
  onClose,
}: {
  messageId: string;
  onClose: () => void;
}) {
  const uiLang = useMessenger((s) => s.uiLang);
  const chats = useMessenger((s) => s.chats);
  const contacts = useMessenger((s) => s.contacts);
  const forwardMessage = useMessenger((s) => s.forwardMessage);
  const [query, setQuery] = useState("");

  const needle = query.trim().toLowerCase();
  const found = useMemo(
    () =>
      chats.filter((chat) =>
        needle ? chatTitle(chat, uiLang).toLowerCase().includes(needle) : true,
      ),
    [chats, needle, uiLang],
  );

  async function pick(chatId: string) {
    try {
      await forwardMessage(messageId, chatId);
      onClose();
    } catch (error) {
      // Показываем причину отказа словами, а не общее «не удалось»: сервер
      // объясняет, что именно не так, и прятать это значит оставлять
      // человека гадать.
      toast(
        error instanceof ProtocolError
          ? error.message
          : t(uiLang, "sendFailed"),
      );
    }
  }

  return (
    <div
      className="fixed inset-0 z-40 flex items-center justify-center bg-bg/80 p-4"
      onClick={onClose}
    >
      <div
        role="dialog"
        aria-label={t(uiLang, "forwardTo")}
        onClick={(e) => e.stopPropagation()}
        className="flex max-h-[28rem] w-full max-w-sm flex-col rounded-xl bg-sidebar p-3 shadow-float"
      >
        <div className="flex items-center justify-between pb-2">
          <h2 className="text-sm font-medium">{t(uiLang, "forwardTo")}</h2>
          <button
            type="button"
            onClick={onClose}
            aria-label={t(uiLang, "close")}
            className="flex size-8 items-center justify-center rounded-md text-subtle hover:text-fg"
          >
            <X className="size-4" />
          </button>
        </div>

        <label className="relative block pb-2">
          <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 -translate-y-[5px] text-subtle" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t(uiLang, "search")}
            autoFocus
            aria-label={t(uiLang, "search")}
            className="h-9 w-full rounded-md bg-elevated pr-3 pl-9 text-sm text-fg placeholder:text-subtle outline-none focus-visible:ring-2 focus-visible:ring-ring/60"
          />
        </label>

        <div className="scroll-thin min-h-0 flex-1 overflow-y-auto">
          {found.length === 0 ? (
            <p className="py-6 text-center text-sm text-subtle">
              {t(uiLang, "nothingFound")}
            </p>
          ) : (
            <ul>
              {found.map((chat) => (
                <li key={chat.id}>
                  <button
                    type="button"
                    onClick={() => void pick(chat.id)}
                    className="flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left transition-colors duration-150 hover:bg-surface"
                  >
                    <UserAvatar
                      src={chat.avatar}
                      initials={chat.initials}
                      name={chatTitle(chat, uiLang)}
                      online={
                        chat.peerId ? contacts[chat.peerId]?.online : false
                      }
                      saved={chat.kind === "saved"}
                      size="sm"
                    />
                    <span className="min-w-0 flex-1 truncate text-sm">
                      {chatTitle(chat, uiLang)}
                    </span>
                  </button>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </div>
  );
}
