import { Bookmark } from "lucide-react";
import { cn } from "@/lib/utils";

type Props = {
  src?: string;
  initials: string;
  name: string;
  online?: boolean;
  saved?: boolean;
  size?: "sm" | "md" | "lg" | "xl";
  className?: string;
};

const sizes = {
  sm: "size-10 text-xs",
  md: "size-12 text-sm",
  lg: "size-14 text-base",
  xl: "size-24 text-2xl",
};

export function UserAvatar({ src, initials, name, online, saved, size = "md", className }: Props) {
  return (
    <span className={cn("relative inline-flex shrink-0", className)}>
      <span
        className={cn(
          "flex items-center justify-center overflow-hidden rounded-full bg-elevated font-medium text-fg",
          sizes[size],
        )}
      >
        {saved ? (
          <span className="flex size-full items-center justify-center bg-accent text-accent-fg">
            <Bookmark className="size-1/2" fill="currentColor" />
          </span>
        ) : src ? (
          <img src={src} alt="" className="size-full object-cover" />
        ) : (
          <span aria-hidden="true">{initials}</span>
        )}
      </span>
      {online ? (
        <span
          className="absolute right-0 bottom-0 size-2.5 rounded-full bg-online ring-2 ring-sidebar"
          aria-label={`${name} online`}
        />
      ) : null}
    </span>
  );
}
