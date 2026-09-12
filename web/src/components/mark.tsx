import { cn } from "@/lib/utils";

export function AppMark({ className }: { className?: string }) {
  return (
    <svg
      viewBox="0 0 32 32"
      className={cn("text-accent", className)}
      aria-hidden="true"
    >
      <circle cx="16" cy="16" r="15" fill="currentColor" opacity="0.12" />
      <path
        d="M8.2 18.4c1.1-4.6 4.6-8.2 9.6-8.6 1.4-.1 2.4.8 2.2 2-.3 1.4-1.6 2-2.9 2.1-2.6.2-4.4 1.6-5.1 3.7-.3.8-1.4 1.2-2.1.8-.8-.4-1.1-1.4-.7-2z"
        fill="currentColor"
      />
      <path
        d="M18.8 12.2c2.8.4 5 2.4 5.8 5.1.3 1.1-.6 2-1.7 1.8-2.4-.3-3.9-1.6-4.6-3.6-.3-.8.1-1.8.5-2.3z"
        fill="currentColor"
        opacity="0.7"
      />
      <circle cx="13.2" cy="14.1" r="1.15" fill="var(--color-fg)" />
      <circle cx="13.55" cy="13.85" r="0.35" fill="var(--color-bg)" />
      <path
        d="M9.4 16.2c-.8.2-1.6-.2-1.8-1"
        fill="none"
        stroke="currentColor"
        strokeWidth="1.2"
        strokeLinecap="round"
      />
    </svg>
  );
}
