import { locations } from "./locations";
import { RiskData, IndiceFinanciero, IndiceProduccion, IndiceClimatico } from "./types";

// Seeded random number generator for consistent results
function seededRandom(seed: number): () => number {
  return function() {
    seed = (seed * 9301 + 49297) % 233280;
    return seed / 233280;
  };
}

export function generateRiskData(): RiskData[] {
  const random = seededRandom(42);
  
  return locations.map(location => {
    // 1. Indice Financiero
    const costoInsumos = Math.round(random() * 100);
    const precioMercado = Math.round(random() * 100);
    const rentabilidad = Math.round(random() * 100);
    const financieroTotal = Math.round(((costoInsumos + precioMercado + rentabilidad) / 300) * 100) / 100;
    
    const indiceFinanciero: IndiceFinanciero = {
      costoInsumos,
      precioMercado,
      rentabilidad,
      total: financieroTotal
    };
    
    // 2. Indice de Produccion
    const rendimiento = Math.round(random() * 100);
    const calidadCultivo = Math.round(random() * 100);
    const eficiencia = Math.round(random() * 100);
    const produccionTotal = Math.round(((rendimiento + calidadCultivo + eficiencia) / 300) * 100) / 100;
    
    const indiceProduccion: IndiceProduccion = {
      rendimiento,
      calidadCultivo,
      eficiencia,
      total: produccionTotal
    };
    
    // 3. Indice Climatico
    const lluvia = Math.round(random() * 100);
    const estresHidrico = Math.round(random() * 100);
    const temperatura = Math.round(random() * 100);
    const climaticoTotal = Math.round(((lluvia + estresHidrico + temperatura) / 300) * 100) / 100;
    
    const indiceClimatico: IndiceClimatico = {
      lluvia,
      estresHidrico,
      temperatura,
      total: climaticoTotal
    };
    
    // Indice Global (ponderacion: 40% climatico, 35% produccion, 25% financiero)
    const indiceGlobal = Math.round((climaticoTotal * 0.4 + produccionTotal * 0.35 + financieroTotal * 0.25) * 100) / 100;
    
    return {
      ...location,
      indiceGlobal,
      indiceFinanciero,
      indiceProduccion,
      indiceClimatico,
      // Legacy fields
      riesgo: indiceGlobal,
      lluvia,
      estres: estresHidrico,
      plagas: Math.round(random() * 100)
    };
  });
}

export const riskData = generateRiskData();
