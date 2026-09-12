import type { ReactNode } from "react";
import { useEffect, useRef, useState } from "react";
import {
  Check,
  CheckCheck,
  Copy,
  Languages,
  Pencil,
  PhoneIncoming,
  PhoneMissed,
  PhoneOutgoing,
  Reply,
  Trash2,
} from "lucide-react";
import { toast } from "sonner";
import { AttachmentView } from "@/components/attachment";
import { UserAvatar } from "@/components/user-avatar";
import { dayKey, formatBubbleTime, formatDayLabel } from "@/lib/format";
import { t, targetLangNames } from "@/lib/i18n";
import { useMe, useMessenger } from "@/lib/store";
import type { CallRecord, Message, UiLang } from "@/lib/types";
import { cn } from "@/lib/utils";

export function MessageList({ chatId }: { chatId: string }) {
  const uiLang = useMessenger((s) => s.uiLang);
  const targetLang = useMessenger((s) => s.targetLang);
  const messages = useMessenger((s) => s.messages);
  const chats = useMessenger((s) => s.chats);
  const contacts = useMessenger((s) => s.contacts);
  const me = useMe();
  const typingChatId = useMessenger((s) => s.typingChatId);
  const translatingChatId = useMessenger((s) => s.translatingChatId);
  const revealedOriginal = useMessenger((s) => s.revealedOriginal);
  const setReplyTo = useMessenger((s) => s.setReplyTo);
  const setEditing = useMessenger((s) => s.setEditing);
  const deleteMessage = useMessenger((s) => s.deleteMessage);
  const translateMessage = useMessenger((s) => s.translateMessage);
  const toggleOriginal = useMessenger((s) => s.toggleOriginal);
  const [activeId, setActiveId] = useState<string | null>(null);
  const bottomRef = useRef<HTMLDivElement>(null);

  const chat = chats.find((c) => c.id === chatId);
  const list = messages.filter((m) => m.chatId === chatId);
  const showNames = chat?.kind === "group";

  useEffect(() => {
    bottomRef.current?.scrollIntoView({ behavior: "smooth", block: "end" });
  }, [list.length, typingChatId, chatId]);

  const items: Array<{ type: "day"; key: string; label: string } | { type: "msg"; key: string; message: Message }> =
    [];
  let lastDay = "";
  for (const message of list) {
    const key = dayKey(message.createdAt);
    if (key !== lastDay) {
      items.push({ type: "day", key: `d-${key}`, label: formatDayLabel(message.createdAt, uiLang) });
      lastDay = key;
    }
    items.push({ type: "msg", key: message.id, message });
  }

  return (
    <div className="scroll-thin flex min-h-0 flex-1 flex-col overflow-y-auto px-3 py-4">
      <div className="mt-auto flex flex-col gap-1.5">
        {items.map((item) => {
          if (item.type === "day") {
            return (
              <div key={item.key} className="my-2 flex justify-center">
                <span className="rounded-full bg-elevated/80 px-3 py-1 text-xs text-muted">
                  {item.label}
                </span>
              </div>
            );
          }
          const message = item.message;
          const mine = message.senderId === me.id;

          // Запись о звонке — не сообщение: её никто не писал, отвечать на
          // неё и править нечего. Поэтому отдельная строка посередине, как
          // разделитель даты, а не пузырь с хвостиком.
          if (message.call) {
            return (
              <CallRow
                key={message.id}
                record={message.call}
                outgoing={mine}
                at={message.createdAt}
                lang={uiLang}
              />
            );
          }

          const sender = mine ? me : contacts[message.senderId];
          const live = Boolean(chat?.translateOn && !mine);
          const tr = message.translations?.[targetLang];
          const showOriginal = revealedOriginal[message.id];
          const body = live && tr && !showOriginal ? tr.text : message.text;
          const reply = message.replyToId
            ? messages.find((m) => m.id === message.replyToId)
            : undefined;

          return (
            <div
              key={message.id}
              className={cn("group flex gap-2", mine ? "flex-row-reverse" : "flex-row")}
            >
              {showNames && !mine ? (
                <UserAvatar
                  src={sender?.avatar}
                  initials={sender?.initials ?? "?"}
                  name={sender?.name ?? ""}
                  size="sm"
                  className="mt-auto"
                />
              ) : null}

              <div className={cn("flex max-w-bubble flex-col", mine ? "items-end" : "items-start")}>
                {showNames && !mine ? (
                  <span className="mb-0.5 px-1 text-xs font-medium text-accent">
                    {sender?.name}
                  </span>
                ) : null}

                <div
                  className={cn(
                    "relative px-3 pt-2 pb-1.5 text-sm leading-snug text-pretty shadow-[var(--shadow-border)]",
                    mine
                      ? "rounded-lg rounded-br-xs bg-bubble-out"
                      : "rounded-lg rounded-bl-xs bg-bubble-in",
                  )}
                  onClick={() => setActiveId((id) => (id === message.id ? null : message.id))}
                >
                  {reply ? (
                    <div className="mb-1.5 border-l-2 border-accent pl-2 text-xs text-muted">
                      <span className="block font-medium text-accent">
                        {reply.senderId === me.id ? t(uiLang, "you") : contacts[reply.senderId]?.name}
                      </span>
                      <span className="line-clamp-2">{reply.text}</span>
                    </div>
                  ) : null}

                  {message.attachments?.length ? (
                    <div className="mb-1.5 flex flex-col gap-1.5">
                      {message.attachments.map((attachment) => (
                        <AttachmentView
                          key={attachment.id}
                          attachment={attachment}
                          uiLang={uiLang}
                          mine={mine}
                        />
                      ))}
                    </div>
                  ) : null}

                  {body || !message.attachments?.length ? (
                    <p className="whitespace-pre-wrap">
                      {body}
                      <span className="inline-flex h-4 w-14" />
                    </p>
                  ) : (
                    // Картинка без подписи: место под время всё равно нужно,
                    // иначе оно ляжет на угол снимка.
                    <p className="h-4 w-14" />
                  )}
                  <span className="absolute right-2 bottom-1 inline-flex items-center gap-1 text-xs tabular-nums text-muted">
                    {live && tr && !showOriginal ? (
                      <Languages className="size-3 opacity-70" />
                    ) : null}
                    {message.editedAt && !message.deleted ? (
                      <span className="opacity-70">{t(uiLang, "edited")}</span>
                    ) : null}
                    {formatBubbleTime(message.createdAt)}
                    {mine ? (
                      message.status === "read" ? (
                        <CheckCheck className="size-3.5 text-accent" />
                      ) : (
                        <Check className="size-3.5" />
                      )
                    ) : null}
                  </span>
                </div>

                {live && tr ? (
                  <button
                    type="button"
                    className="mt-0.5 px-1 text-xs text-subtle hover:text-muted"
                    onClick={() => toggleOriginal(message.id)}
                  >
                    {showOriginal ? t(uiLang, "showTranslation") : t(uiLang, "showOriginal")}
                    {tr.from && tr.from !== "und"
                      ? ` · ${targetLangNames[targetLang][uiLang]}`
                      : ""}
                  </button>
                ) : null}

                <div
                  className={cn(
                    "mt-0.5 gap-0.5",
                    mine ? "flex-row-reverse" : "flex-row",
                    activeId === message.id ? "flex" : "hidden group-hover:flex",
                  )}
                >
                  <IconAction
                    label={t(uiLang, "reply")}
                    onClick={() => setReplyTo(message.id)}
                  >
                    <Reply className="size-3.5" />
                  </IconAction>
                  <IconAction
                    label={t(uiLang, "copy")}
                    onClick={() => {
                      void navigator.clipboard.writeText(body);
                      toast(t(uiLang, "copied"));
                    }}
                  >
                    <Copy className="size-3.5" />
                  </IconAction>
                  {!mine ? (
                    <IconAction
                      label={t(uiLang, "translate")}
                      onClick={() => void translateMessage(message.id)}
                    >
                      <Languages className="size-3.5" />
                    </IconAction>
                  ) : null}
                  {/* Править и удалять можно только своё — так же решает и
                      сервер, здесь мы лишь не показываем заведомый отказ. */}
                  {mine && !message.deleted ? (
                    <>
                      <IconAction
                        label={t(uiLang, "edit")}
                        onClick={() => setEditing(message.id)}
                      >
                        <Pencil className="size-3.5" />
                      </IconAction>
                      <IconAction
                        label={t(uiLang, "delete")}
                        onClick={() => {
                          if (!window.confirm(t(uiLang, "deleteConfirm"))) return;
                          void deleteMessage(chatId, message.id).catch(() =>
                            toast(t(uiLang, "deleteFailed")),
                          );
                        }}
                      >
                        <Trash2 className="size-3.5" />
                      </IconAction>
                    </>
                  ) : null}
                </div>
              </div>
            </div>
          );
        })}

        {typingChatId === chatId ? (
          <div className="flex">
            <div className="flex items-center gap-1 rounded-lg rounded-bl-xs bg-bubble-in px-3 py-2.5 shadow-[var(--shadow-border)]">
              <span className="typing-dot size-1.5 rounded-full bg-muted" />
              <span className="typing-dot size-1.5 rounded-full bg-muted [animation-delay:120ms]" />
              <span className="typing-dot size-1.5 rounded-full bg-muted [animation-delay:240ms]" />
            </div>
          </div>
        ) : null}

        {translatingChatId === chatId ? (
          <p className="px-1 text-center text-xs text-muted">{t(uiLang, "translating")}</p>
        ) : null}

        <div ref={bottomRef} />
      </div>
    </div>
  );
}

/// Строка о звонке в ленте.
function CallRow({
  record,
  outgoing,
  at,
  lang,
}: {
  record: CallRecord;
  outgoing: boolean;
  at: number;
  lang: UiLang;
}) {
  // Пропущенный для того, кому звонили, — не то же, что для звонившего:
  // один не дозвонился, другой не услышал. Красным он только у второго.
  const missed = record.reason === "missed" || record.reason === "declined";
  const alarming = missed && !outgoing;
  const Icon = missed ? PhoneMissed : outgoing ? PhoneOutgoing : PhoneIncoming;

  return (
    <div className="flex justify-center">
      <span
        className={cn(
          "inline-flex items-center gap-2 rounded-full bg-surface px-3 py-1 text-xs",
          alarming ? "text-danger" : "text-muted",
        )}
      >
        <Icon className="size-3.5" />
        {callLabel(record, outgoing, lang)}
        <span className="text-subtle">{formatBubbleTime(at)}</span>
      </span>
    </div>
  );
}

function callLabel(record: CallRecord, outgoing: boolean, lang: UiLang): string {
  if (record.reason === "declined") {
    return t(lang, outgoing ? "callDeclinedOut" : "callDeclinedIn");
  }
  if (record.reason === "missed" || record.seconds === 0) {
    return t(lang, outgoing ? "callNoAnswer" : "callMissed");
  }
  const minutes = Math.floor(record.seconds / 60);
  const seconds = String(record.seconds % 60).padStart(2, "0");
  return `${t(lang, outgoing ? "callOut" : "callIn")} · ${minutes}:${seconds}`;
}

function IconAction({
  children,
  label,
  onClick,
}: {
  children: ReactNode;
  label: string;
  onClick: () => void;
}) {
  return (
    <button
      type="button"
      aria-label={label}
      onClick={onClick}
      className="flex size-7 items-center justify-center rounded-full bg-elevated text-muted shadow-[var(--shadow-border)] hover:text-fg"
    >
      {children}
    </button>
  );
}
