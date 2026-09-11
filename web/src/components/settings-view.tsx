import { ChevronLeft } from "lucide-react";
import { UserAvatar } from "@/components/user-avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { Separator } from "@/components/ui/separator";
import { Switch } from "@/components/ui/switch";
import { t, targetLangList, targetLangNames } from "@/lib/i18n";
import { useMe, useMessenger } from "@/lib/store";
import type { TargetLang, UiLang } from "@/lib/types";
import { cn } from "@/lib/utils";

export function SettingsView() {
  const uiLang = useMessenger((s) => s.uiLang);
  const targetLang = useMessenger((s) => s.targetLang);
  const notifications = useMessenger((s) => s.notifications);
  const me = useMe();
  const setUiLang = useMessenger((s) => s.setUiLang);
  const setTargetLang = useMessenger((s) => s.setTargetLang);
  const setNotifications = useMessenger((s) => s.setNotifications);
  const setMe = useMessenger((s) => s.setMe);
  const setSidebarView = useMessenger((s) => s.setSidebarView);

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
        <h1 className="px-1 text-base font-medium">{t(uiLang, "settings")}</h1>
      </header>

      <div className="scroll-thin min-h-0 flex-1 overflow-y-auto px-3 pb-6">
        <button
          type="button"
          onClick={() => setSidebarView("profile")}
          className="flex w-full items-center gap-3 rounded-lg bg-surface p-3 text-left shadow-[var(--shadow-border)] transition-colors duration-150 hover:bg-elevated"
        >
          <UserAvatar src={me.avatar} initials={me.initials} name={me.name} size="lg" />
          <span className="min-w-0">
            <span className="block truncate font-medium">{me.name}</span>
            <span className="mt-0.5 block truncate text-xs text-muted">{me.about}</span>
          </span>
        </button>

        <p className="mt-6 mb-2 px-1 text-xs font-medium tracking-wide text-subtle uppercase">
          {t(uiLang, "general")}
        </p>
        <section className="rounded-lg bg-surface shadow-[var(--shadow-border)]">
          <label className="flex items-center justify-between gap-3 px-3 py-3">
            <span className="text-sm">{t(uiLang, "language")}</span>
            <span className="flex rounded-full bg-elevated p-0.5">
              {(["ru", "en"] as UiLang[]).map((lang) => (
                <button
                  key={lang}
                  type="button"
                  onClick={() => setUiLang(lang)}
                  className={cn(
                    "h-8 rounded-full px-3 text-xs font-medium transition-colors duration-150",
                    uiLang === lang ? "bg-accent text-accent-fg" : "text-muted hover:text-fg",
                  )}
                >
                  {lang === "ru" ? t(uiLang, "russian") : t(uiLang, "english")}
                </button>
              ))}
            </span>
          </label>
          <Separator />
          <div className="px-3 py-3">
            <p className="mb-2 text-sm">{t(uiLang, "targetLang")}</p>
            <div className="flex flex-wrap gap-1.5">
              {targetLangList.map((lang) => (
                <button
                  key={lang}
                  type="button"
                  onClick={() => setTargetLang(lang as TargetLang)}
                  className={cn(
                    "h-8 rounded-full px-3 text-xs font-medium transition-colors duration-150",
                    targetLang === lang
                      ? "bg-accent text-accent-fg"
                      : "bg-elevated text-muted hover:text-fg",
                  )}
                >
                  {targetLangNames[lang][uiLang]}
                </button>
              ))}
            </div>
          </div>
          <Separator />
          <label className="flex items-center justify-between gap-3 px-3 py-3">
            <span>
              <span className="block text-sm">{t(uiLang, "notifications")}</span>
              <span className="text-xs text-muted">
                {notifications ? t(uiLang, "notificationsOn") : t(uiLang, "notificationsOff")}
              </span>
            </span>
            <Switch checked={notifications} onCheckedChange={setNotifications} />
          </label>
        </section>

        <p className="mt-6 mb-2 px-1 text-xs font-medium tracking-wide text-subtle uppercase">
          {t(uiLang, "profile")}
        </p>
        <section className="space-y-3 rounded-lg bg-surface p-3 shadow-[var(--shadow-border)]">
          <label className="block">
            <span className="mb-1.5 block text-xs text-muted">{t(uiLang, "name")}</span>
            <Input value={me.name} onChange={(e) => setMe({ name: e.target.value })} />
          </label>
          <label className="block">
            <span className="mb-1.5 block text-xs text-muted">{t(uiLang, "about")}</span>
            <Input value={me.about} onChange={(e) => setMe({ about: e.target.value })} />
          </label>
        </section>

        <p className="mt-6 px-1 text-xs leading-relaxed text-subtle">{t(uiLang, "titoAbout")}</p>
      </div>
    </div>
  );
}
