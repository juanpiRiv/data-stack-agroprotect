"use client";

import { LayoutDashboard, TrendingUp, FileText } from "lucide-react";
import { provinces } from "@/lib/locations";
import { RiskData } from "@/lib/types";

interface SidebarProps {
  onAnalyticsClick: () => void;
  onExport: () => void;
  selectedProvince: string;
  onProvinceChange: (province: string) => void;
}

export function Sidebar({
  onAnalyticsClick,
  onExport,
  selectedProvince,
  onProvinceChange,
}: SidebarProps) {
  return (
    <aside className="bg-surface-container-lowest font-sans font-medium text-sm fixed left-0 h-[calc(100vh-64px)] top-16 w-64 flex flex-col py-8 px-4 gap-y-2 shrink-0 border-r border-border z-40">
      <div className="mb-8 px-2">
        <h2 className="text-[#efffe3] font-bold text-xs uppercase tracking-widest opacity-50 mb-4">
          Módulos
        </h2>
        <div className="space-y-1">
          <a
            className="flex items-center gap-3 px-3 py-2.5 rounded-lg text-primary bg-surface-container-high/50 border-r-2 border-primary transition-all"
            href="#"
          >
            <LayoutDashboard className="w-5 h-5" />
            <span>Dashboard</span>
          </a>
          <button
            onClick={onAnalyticsClick}
            className="w-full flex items-center gap-3 px-3 py-2.5 rounded-lg text-muted-foreground hover:text-foreground hover:bg-surface-container-high transition-all"
          >
            <TrendingUp className="w-5 h-5" />
            <span>Analytics</span>
          </button>
        </div>
      </div>
      <div className="px-2 mb-4">
        <h2 className="text-[#efffe3] font-bold text-xs uppercase tracking-widest opacity-50 mb-4">
          Filtros
        </h2>
        <div className="space-y-4">
          <div className="space-y-1.5">
            <label className="text-[10px] text-muted-foreground font-bold uppercase ml-1">
              Provincia
            </label>
            <select
              value={selectedProvince}
              onChange={(e) => onProvinceChange(e.target.value)}
              className="w-full bg-surface-container-highest border-none rounded-lg text-xs text-foreground py-2 focus:ring-1 focus:ring-primary"
            >
              <option value="">Toda Argentina</option>
              {provinces.map((province) => (
                <option key={province} value={province}>
                  {province}
                </option>
              ))}
            </select>
          </div>
        </div>
      </div>
      <div className="mt-auto border-t border-border pt-6 px-2">
        <button
          onClick={onExport}
          className="w-full flex items-center justify-center gap-2 bg-primary-container text-on-primary-container py-2.5 rounded-lg font-bold text-xs active:scale-[0.98] transition-all hover:opacity-90"
        >
          <FileText className="w-4 h-4" />
          Export Data
        </button>
      </div>
    </aside>
  );
}
