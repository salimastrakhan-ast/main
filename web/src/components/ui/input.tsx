import * as React from "react";
import { cn } from "@/lib/utils";

export function Input({ className, ...props }: React.ComponentProps<"input">) {
  return (
    <input
      className={cn(
        "h-10 w-full rounded-md bg-elevated px-3 text-sm text-fg placeholder:text-subtle",
        "shadow-[var(--shadow-border)] outline-none transition-[box-shadow] duration-150",
        "focus-visible:ring-2 focus-visible:ring-ring/60",
        className,
      )}
      {...props}
    />
  );
}
