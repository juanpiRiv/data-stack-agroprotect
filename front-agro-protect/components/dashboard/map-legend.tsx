"use client";

export function MapLegend() {
  return (
    <div className="absolute top-4 right-4 glass-panel border border-border p-4 rounded-xl w-48 z-[500]">
      <p className="text-[10px] font-bold text-muted-foreground uppercase mb-3">
        Leyenda de Riesgo
      </p>
      <div className="space-y-3 text-[11px] text-foreground">
        <div className="flex items-center gap-2">
          <div className="w-2.5 h-2.5 rounded-full bg-primary shadow-[0_0_8px_#39ff14]" />
          Zona Segura
        </div>
        <div className="flex items-center gap-2">
          <div className="w-2.5 h-2.5 rounded-full bg-secondary shadow-[0_0_8px_#fd9000]" />
          Vigilancia
        </div>
        <div className="flex items-center gap-2">
          <div className="w-2.5 h-2.5 rounded-full bg-destructive shadow-[0_0_8px_#c50100]" />
          Crítico
        </div>
      </div>
    </div>
  );
}
