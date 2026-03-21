"use client";

import { AlertTriangle, TrendingUp, Radio } from "lucide-react";

interface KpiCardsProps {
  criticalAlerts: number;
  nationalRisk: number;
  activeNodes: number;
}

export function KpiCards({ criticalAlerts, nationalRisk, activeNodes }: KpiCardsProps) {
  return (
    <div className="grid grid-cols-1 md:grid-cols-3 gap-6 p-6 pb-0 z-10">
      <div className="bg-surface-container rounded-xl p-5 relative overflow-hidden group border-b-4 border-on-tertiary-container">
        <div className="flex justify-between items-start mb-2">
          <span className="text-xs font-bold text-on-surface-variant uppercase">
            Alertas Críticas
          </span>
          <AlertTriangle className="text-on-tertiary-container w-5 h-5 animate-pulse" />
        </div>
        <div className="text-4xl font-black tabular text-on-tertiary-container">
          {criticalAlerts}
        </div>
      </div>
      <div className="bg-surface-container rounded-xl p-5 relative overflow-hidden border-b-4 border-secondary-container">
        <div className="flex justify-between items-start mb-2">
          <span className="text-xs font-bold text-on-surface-variant uppercase">
            Riesgo Nacional
          </span>
          <TrendingUp className="text-secondary-container w-5 h-5" />
        </div>
        <div className="text-4xl font-black tabular text-secondary-container">
          {nationalRisk}%
        </div>
      </div>
      <div className="bg-surface-container rounded-xl p-5 relative overflow-hidden border-b-4 border-primary-container">
        <div className="flex justify-between items-start mb-2">
          <span className="text-xs font-bold text-on-surface-variant uppercase">
            Nodos Activos
          </span>
          <Radio className="text-primary-container w-5 h-5" />
        </div>
        <div className="text-4xl font-black tabular text-[#efffe3]">
          {activeNodes}
        </div>
      </div>
    </div>
  );
}
