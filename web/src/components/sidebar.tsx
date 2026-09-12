import {
  Bookmark,
  Menu,
  Pin,
  Search,
  SquarePen,
  X,
} from "lucide-react";
import { UserAvatar } from "@/components/user-avatar";
import { Button } from "@/components/ui/button";
import { AppMark } from "@/components/mark";
import { chatStatus, formatListTime } from "@/lib/format";
import { t } from "@/lib/i18n";
import { chatTitle, lastPreview, useMessenger } from "@/lib/store";
import type { Chat, FolderId } from "@/lib/types";
import { cn } from "@/lib/utils";

const FOLDERS: FolderId[] = ["all", "personal", "groups"];

function matchesFolder(chat: Chat, folder: FolderId) {
  if (folder === "all") return true;
  if (folder === "groups") return chat.kind === "group";
  return chat.kind === "dm" || chat.kind === "saved";
}

export function Sidebar() {
  const uiLang = useMessenger((s) => s.uiLang);
  const folder = useMessenger((s) => s.folder);
  const search = useMessenger((s) => s.search);
  const chats = useMessenger((s) => s.chats);
  const messages = useMessenger((s) => s.messages);
  const contacts = useMessenger((s) => s.contacts);
  const selectedChatId = useMessenger((s) => s.selectedChatId);
  const setFolder = useMessenger((s) => s.setFolder);
  const setSearch = useMessenger((s) => s.setSearch);
  const selectChat = useMessenger((s) => s.selectChat);
  const setSidebarView = useMessenger((s) => s.setSidebarView);

  const q = search.trim().toLowerCase();
  const visible = chats
    .filter((c) => matchesFolder(c, folder))
    .filter((c) => {
      if (!q) return true;
      const preview = lastPreview(messages, c.id, t(uiLang, "you")).toLowerCase();
      return chatTitle(c, uiLang).toLowerCase().includes(q) || preview.includes(q);
    })
    .slice()
    .sort((a, b) => {
      if (!!a.pinned !== !!b.pinned) return a.pinned ? -1 : 1;
      return b.lastMessageAt - a.lastMessageAt;
    });

  return (
    <div className="flex h-full min-h-0 flex-col bg-sidebar">
      <header className="flex items-center gap-1 px-2 pt-2 pb-1">
        <Button
          variant="icon"
          size="icon"
          aria-label={t(uiLang, "openSettings")}
          onClick={() => setSidebarView("settings")}
        >
          <Menu className="size-5" />
        </Button>
        <div className="flex min-w-0 flex-1 items-center gap-2 px-1">
          <AppMark className="size-7" />
          <span className="font-display text-base font-medium tracking-tight">{t(uiLang, "appName")}</span>
        </div>
        <Button
          variant="icon"
          size="icon"
          aria-label={t(uiLang, "newMessage")}
          type="button"
          onClick={() => setSidebarView("new")}
        >
          <SquarePen className="size-5" />
        </Button>
      </header>

      <div className="px-3 pt-1 pb-2">
        <label className="relative block">
          <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-subtle" />
          <input
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            placeholder={t(uiLang, "search")}
            className="h-10 w-full rounded-md bg-elevated pr-9 pl-9 text-sm text-fg placeholder:text-subtle shadow-[var(--shadow-border)] outline-none focus-visible:ring-2 focus-visible:ring-ring/60"
          />
          {search ? (
            <button
              type="button"
              className="absolute top-1/2 right-1 flex size-8 -translate-y-1/2 items-center justify-center rounded-sm text-subtle hover:text-fg"
              onClick={() => setSearch("")}
              aria-label={t(uiLang, "close")}
            >
              <X className="size-4" />
            </button>
          ) : null}
        </label>
      </div>

      <div className="flex gap-1 overflow-x-auto px-3 pb-2">
        {FOLDERS.map((id) => (
          <button
            key={id}
            type="button"
            onClick={() => setFolder(id)}
            className={cn(
              "h-8 shrink-0 rounded-full px-3 text-xs font-medium transition-colors duration-150",
              folder === id
                ? "bg-accent text-accent-fg"
                : "bg-elevated text-muted hover:text-fg",
            )}
          >
            {t(uiLang, id)}
          </button>
        ))}
      </div>

      <div className="scroll-thin min-h-0 flex-1 overflow-y-auto">
        {visible.length === 0 ? (
          <p className="px-4 py-8 text-center text-sm text-muted">
            {q ? t(uiLang, "emptySearch") : t(uiLang, "emptyFolder")}
          </p>
        ) : (
          visible.map((chat) => {
            const preview = lastPreview(messages, chat.id, t(uiLang, "you"));
            const peer = chat.peerId ? contacts[chat.peerId] : undefined;
            const status = chatStatus(uiLang, chat, contacts);
            return (
              <button
                key={chat.id}
                type="button"
                onClick={() => selectChat(chat.id)}
                className={cn(
                  "flex w-full items-center gap-3 px-3 py-2.5 text-left transition-colors duration-150",
                  selectedChatId === chat.id ? "bg-elevated" : "hover:bg-surface",
                )}
              >
                {chat.kind === "saved" ? (
                  <UserAvatar initials={chat.initials} name={chatTitle(chat, uiLang)} saved size="md" />
                ) : (
                  <UserAvatar
                    src={chat.avatar}
                    initials={chat.initials}
                    name={chatTitle(chat, uiLang)}
                    online={peer?.online ?? false}
                    size="md"
                  />
                )}
                <span className="min-w-0 flex-1">
                  <span className="flex items-baseline justify-between gap-2">
                    <span className="truncate text-sm font-medium">
                      {chat.kind === "saved" ? (
                        <span className="inline-flex items-center gap-1">
                          <Bookmark className="size-3.5 text-accent" />
                          {chatTitle(chat, uiLang)}
                        </span>
                      ) : (
                        <span className="inline-flex items-center gap-1">
                          {chatTitle(chat, uiLang)}
                          {chat.pinned ? <Pin className="size-3 text-subtle" /> : null}
                        </span>
                      )}
                    </span>
                    <span className="shrink-0 text-xs tabular-nums text-subtle">
                      {formatListTime(chat.lastMessageAt, uiLang)}
                    </span>
                  </span>
                  <span className="mt-0.5 flex items-center justify-between gap-2">
                    <span className="truncate text-xs text-muted">{preview || status}</span>
                    {chat.unread > 0 ? (
                      <span
                        className={cn(
                          "inline-flex min-w-5 justify-center rounded-full px-1.5 text-xs leading-5 font-medium tabular-nums",
                          chat.muted ? "bg-subtle text-fg" : "bg-accent text-accent-fg",
                        )}
                      >
                        {chat.unread}
                      </span>
                    ) : null}
                  </span>
                </span>
              </button>
            );
          })
        )}
      </div>
    </div>
  );
}
