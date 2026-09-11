import {
  ArrowLeft,
  BellOff,
  Languages,
  MoreVertical,
  Phone,
  Pin,
  Volume2,
} from "lucide-react";
import { toast } from "sonner";
import { Composer } from "@/components/composer";
import { MessageList } from "@/components/message-list";
import { AppMark } from "@/components/mark";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuSeparator,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Switch } from "@/components/ui/switch";
import { UserAvatar } from "@/components/user-avatar";
import { chatStatus } from "@/lib/format";
import { t } from "@/lib/i18n";
import { chatTitle, useMessenger } from "@/lib/store";
import type { Chat } from "@/lib/types";
import { cn } from "@/lib/utils";

export function ChatPane() {
  const uiLang = useMessenger((s) => s.uiLang);
  const selectedChatId = useMessenger((s) => s.selectedChatId);
  const draftPeerId = useMessenger((s) => s.draftPeerId);
  const chats = useMessenger((s) => s.chats);
  const contacts = useMessenger((s) => s.contacts);
  const translatingChatId = useMessenger((s) => s.translatingChatId);
  const selectChat = useMessenger((s) => s.selectChat);
  const toggleTranslate = useMessenger((s) => s.toggleTranslate);
  const togglePin = useMessenger((s) => s.togglePin);
  const startCall = useMessenger((s) => s.startCall);
  // Кнопка гаснет, пока идёт другой звонок: второй означал бы два открытых
  // микрофона и путаницу, кому какой ответ.
  const callBusy = useMessenger((s) => s.call !== null);
  const toggleMute = useMessenger((s) => s.toggleMute);

  const opened = chats.find((c) => c.id === selectedChatId);
  // Переписки с человеком может ещё не быть: на сервере она заводится
  // первым сообщением. Пока её нет, показываем ту же панель по собеседнику
  // — иначе с экрана «новый чат» некуда было бы писать.
  const draftPeer = draftPeerId ? contacts[draftPeerId] : undefined;
  const chat: Chat | undefined =
    opened ??
    (draftPeer
      ? {
          id: "",
          kind: "dm",
          title: draftPeer.name,
          peerId: draftPeer.id,
          initials: draftPeer.initials,
          avatar: draftPeer.avatar,
          pinned: false,
          muted: false,
          unread: 0,
          translateOn: false,
          lastMessageAt: Date.now(),
        }
      : undefined);

  if (!chat) {
    return (
      <div className="chat-canvas flex h-full flex-col items-center justify-center gap-4 px-6 text-center">
        <AppMark className="size-16" />
        <div>
          <p className="font-display text-xl font-medium tracking-tight">
            {t(uiLang, "appName")}
          </p>
          <p className="mt-2 max-w-sm text-sm text-muted text-pretty">
            {t(uiLang, "tagline")}
          </p>
          <p className="mt-4 text-sm text-subtle">{t(uiLang, "emptyChat")}</p>
        </div>
      </div>
    );
  }

  const peer = chat.peerId ? contacts[chat.peerId] : undefined;
  const title = chatTitle(chat, uiLang);
  const status = chat.translateOn
    ? t(uiLang, "liveOn")
    : chatStatus(uiLang, chat, contacts);

  return (
    <div className="flex h-full min-h-0 flex-col">
      <header className="flex items-center gap-1 border-b border-border bg-sidebar/95 px-1 py-1.5">
        <Button
          variant="icon"
          size="icon"
          className="md:hidden"
          aria-label={t(uiLang, "back")}
          onClick={() => selectChat(null)}
        >
          <ArrowLeft className="size-5" />
        </Button>

        {chat.kind === "saved" ? (
          <UserAvatar initials={chat.initials} name={title} saved size="sm" />
        ) : (
          <UserAvatar
            src={chat.avatar}
            initials={chat.initials}
            name={title}
            online={peer?.online ?? false}
            size="sm"
          />
        )}

        <div className="min-w-0 flex-1 px-1">
          <p className="truncate text-sm font-medium">{title}</p>
          <p
            className={cn(
              "truncate text-xs",
              chat.translateOn ? "text-accent" : "text-muted",
            )}
          >
            {translatingChatId === chat.id ? t(uiLang, "translating") : status}
          </p>
        </div>

        <label className="mr-1 hidden items-center gap-2 rounded-full bg-elevated px-3 py-1.5 sm:flex">
          <Languages className="size-3.5 text-accent" />
          <span className="text-xs text-muted">
            {t(uiLang, "translateChat")}
          </span>
          <Switch
            checked={chat.translateOn}
            onCheckedChange={() => void toggleTranslate(chat.id)}
            className="h-5 w-8"
          />
        </label>

        <Button
          variant="icon"
          size="icon"
          className="sm:hidden"
          aria-label={t(uiLang, "translateChat")}
          onClick={() => void toggleTranslate(chat.id)}
        >
          <Languages
            className={cn("size-5", chat.translateOn ? "text-accent" : "")}
          />
        </Button>

        {/* Звонок — только в личной переписке: групповым нужен отдельный
            сервер сведения потоков, и кнопка, которая всегда отвечает
            отказом, хуже её отсутствия. */}
        {chat.peerId ? (
          <Button
            variant="icon"
            size="icon"
            aria-label={t(uiLang, "call")}
            title={t(uiLang, "call")}
            disabled={callBusy}
            onClick={() =>
              void startCall(chat.id).catch(() => toast(t(uiLang, "micDenied")))
            }
          >
            <Phone className="size-5" />
          </Button>
        ) : null}

        <DropdownMenu>
          <DropdownMenuTrigger asChild>
            <Button
              variant="icon"
              size="icon"
              aria-label={t(uiLang, "settings")}
            >
              <MoreVertical className="size-5" />
            </Button>
          </DropdownMenuTrigger>
          <DropdownMenuContent align="end">
            <DropdownMenuItem onSelect={() => void toggleTranslate(chat.id)}>
              <Languages className="size-4" />
              {t(uiLang, "translateChat")}
            </DropdownMenuItem>
            <DropdownMenuItem onSelect={() => togglePin(chat.id)}>
              <Pin className="size-4" />
              {chat.pinned ? t(uiLang, "unpin") : t(uiLang, "pin")}
            </DropdownMenuItem>
            <DropdownMenuSeparator />
            <DropdownMenuItem onSelect={() => toggleMute(chat.id)}>
              {chat.muted ? (
                <Volume2 className="size-4" />
              ) : (
                <BellOff className="size-4" />
              )}
              {chat.muted ? t(uiLang, "unmute") : t(uiLang, "mute")}
            </DropdownMenuItem>
          </DropdownMenuContent>
        </DropdownMenu>
      </header>

      <div className="chat-canvas flex min-h-0 flex-1 flex-col">
        <MessageList chatId={chat.id} />
        <Composer chatId={chat.id} />
      </div>
    </div>
  );
}
