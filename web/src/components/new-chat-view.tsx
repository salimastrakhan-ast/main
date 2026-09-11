import { useEffect, useMemo, useState } from "react";
import { Check, ChevronLeft, Search, Users, X } from "lucide-react";
import { toast } from "sonner";
import { UserAvatar } from "@/components/user-avatar";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { t } from "@/lib/i18n";
import { useMessenger } from "@/lib/store";
import type { Contact } from "@/lib/types";
import { cn } from "@/lib/utils";

/// Новый чат: занимает место панели, как и настройки.
///
/// Отдельного раздела «Контакты» в Tito нет — книга живёт здесь, шагом
/// внутри «нового чата». Тем же экраном собирается группа: сначала
/// участники, потом название.
export function NewChatView() {
  const uiLang = useMessenger((s) => s.uiLang);
  const contacts = useMessenger((s) => s.contacts);
  const setSidebarView = useMessenger((s) => s.setSidebarView);
  const startChatWith = useMessenger((s) => s.startChatWith);
  const createGroup = useMessenger((s) => s.createGroup);
  const findPeople = useMessenger((s) => s.findPeople);

  const [query, setQuery] = useState("");
  const [found, setFound] = useState<Contact[]>([]);
  const [searching, setSearching] = useState(false);
  const [group, setGroup] = useState<string[] | null>(null);
  const [title, setTitle] = useState("");
  const [busy, setBusy] = useState(false);

  const book = useMemo(
    () =>
      Object.values(contacts).sort((a, b) =>
        a.name.localeCompare(b.name, uiLang === "ru" ? "ru" : "en"),
      ),
    [contacts, uiLang],
  );

  const needle = query.trim().toLowerCase();
  const fromBook = needle
    ? book.filter((c) => c.name.toLowerCase().includes(needle))
    : book;

  // Поиск на сервере — только когда в книге не нашлось: в браузере книга
  // часто пуста вовсе, её заполняет телефон.
  useEffect(() => {
    if (needle.length < 2 || fromBook.length > 0) {
      setFound([]);
      return;
    }
    let live = true;
    setSearching(true);
    const timer = window.setTimeout(async () => {
      const people = await findPeople(needle);
      if (!live) return;
      setFound(people);
      setSearching(false);
    }, 350);
    return () => {
      live = false;
      window.clearTimeout(timer);
      window.clearTimeout(timer);
    };
  }, [needle, fromBook.length, findPeople]);

  const people = fromBook.length ? fromBook : found;
  const picking = group !== null;

  const toggle = (id: string) =>
    setGroup((current) =>
      current === null
        ? current
        : current.includes(id)
          ? current.filter((x) => x !== id)
          : [...current, id],
    );

  const submit = async () => {
    if (!group?.length || !title.trim() || busy) return;
    setBusy(true);
    try {
      await createGroup(title, group);
    } catch {
      toast(t(uiLang, "groupFailed"));
    } finally {
      setBusy(false);
    }
  };

  return (
    <div className="flex h-full min-h-0 flex-col bg-sidebar">
      <header className="flex items-center gap-1 px-2 py-2">
        <Button
          variant="icon"
          size="icon"
          aria-label={t(uiLang, "back")}
          onClick={() => (picking ? setGroup(null) : setSidebarView("chats"))}
        >
          <ChevronLeft className="size-5" />
        </Button>
        <h1 className="px-1 text-base font-medium">
          {picking ? t(uiLang, "newGroup") : t(uiLang, "newChat")}
        </h1>
      </header>

      <div className="px-3 pb-2">
        <label className="relative block">
          <Search className="pointer-events-none absolute top-1/2 left-3 size-4 -translate-y-1/2 text-subtle" />
          <input
            value={query}
            onChange={(e) => setQuery(e.target.value)}
            placeholder={t(uiLang, "findPeople")}
            className="h-10 w-full rounded-md bg-elevated pr-9 pl-9 text-sm text-fg placeholder:text-subtle shadow-[var(--shadow-border)] outline-none focus-visible:ring-2 focus-visible:ring-ring/60"
          />
          {query ? (
            <button
              type="button"
              aria-label={t(uiLang, "close")}
              onClick={() => setQuery("")}
              className="absolute top-1/2 right-1 flex size-8 -translate-y-1/2 items-center justify-center rounded-sm text-subtle hover:text-fg"
            >
              <X className="size-4" />
            </button>
          ) : null}
        </label>
      </div>

      {picking ? null : (
        <button
          type="button"
          onClick={() => setGroup([])}
          className="mx-3 mb-2 flex items-center gap-3 rounded-lg bg-surface px-3 py-2.5 text-left transition-colors duration-150 hover:bg-elevated"
        >
          <span className="flex size-10 items-center justify-center rounded-full bg-accent text-accent-fg">
            <Users className="size-5" />
          </span>
          <span className="text-sm font-medium">{t(uiLang, "newGroup")}</span>
        </button>
      )}

      <div className="scroll-thin min-h-0 flex-1 overflow-y-auto px-3 pb-3">
        {people.length === 0 ? (
          <p className="px-1 py-8 text-center text-sm text-subtle">
            {searching
              ? t(uiLang, "searching")
              : needle
                ? t(uiLang, "nobodyFound")
                : t(uiLang, "noContacts")}
          </p>
        ) : (
          <ul>
            {people.map((person) => {
              const chosen = group?.includes(person.id) ?? false;
              return (
                <li key={person.id}>
                  <button
                    type="button"
                    onClick={() =>
                      picking ? toggle(person.id) : startChatWith(person.id)
                    }
                    className={cn(
                      "flex w-full items-center gap-3 rounded-lg px-2 py-2 text-left transition-colors duration-150",
                      chosen ? "bg-elevated" : "hover:bg-surface",
                    )}
                  >
                    <UserAvatar
                      src={person.avatar}
                      initials={person.initials}
                      name={person.name}
                      online={person.online}
                      size="sm"
                    />
                    <span className="min-w-0 flex-1">
                      <span className="block truncate text-sm font-medium">
                        {person.name}
                      </span>
                      {person.about ? (
                        <span className="block truncate text-xs text-muted">
                          {person.about}
                        </span>
                      ) : null}
                    </span>
                    {chosen ? <Check className="size-4 shrink-0 text-accent" /> : null}
                  </button>
                </li>
              );
            })}
          </ul>
        )}
      </div>

      {picking ? (
        <div className="border-t border-border px-3 py-3">
          <p className="mb-2 text-xs text-muted">
            {group.length
              ? `${t(uiLang, "chosen")}: ${group.length}`
              : t(uiLang, "pickMembers")}
          </p>
          <Input
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            placeholder={t(uiLang, "groupNamePlaceholder")}
            aria-label={t(uiLang, "groupName")}
          />
          <Button
            className="mt-2 w-full"
            disabled={!group.length || !title.trim() || busy}
            onClick={submit}
          >
            {t(uiLang, "create")}
          </Button>
        </div>
      ) : null}
    </div>
  );
}
