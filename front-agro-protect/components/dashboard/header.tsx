"use client";

import { Search } from "lucide-react";
import Image from "next/image";

interface HeaderProps {
  onAnalyticsClick: () => void;
}

export function Header({ onAnalyticsClick }: HeaderProps) {
  return (
    <header className="bg-surface-dim font-sans antialiased tracking-tight fixed top-0 z-[1000] flex items-center justify-between px-6 h-16 w-full border-b border-border">
      <div className="flex items-center gap-8 flex-1">
        <span className="text-xl font-black tracking-tighter text-[#efffe3]">
          AgroProtect
        </span>
        <div className="hidden md:flex items-center bg-surface-container-lowest rounded-lg px-3 py-1.5 w-full max-w-md border border-border">
          <Search className="text-muted-foreground w-4 h-4" />
          <input
            className="bg-transparent border-none focus:ring-0 focus:outline-none text-sm text-on-surface-variant w-full placeholder:text-muted-foreground ml-2"
            placeholder="Buscar parcela o sensor..."
            type="text"
          />
        </div>
      </div>
      <div className="flex items-center gap-4">
        <nav className="hidden lg:flex items-center gap-6 mr-6">
          <a
            className="text-primary font-bold border-b-2 border-primary py-1 text-sm"
            href="#"
          >
            Dashboard
          </a>
          <button
            onClick={onAnalyticsClick}
            className="text-muted-foreground font-medium hover:bg-surface-container-high transition-colors duration-200 px-2 py-1 rounded text-sm"
          >
            Analytics
          </button>
        </nav>
        <div className="w-8 h-8 rounded-full bg-surface-container-high border border-border overflow-hidden ml-2">
          <Image
            alt="Usuario"
            className="w-full h-full object-cover"
            src="https://lh3.googleusercontent.com/aida-public/AB6AXuBrCvfEYfnA8_PJsQxN7xrUiBzCXMAILD7m3uwc4Vp_x3CPuc9VOEoSvEnJKROXgNqJ0VF7NqVNeQ7RBruJXbHsFazj-VJGtvLX_YLFgGxdH8txEomm6U0Rj3BWKWg-og50Xjo_sxD4fPeO5z31Ss3p3xS_qwTvGBcg5qvXuY6gkkZBexUB2H25j2apWGYMeQTZ_U0QcbCi08_aKbnj-4sv3AN_SF_texVdjU1GUP6Oa5G5nvH4_xoOT-mj6SUDtm26J2ShXBjnafY"
            width={32}
            height={32}
          />
        </div>
      </div>
    </header>
  );
}
