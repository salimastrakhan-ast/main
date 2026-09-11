import { useEffect, useState } from "react";
import { Toaster } from "sonner";
import { CallOverlay } from "@/components/call-overlay";
import { ChatPane } from "@/components/chat-pane";
import { NewChatView } from "@/components/new-chat-view";
import { SettingsView } from "@/components/settings-view";
import { Sidebar } from "@/components/sidebar";
import { AppMark } from "@/components/mark";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useMessenger } from "@/lib/store";
import { cn } from "@/lib/utils";

export function Messenger() {
  const [mounted, setMounted] = useState(false);
  const selectedChatId = useMessenger((s) => s.selectedChatId);
  const draftPeerId = useMessenger((s) => s.draftPeerId);
  const sidebarView = useMessenger((s) => s.sidebarView);
  const uiLang = useMessenger((s) => s.uiLang);

  useEffect(() => {
    let live = true;
    const show = () => {
      if (live) setMounted(true);
    };
    void Promise.resolve(useMessenger.persist.rehydrate()).finally(show);
    const id = window.setTimeout(show, 80);
    return () => {
      live = false;
      window.clearTimeout(id);
    };
  }, []);

  useEffect(() => {
    document.documentElement.lang = uiLang;
  }, [uiLang]);

  if (!mounted) {
    return (
      <div className="flex h-dvh flex-col items-center justify-center bg-bg text-fg">
        <AppMark className="size-12" />
        <p className="mt-3 font-display text-lg font-medium tracking-tight">
          Tito
        </p>
      </div>
    );
  }

  // Начатая, но ещё не заведённая переписка занимает правую часть так же,
  // как настоящая: на узком экране иначе некуда было бы писать.
  const showChat = Boolean(selectedChatId || draftPeerId);

  return (
    <TooltipProvider delayDuration={250}>
      <div className="flex h-dvh overflow-hidden bg-bg text-fg">
        <aside
          className={cn(
            "flex h-full w-full min-w-0 flex-col border-r border-border md:w-sidebar md:shrink-0",
            showChat && sidebarView === "chats" ? "hidden md:flex" : "flex",
          )}
        >
          {sidebarView === "chats" ? (
            <Sidebar />
          ) : sidebarView === "new" ? (
            <NewChatView />
          ) : (
            <SettingsView />
          )}
        </aside>
        <main
          className={cn("min-w-0 flex-1", showChat ? "flex" : "hidden md:flex")}
        >
          <div className="h-full w-full">
            <ChatPane />
          </div>
        </main>
      </div>
      <CallOverlay />
      <Toaster
        theme="dark"
        position="top-center"
        toastOptions={{
          className:
            "bg-elevated text-fg border-border shadow-[var(--shadow-border)]",
        }}
      />
    </TooltipProvider>
  );
}
