import {
  Check,
  Languages,
  Loader2,
  Mic,
  Paperclip,
  Pencil,
  Send,
  Smile,
  Sparkles,
  Trash2,
  WandSparkles,
  X,
} from "lucide-react";
import { useEffect, useRef, useState } from "react";
import { EmojiPicker } from "@/components/emoji-picker";
import { VoiceRecorder } from "@/lib/recorder";
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

type Props = {
  chatId: string;
};

/// Секунды в «м:сс».
function formatSeconds(total: number): string {
  const minutes = Math.floor(total / 60);
  const seconds = total % 60;
  return `${minutes}:${String(seconds).padStart(2, "0")}`;
}

/// Предел размера файла.
///
/// Тот же, что по умолчанию у сервера (`TITO_MAX_UPLOAD_MB`). Проверка
/// здесь — чтобы не гнать мегабайты по сети ради отказа; если на сервере
/// лимит понизили, его ответ всё равно перехватывается ниже.
const MAX_FILE = 50 * 1024 * 1024;

export function Composer({ chatId }: Props) {
  const [emojiOpen, setEmojiOpen] = useState(false);
  const uiLang = useMessenger((s) => s.uiLang);
  const messages = useMessenger((s) => s.messages);
  const replyToId = useMessenger((s) => s.replyToId);
  const setReplyTo = useMessenger((s) => s.setReplyTo);
  const sendMessage = useMessenger((s) => s.sendMessage);
  const sendFiles = useMessenger((s) => s.sendFiles);
  const editingId = useMessenger((s) => s.editingId);
  const setEditing = useMessenger((s) => s.setEditing);
  const editMessage = useMessenger((s) => s.editMessage);
  const sendVoice = useMessenger((s) => s.sendVoice);
  const runDraftTool = useMessenger((s) => s.runDraftTool);
  const draftBusy = useMessenger((s) => s.draftBusy);
  const contacts = useMessenger((s) => s.contacts);
  const me = useMe();

  const [value, setValue] = useState("");
  const areaRef = useRef<HTMLTextAreaElement>(null);

  /// Эмодзи вставляется туда, где стоит курсор, а не в конец: дописать знак
  /// в середину набранного — обычное дело, и выбрасывать его в хвост значит
  /// заставлять человека вырезать и переставлять.
  function insertEmoji(emoji: string) {
    const area = areaRef.current;
    const at = area?.selectionStart ?? value.length;
    const to = area?.selectionEnd ?? at;
    setValue(value.slice(0, at) + emoji + value.slice(to));

    // Курсор ставится после вставки, когда DOM уже обновился: раньше он
    // окажется в старом тексте и прыгнет.
    requestAnimationFrame(() => {
      const next = at + emoji.length;
      area?.focus();
      area?.setSelectionRange(next, next);
    });
  }
  const fileRef = useRef<HTMLInputElement>(null);
  const recorder = useRef(new VoiceRecorder());
  const [recording, setRecording] = useState<number | null>(null);

  const reply = replyToId ? messages.find((m) => m.id === replyToId) : undefined;
  const editing = editingId ? messages.find((m) => m.id === editingId) : undefined;

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

  // Взялись править — в поле встаёт прежний текст. Отменили — поле
  // очищается: дописывать в него начатую правку было бы неожиданно.
  useEffect(() => {
    setValue(editing?.text ?? "");
    areaRef.current?.focus();
  }, [editingId, editing?.text]);

  function submit() {
    const text = value.trim();
    if (!text || draftBusy) return;

    if (editingId) {
      void editMessage(chatId, editingId, text).catch(() =>
        toast(t(uiLang, "editFailed")),
      );
      setValue("");
      return;
    }

    void sendMessage(chatId, text);
    setValue("");
  }

  // Запись не должна пережить уход с экрана: иначе микрофон остаётся
  // включённым, и в браузере горит красная точка.
  useEffect(() => {
    const current = recorder.current;
    return () => current.cancel();
  }, []);

  async function startRecording() {
    try {
      await recorder.current.start((seconds) => setRecording(seconds));
    } catch {
      // Отказ в доступе к микрофону — единственный частый случай, и молчать
      // здесь нельзя: кнопка нажата, а ничего не происходит.
      setRecording(null);
      toast(t(uiLang, "micDenied"));
    }
  }

  async function finishRecording() {
    const result = await recorder.current.stop();
    setRecording(null);
    if (!result) return;
    try {
      await sendVoice(chatId, result.blob, result.seconds);
    } catch {
      toast(t(uiLang, "uploadFailed"));
    }
  }

  function cancelRecording() {
    recorder.current.cancel();
    setRecording(null);
  }

  async function attach(files: FileList | null) {
    const chosen = [...(files ?? [])];
    if (!chosen.length) return;
    const tooBig = chosen.find((f) => f.size > MAX_FILE);
    if (tooBig) {
      toast(t(uiLang, "fileTooBig"));
      return;
    }
    try {
      await sendFiles(chatId, chosen);
    } catch {
      toast(t(uiLang, "uploadFailed"));
    }
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
      {editing ? (
        <div className="mb-2 flex items-start gap-2 rounded-md bg-elevated px-3 py-2">
          <Pencil className="mt-0.5 size-3.5 shrink-0 text-accent" />
          <span className="min-w-0 flex-1">
            <span className="block text-xs font-medium text-accent">
              {t(uiLang, "editing")}
            </span>
            <span className="block truncate text-xs text-muted">{editing.text}</span>
          </span>
          <Button
            variant="icon"
            size="iconSm"
            aria-label={t(uiLang, "cancelEdit")}
            onClick={() => setEditing(null)}
          >
            <X className="size-4" />
          </Button>
        </div>
      ) : null}

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

      {recording !== null ? (
        <div className="flex items-center gap-2">
          <Button
            variant="icon"
            size="icon"
            type="button"
            aria-label={t(uiLang, "cancelRecording")}
            onClick={cancelRecording}
          >
            <Trash2 className="size-5 text-danger" />
          </Button>

          <span className="flex min-w-0 flex-1 items-center gap-2 rounded-xl bg-elevated px-3 py-2.5 shadow-[var(--shadow-border)]">
            <span className="size-2 shrink-0 animate-pulse rounded-full bg-danger" />
            <span className="text-sm tabular-nums">{formatSeconds(recording)}</span>
            <span className="truncate text-xs text-muted">
              {t(uiLang, "recording")}
            </span>
          </span>

          <Button
            size="icon"
            className="shrink-0 rounded-full"
            aria-label={t(uiLang, "sendVoice")}
            disabled={draftBusy}
            onClick={() => void finishRecording()}
          >
            <Send className="size-4" />
          </Button>
        </div>
      ) : (
      <div className="flex items-end gap-1.5">
        <input
          ref={fileRef}
          type="file"
          multiple
          hidden
          aria-label={t(uiLang, "attach")}
          onChange={(e) => {
            void attach(e.target.files);
            // Сбрасываем значение: иначе выбор того же файла второй раз
            // подряд не вызовет события, и скрепка «перестанет работать».
            e.target.value = "";
          }}
        />
        <Tooltip>
          <TooltipTrigger asChild>
            <Button
              variant="icon"
              size="icon"
              type="button"
              className="shrink-0"
              aria-label={t(uiLang, "attach")}
              disabled={draftBusy}
              onClick={() => fileRef.current?.click()}
            >
              <Paperclip className="size-5" />
            </Button>
          </TooltipTrigger>
          <TooltipContent>{t(uiLang, "attach")}</TooltipContent>
        </Tooltip>

        <div className="relative flex min-w-0 flex-1 items-end rounded-xl bg-elevated px-3 py-1 shadow-[var(--shadow-border)]">
          {emojiOpen ? (
            <EmojiPicker onPick={insertEmoji} onClose={() => setEmojiOpen(false)} />
          ) : null}
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
          <Button
            variant="icon"
            size="iconSm"
            type="button"
            className="mb-0.5 shrink-0"
            aria-label={t(uiLang, "emoji")}
            onClick={() => setEmojiOpen((open) => !open)}
          >
            <Smile className="size-4" />
          </Button>

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

        {/* Пустое поле — микрофон, набранный текст — отправка. Так же
            устроено везде, и человек не ищет, куда делась кнопка. */}
        {value.trim() || editingId ? (
          <Button
            size="icon"
            className="shrink-0 rounded-full"
            disabled={draftBusy}
            // Подпись меняется вместе со значком: «отправить» на кнопке,
            // которая сохраняет правку, сбивает с толку и голосовой доступ.
            aria-label={editingId ? t(uiLang, "save") : t(uiLang, "send")}
            onClick={submit}
          >
            {editingId ? <Check className="size-4" /> : <Send className="size-4" />}
          </Button>
        ) : (
          <Button
            variant="subtle"
            size="icon"
            className="shrink-0 rounded-full"
            disabled={draftBusy}
            aria-label={t(uiLang, "recordVoice")}
            onClick={() => void startRecording()}
          >
            <Mic className="size-4" />
          </Button>
        )}
      </div>
      )}
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
