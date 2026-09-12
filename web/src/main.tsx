import { StrictMode, useEffect, useState } from "react";
import { createRoot } from "react-dom/client";
import { Messenger } from "@/components/messenger";
import { SignIn } from "@/components/sign-in";
import { AppMark } from "@/components/mark";
import { api } from "@/lib/api";
import { useMessenger } from "@/lib/store";
import { ws } from "@/lib/ws";
import "@/styles.css";

/// Развилка: вошедшего ведём в переписку, остальных — на ввод номера.
function App() {
  const [signedIn, setSignedIn] = useState(() => Boolean(api.session()));
  const [ready, setReady] = useState(false);
  const bootstrap = useMessenger((s) => s.bootstrap);

  useEffect(() => {
    if (!signedIn) {
      setReady(true);
      return;
    }
    let live = true;
    void bootstrap().finally(() => live && setReady(true));
    return () => {
      live = false;
    };
  }, [signedIn, bootstrap]);

  useEffect(() => {
    if (!signedIn) return;
    // Вкладку усыпляют, и сокет тихо умирает. Возврат на экран — повод
    // проверить связь, не дожидаясь таймаута heartbeat.
    const onVisible = () => {
      if (document.visibilityState === "visible") ws.connect();
    };
    document.addEventListener("visibilitychange", onVisible);
    window.addEventListener("online", onVisible);
    return () => {
      document.removeEventListener("visibilitychange", onVisible);
      window.removeEventListener("online", onVisible);
    };
  }, [signedIn]);

  if (!signedIn) return <SignIn onDone={() => setSignedIn(true)} />;

  if (!ready) {
    return (
      <div className="flex h-dvh flex-col items-center justify-center bg-bg text-fg">
        <AppMark className="size-12" />
        <p className="mt-3 font-display text-lg font-medium tracking-tight">Tito</p>
      </div>
    );
  }

  return <Messenger />;
}

createRoot(document.getElementById("app")!).render(
  <StrictMode>
    <App />
  </StrictMode>,
);
