import { useMemo, useState } from "react";
import { ChevronLeft, Image, LogOut, Phone, Search } from "lucide-react";
import { toast } from "sonner";
import { AttachmentView } from "@/components/attachment";
import { UserAvatar } from "@/components/user-avatar";
import { Button } from "@/components/ui/button";
import { chatStatus } from "@/lib/format";
import { t } from "@/lib/i18n";
import { chatTitle, useMessenger } from "@/lib/store";
import type { Chat, Contact } from "@/lib/types";
import { cn } from "@/lib/utils";

/// Сведения о чате: кто это, что в переписке было, что с ней можно сделать.
///
/// Панелью на месте списка, как настройки и новый чат: во Flutter это
/// отдельный экран, но там и переписка занимает весь экран. Складывать сюда
/// модальное окно поверх ленты значило бы прятать то, ради чего сюда зашли.
export function ChatInfoView({ chat }: { chat: Chat }) {
  const uiLang = useMessenger((s) => s.uiLang);
  const contacts = useMessenger((s) => s.contacts);
  const messages = useMessenger((s) => s.messages);
  const setSidebarView = useMessenger((s) => s.setSidebarView);
  const leaveChat = useMessenger((s) => s.leaveChat);
  const startCall = useMessenger((s) => s.startCall);
  const callBusy = useMessenger((s) => s.call !== null);

  const [tab, setTab] = useState<"about" | "media">("about");

  const peer = chat.peerId ? contacts[chat.peerId] : undefined;
  // filter(Boolean) не сужает тип: собеседника может не быть в книге, и
  // такие записи отбрасываются явно.
  const members = useMemo(
    () =>
      (chat.memberIds ?? [])
        .map((id) => contacts[id])
        .filter((person): person is Contact => person !== undefined),
    [chat.memberIds, contacts],
  );

  // Вложения всей переписки — те же, что показывает раздел «медиа» во
  // Flutter. Берём из уже загруженных сообщений: отдельного запроса на
  // сервер для этого нет, и заводить его ради одной панели незачем.
  const attachments = useMemo(
    () =>
      messages
        .filter((m) => m.chatId === chat.id && !m.deleted)
        .flatMap((m) => m.attachments ?? [])
        .reverse(),
    [messages, chat.id],
  );

  async function confirmLeave() {
    if (!window.confirm(t(uiLang, "leaveGroupWhy"))) return;
    try {
      await leaveChat(chat.id);
      setSidebarView("chats");
    } catch {
      toast(t(uiLang, "groupFailed"));
    }
  }

  return (
    <div className="flex h-full min-h-0 flex-col bg-sidebar">
      <header className="flex items-center gap-1 px-2 py-2">
        <Button
          variant="icon"
          size="icon"
          aria-label={t(uiLang, "back")}
          onClick={() => setSidebarView("chats")}
        >
          <ChevronLeft className="size-5" />
        </Button>
        <h1 className="px-1 text-base font-medium">
          {chat.kind === "group"
            ? t(uiLang, "groupInfo")
            : t(uiLang, "profile")}
        </h1>
      </header>

      <div className="scroll-thin min-h-0 flex-1 overflow-y-auto px-3 pb-4">
        <div className="flex flex-col items-center pt-2 pb-4 text-center">
          <UserAvatar
            src={chat.avatar}
            initials={chat.initials}
            name={chatTitle(chat, uiLang)}
            online={peer?.online}
            saved={chat.kind === "saved"}
            size="xl"
          />
          <h2 className="mt-3 text-lg font-medium">
            {chatTitle(chat, uiLang)}
          </h2>
          <p className="mt-0.5 text-sm text-muted">
            {peer?.about || chatStatus(uiLang, chat, contacts)}
          </p>
        </div>

        <div className="flex gap-2">
          {chat.peerId ? (
            <Action
              icon={<Phone className="size-5" />}
              label={t(uiLang, "call")}
              disabled={callBusy}
              onClick={() =>
                void startCall(chat.id).catch(() =>
                  toast(t(uiLang, "micDenied")),
                )
              }
            />
          ) : null}
          <Action
            icon={<Search className="size-5" />}
            label={t(uiLang, "searchInChat")}
            onClick={() => setSidebarView("search")}
          />
          <Action
            icon={<Image className="size-5" />}
            label={t(uiLang, "mediaFiles")}
            onClick={() => setTab(tab === "media" ? "about" : "media")}
          />
        </div>

        {tab === "media" ? (
          <div className="mt-4">
            <p className="px-1 pb-2 text-xs font-semibold text-muted">
              {t(uiLang, "mediaFiles")} · {attachments.length}
            </p>
            {attachments.length === 0 ? (
              <p className="px-1 py-6 text-center text-sm text-subtle">
                {t(uiLang, "nothingFound")}
              </p>
            ) : (
              <div className="flex flex-col gap-2">
                {attachments.map((attachment) => (
                  <AttachmentView
                    key={attachment.id}
                    attachment={attachment}
                    uiLang={uiLang}
                    mine={false}
                  />
                ))}
              </div>
            )}
          </div>
        ) : null}

        {chat.kind === "group" && members.length > 0 ? (
          <div className="mt-4">
            <p className="px-1 pb-1 text-xs font-semibold text-muted">
              {t(uiLang, "membersTitle")} · {members.length + 1}
            </p>
            <ul>
              {members.map((person) => (
                <li key={person.id}>
                  <div className="flex items-center gap-3 rounded-lg px-2 py-2">
                    <UserAvatar
                      src={person.avatar}
                      initials={person.initials}
                      name={person.name}
                      online={person.online}
                      size="sm"
                    />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium">
                        {person.name}
                      </span>
                      <span className="block truncate text-xs text-muted">
                        {person.online ? t(uiLang, "online") : ""}
                      </span>
                    </span>
                  </div>
                </li>
              ))}
            </ul>
          </div>
        ) : null}

        {chat.kind === "group" ? (
          <button
            type="button"
            onClick={() => void confirmLeave()}
            className="mt-4 flex w-full items-center gap-3 rounded-lg px-2 py-2.5 text-left text-sm text-danger transition-colors duration-150 hover:bg-surface"
          >
            <LogOut className="size-5" />
            {t(uiLang, "leaveGroup")}
          </button>
        ) : null}
      </div>
    </div>
  );
}

function Action({
  icon,
  label,
  onClick,
  disabled,
}: {
  icon: React.ReactNode;
  label: string;
  onClick: () => void;
  disabled?: boolean;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      title={label}
      className={cn(
        "flex flex-1 flex-col items-center gap-1 rounded-lg bg-elevated py-3 text-xs transition-colors duration-150",
        disabled ? "text-subtle" : "text-muted hover:bg-surface hover:text-fg",
      )}
    >
      {icon}
      <span className="max-w-full truncate px-1">{label}</span>
    </button>
  );
}
