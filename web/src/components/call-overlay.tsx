import { useEffect, useState } from "react";
import { Mic, MicOff, Phone, PhoneOff } from "lucide-react";
import { toast } from "sonner";
import { UserAvatar } from "@/components/user-avatar";
import { t } from "@/lib/i18n";
import type { CallEndReason } from "@/lib/calls";
import { useMessenger } from "@/lib/store";
import { cn } from "@/lib/utils";

/// Окно звонка поверх всего.
///
/// Поверх, а не сбоку: звонок — единственное, что в мессенджере нельзя
/// пропустить и отложить. Пока он идёт, остальное подождёт.
export function CallOverlay() {
  const uiLang = useMessenger((s) => s.uiLang);
  const call = useMessenger((s) => s.call);
  const contacts = useMessenger((s) => s.contacts);
  const acceptCall = useMessenger((s) => s.acceptCall);
  const declineCall = useMessenger((s) => s.declineCall);
  const hangUp = useMessenger((s) => s.hangUp);
  const toggleCallMute = useMessenger((s) => s.toggleCallMute);

  if (!call) return null;

  const peer = contacts[call.peerId];
  const name = peer?.name ?? "…";
  const incoming = call.state === "incoming";
  const active = call.state === "active";

  return (
    <div className="fixed inset-0 z-50 flex items-center justify-center bg-bg/80 backdrop-blur-[2px] p-4">
      <div className="w-full max-w-xs rounded-2xl bg-sidebar p-6 text-center shadow-float">
        <div className="flex justify-center">
          <UserAvatar
            src={peer?.avatar}
            initials={peer?.initials ?? "?"}
            name={name}
            size="xl"
          />
        </div>

        <h2 className="mt-4 truncate text-lg font-medium">{name}</h2>
        <p className="mt-1 h-5 text-sm text-muted" aria-live="polite">
          {active ? (
            <Elapsed since={call.startedAt} />
          ) : (
            statusText(call.state, call.reason, uiLang)
          )}
        </p>

        <div className="mt-6 flex items-center justify-center gap-4">
          {incoming ? (
            <>
              <RoundButton
                tone="danger"
                label={t(uiLang, "decline")}
                onClick={declineCall}
              >
                <PhoneOff className="size-6" />
              </RoundButton>
              <RoundButton
                tone="accept"
                label={t(uiLang, "answer")}
                onClick={() =>
                  void acceptCall().catch(() => toast(t(uiLang, "micDenied")))
                }
              >
                <Phone className="size-6" />
              </RoundButton>
            </>
          ) : call.state === "ended" ? null : (
            <>
              <RoundButton
                tone="neutral"
                label={call.muted ? t(uiLang, "micOn") : t(uiLang, "micOff")}
                onClick={toggleCallMute}
              >
                {call.muted ? (
                  <MicOff className="size-6" />
                ) : (
                  <Mic className="size-6" />
                )}
              </RoundButton>
              <RoundButton
                tone="danger"
                label={t(uiLang, "hangUp")}
                onClick={hangUp}
              >
                <PhoneOff className="size-6" />
              </RoundButton>
            </>
          )}
        </div>
      </div>
    </div>
  );
}

function statusText(
  state: string,
  reason: CallEndReason | undefined,
  lang: Parameters<typeof t>[0],
) {
  if (state === "ringing") return t(lang, "calling");
  if (state === "incoming") return t(lang, "incomingCall");
  if (state === "connecting") return t(lang, "connecting");
  if (state !== "ended") return "";

  switch (reason) {
    case "declined":
      return t(lang, "callEndedDeclined");
    case "missed":
      return t(lang, "callEndedMissed");
    case "busy":
      return t(lang, "callEndedBusy");
    case "failed":
      return t(lang, "callEndedFailed");
    case "offline":
      return t(lang, "callEndedOffline");
    default:
      return t(lang, "callEndedHangup");
  }
}

/// Длительность разговора.
///
/// Считается от момента соединения, а не от нажатия «позвонить»: гудки
/// разговором не были, и записывать их в его длину нечестно.
function Elapsed({ since }: { since: number }) {
  const [now, setNow] = useState(() => Date.now());
  useEffect(() => {
    const timer = window.setInterval(() => setNow(Date.now()), 500);
    return () => window.clearInterval(timer);
  }, []);

  const total = Math.max(0, Math.floor((now - since) / 1000));
  const minutes = Math.floor(total / 60);
  const seconds = total % 60;
  return <span>{`${minutes}:${String(seconds).padStart(2, "0")}`}</span>;
}

function RoundButton({
  tone,
  label,
  onClick,
  children,
}: {
  tone: "accept" | "danger" | "neutral";
  label: string;
  onClick: () => void;
  children: React.ReactNode;
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      aria-label={label}
      title={label}
      className={cn(
        "flex size-14 items-center justify-center rounded-full transition-colors duration-150",
        tone === "accept" && "bg-online text-bg hover:brightness-110",
        tone === "danger" && "bg-danger text-fg hover:brightness-110",
        tone === "neutral" && "bg-elevated text-fg hover:bg-surface",
      )}
    >
      {children}
    </button>
  );
}
