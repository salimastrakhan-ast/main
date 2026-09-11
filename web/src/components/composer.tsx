import { Languages, Loader2, Paperclip, Send, Sparkles, WandSparkles, X } from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { toast } from "sonner";
import { Button } from "@/components/ui/button";
import {
  DropdownMenu,
  DropdownMenuContent,
  DropdownMenuItem,
  DropdownMenuTrigger,
} from "@/components/ui/dropdown-menu";
import { Tooltip, TooltipContent, TooltipTrigger } from "@/components/ui/tooltip";
import { t } from "@/lib/i18n";
import { useMe, useMessenger } from "@/lib/store";
import type { Message } from "@/lib/types";
import { cn } from "@/lib/utils";

type Props = {
  chatId: string;
};

export function Composer({ chatId }: Props) {
  const uiLang = useMessenger((s) => s.uiLang);
  const messages = useMessenger((s) => s.messages);
  const replyToId = useMessenger((s) => s.replyToId);
  const setReplyTo = useMessenger((s) => s.setReplyTo);
  const sendMessage = useMessenger((s) => s.sendMessage);
  const runDraftTool = useMessenger((s) => s.runDraftTool);
  const draftBusy = useMessenger((s) => s.draftBusy);
  const contacts = useMessenger((s) => s.contacts);
  const me = useMe();

  const [value, setValue] = useState("");
  const areaRef = useRef<HTMLTextAreaElement>(null);

  const reply = replyToId ? messages.find((m) => m.id === replyToId) : undefined;

  useEffect(() => {
    const el = areaRef.current;
    if (!el) return;
    el.style.height = "auto";
    el.style.height = `${Math.min(el.scrollHeight, 128)}px`;
  }, [value]);

  useEffect(() => {
    setValue("");
    areaRef.current?.focus();
  }, [chatId]);

  function submit() {
    const text = value.trim();
    if (!text || draftBusy) return;
    void sendMessage(chatId, text);
    setValue("");
  }

  async function onTool(mode: "improve" | "translate" | "reply") {
    if (mode !== "reply" && !value.trim()) {
      toast(t(uiLang, "draftEmpty"));
      return;
    }
    const next = await runDraftTool(mode, value);
    if (!next) {
      toast(t(uiLang, "aiUnavailable"));
      return;
    }
    setValue(next);
    areaRef.current?.focus();
  }

  return (
    <div className="border-t border-border bg-sidebar px-2 py-2 safe-bottom">
      {reply ? (
        <div className="mb-2 flex items-start gap-2 rounded-md bg-elevated px-3 py-2">
          <span className="min-w-0 flex-1">
            <span className="block text-xs font-medium text-accent">
              {senderLabel(me.id, reply, me.name, contacts, uiLang)}
            </span>
            <span className="block truncate text-xs text-muted">{reply.text}</span>
          </span>
          <Button
            variant="icon"
            size="iconSm"
            aria-label={t(uiLang, "cancelReply")}
            onClick={() => setReplyTo(null)}
          >
            <X className="size-4" />
          </Button>
        </div>
      ) : null}

      <div className="flex items-end gap-1.5">
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant="icon"
              size="icon"
              type="button"
              className="shrink-0"
              aria-label={t(uiLang, "attachSoon")}
              onClick={() => toast(t(uiLang, "attachSoon"))}
            >
              <Paperclip className="size-5" />
            </Button>
          </TooltipTrigger>
          <TooltipContent>{t(uiLang, "attachSoon")}</TooltipContent>
        </Tooltip>

        <div className="flex min-w-0 flex-1 items-end rounded-xl bg-elevated px-3 py-1 shadow-[var(--shadow-border)]">
          <textarea
            ref={areaRef}
            id="tito-composer"
            rows={1}
            value={value}
            onChange={(e) => setValue(e.target.value)}
            placeholder={t(uiLang, "typeMessage")}
            className="max-h-32 min-h-9 w-full flex-1 resize-none bg-transparent py-2 text-base leading-snug text-fg placeholder:text-muted outline-none md:text-sm"
            onKeyDown={(e) => {
              if (e.key === "Enter" && !e.shiftKey) {
                e.preventDefault();
                submit();
              }
            }}
          />
          <DropdownMenu>
            <DropdownMenuTrigger asChild>
              <Button
                variant="icon"
                size="iconSm"
                className="mb-0.5 shrink-0"
                aria-label={t(uiLang, "improve")}
                disabled={draftBusy}
              >
                {draftBusy ? (
                  <Loader2 className="size-4 animate-spin" />
                ) : (
                  <Sparkles className="size-4" />
                )}
              </Button>
            </DropdownMenuTrigger>
            <DropdownMenuContent align="end">
              <DropdownMenuItem onSelect={() => void onTool("improve")}>
                <WandSparkles className="size-4" />
                {t(uiLang, "improve")}
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={() => void onTool("translate")}>
                <Languages className="size-4" />
                {t(uiLang, "translateDraft")}
              </DropdownMenuItem>
              <DropdownMenuItem onSelect={() => void onTool("reply")}>
                <Sparkles className="size-4" />
                {t(uiLang, "suggestReply")}
              </DropdownMenuItem>
            </DropdownMenuContent>
          </DropdownMenu>
        </div>

        <Button
          size="icon"
          className={cn("shrink-0 rounded-full", !value.trim() && "opacity-40")}
          disabled={!value.trim() || draftBusy}
          aria-label={t(uiLang, "send")}
          onClick={submit}
        >
          <Send className="size-4" />
        </Button>
      </div>
    </div>
  );
}

function senderLabel(
  meId: string,
  message: Message,
  meName: string,
  contacts: Record<string, { name: string }>,
  uiLang: "ru" | "en",
) {
  if (message.senderId === meId) return t(uiLang, "you");
  return contacts[message.senderId]?.name ?? meName;
}
