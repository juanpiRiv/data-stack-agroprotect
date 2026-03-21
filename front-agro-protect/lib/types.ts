export interface Location {
  location_id: string;
  location_name: string;
  province_name: string;
  latitude: number;
  longitude: number;
  country_code: string;
  is_active: boolean;
}

// Indice Financiero (sub-indices)
export interface IndiceFinanciero {
  costoInsumos: number;      // Costo de insumos (0-100)
  precioMercado: number;     // Precio de mercado (0-100)
  rentabilidad: number;      // Rentabilidad proyectada (0-100)
  total: number;             // Indice combinado (0-1)
}

// Indice de Produccion (sub-indices)
export interface IndiceProduccion {
  rendimiento: number;       // Rendimiento estimado (0-100)
  calidadCultivo: number;    // Calidad del cultivo (0-100)
  eficiencia: number;        // Eficiencia operativa (0-100)
  total: number;             // Indice combinado (0-1)
}

// Indice Climatico (sub-indices)
export interface IndiceClimatico {
  lluvia: number;            // Probabilidad de lluvia (0-100)
  estresHidrico: number;     // Estres hidrico (0-100)
  temperatura: number;       // Riesgo por temperatura (0-100)
  total: number;             // Indice combinado (0-1)
}

export interface RiskData extends Location {
  // Indice Global (combinacion de todos)
  indiceGlobal: number;      // 0-1
  
  // Sub-indices principales
  indiceFinanciero: IndiceFinanciero;
  indiceProduccion: IndiceProduccion;
  indiceClimatico: IndiceClimatico;
  
  // Legacy fields for compatibility
  riesgo: number;
  lluvia: number;
  estres: number;
  plagas: number;
}

// Tipo de indice para filtrar el mapa
export type TipoIndice = 'global' | 'financiero' | 'produccion' | 'climatico';

export interface ProvinceStats {
  province: string;
  averageRisk: number;
  count: number;
}
