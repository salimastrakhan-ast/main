import { useEffect, useState } from "react";
import { Toaster } from "sonner";
import { ChatPane } from "@/components/chat-pane";
import { SettingsView } from "@/components/settings-view";
import { Sidebar } from "@/components/sidebar";
import { AppMark } from "@/components/mark";
import { TooltipProvider } from "@/components/ui/tooltip";
import { useMessenger } from "@/lib/store";
import { cn } from "@/lib/utils";

export function Messenger() {
  const [mounted, setMounted] = useState(false);
  const selectedChatId = useMessenger((s) => s.selectedChatId);
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
        <p className="mt-3 font-display text-lg font-medium tracking-tight">Маяк</p>
      </div>
    );
  }

  const showChat = Boolean(selectedChatId);

  return (
    <TooltipProvider delayDuration={250}>
      <div className="flex h-dvh overflow-hidden bg-bg text-fg">
        <aside
          className={cn(
            "flex h-full w-full min-w-0 flex-col border-r border-border md:w-sidebar md:shrink-0",
            showChat && sidebarView === "chats" ? "hidden md:flex" : "flex",
          )}
        >
          {sidebarView === "chats" ? <Sidebar /> : <SettingsView />}
        </aside>
        <main className={cn("min-w-0 flex-1", showChat ? "flex" : "hidden md:flex")}>
          <div className="h-full w-full">
            <ChatPane />
          </div>
        </main>
      </div>
      <Toaster
        theme="dark"
        position="top-center"
        toastOptions={{
          className: "bg-elevated text-fg border-border shadow-[var(--shadow-border)]",
        }}
      />
    </TooltipProvider>
  );
}
