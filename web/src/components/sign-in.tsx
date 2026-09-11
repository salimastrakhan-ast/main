import { Loader2, MessageCircle, Phone } from "lucide-react";
import { useState } from "react";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { api, ApiError } from "@/lib/api";
import { cn } from "@/lib/utils";

/// Вход по номеру телефона.
///
/// Отдельной регистрации нет — как в Телеграме: первый вход по номеру и
/// создаёт аккаунт. Меньше шагов, и нечего забывать, кроме номера.
export function SignIn({ onDone }: { onDone: () => void }) {
  const [step, setStep] = useState<"phone" | "code">("phone");
  const [phone, setPhone] = useState("+7");
  const [code, setCode] = useState("");
  const [busy, setBusy] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [hint, setHint] = useState<string | null>(null);

  async function requestCode() {
    setBusy(true);
    setError(null);
    try {
      const result = await api.requestCode(phone);
      // На тестовом сервере код приходит в ответе: почтальона нет, а войти
      // надо. В бою поля просто не будет.
      const devCode = result.dev_code as string | undefined;
      if (devCode) {
        setCode(devCode);
        setHint(`Код разработчика: ${devCode}`);
      }
      setStep("code");
    } catch (e) {
      setError(messageOf(e));
    } finally {
      setBusy(false);
    }
  }

  async function verify() {
    setBusy(true);
    setError(null);
    try {
      await api.verify(phone, code);
      onDone();
    } catch (e) {
      setError(messageOf(e));
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="flex h-dvh flex-col items-center justify-center bg-bg px-6 text-fg">
      <div className="w-full max-w-sm">
        <div className="flex flex-col items-center text-center">
          <span className="flex size-16 items-center justify-center rounded-[22px] bg-accent text-accent-fg">
            <MessageCircle className="size-8" />
          </span>
          <h1 className="mt-5 font-display text-2xl font-semibold tracking-tight">
            Tito
          </h1>
          <p className="mt-2 text-sm text-muted">
            {step === "phone"
              ? "Введите номер телефона"
              : `Код отправлен на ${phone}`}
          </p>
        </div>

        <div className="mt-8 space-y-3">
          {step === "phone" ? (
            <label className="relative block">
              <Phone className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-subtle" />
              <Input
                value={phone}
                onChange={(e) => setPhone(e.target.value)}
                onKeyDown={(e) => e.key === "Enter" && void requestCode()}
                inputMode="tel"
                autoFocus
                placeholder="+7 999 123-45-67"
                className="pl-9"
                aria-label="Номер телефона"
              />
            </label>
          ) : (
            <Input
              value={code}
              onChange={(e) => setCode(e.target.value)}
              onKeyDown={(e) => e.key === "Enter" && void verify()}
              inputMode="numeric"
              autoFocus
              placeholder="Код из SMS"
              className="text-center font-display text-lg tracking-[0.4em]"
              aria-label="Код из SMS"
            />
          )}

          {error ? (
            <p className="text-sm text-danger" role="alert">
              {error}
            </p>
          ) : hint ? (
            <p className="text-sm text-subtle">{hint}</p>
          ) : null}

          <Button
            className="w-full"
            disabled={busy || (step === "phone" ? phone.length < 11 : code.length < 4)}
            onClick={() => void (step === "phone" ? requestCode() : verify())}
          >
            <Loader2 className={cn("size-4 animate-spin", !busy && "hidden")} />
            {step === "phone" ? "Получить код" : "Войти"}
          </Button>

          {step === "code" ? (
            <Button
              variant="ghost"
              className="w-full"
              onClick={() => {
                setStep("phone");
                setError(null);
                setHint(null);
              }}
            >
              Изменить номер
            </Button>
          ) : null}
        </div>
      </div>
    </div>
  );
}

function messageOf(error: unknown): string {
  if (error instanceof ApiError) {
    // Коды сервера человеку ничего не говорят, а вот сами сообщения он
    // пишет по-русски и по делу.
    return error.message;
  }
  return "Сервер недоступен. Проверьте соединение.";
}
