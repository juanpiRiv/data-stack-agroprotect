import * as L from "leaflet";

declare module "leaflet" {
  function heatLayer(
    latlngs: [number, number, number][],
    options?: {
      minOpacity?: number;
      maxZoom?: number;
      max?: number;
      radius?: number;
      blur?: number;
      gradient?: Record<number, string>;
    }
  ): L.Layer;
}

declare module "leaflet.heat" {
  export = L;
}
