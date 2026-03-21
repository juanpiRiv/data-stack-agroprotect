"use client";

import { useState, useMemo, useCallback, useRef } from "react";
import dynamic from "next/dynamic";
import { 
  Satellite, 
  Shield, 
  Zap, 
  BarChart3, 
  MapPin, 
  Bot,
  ChevronDown,
  TrendingUp,
  AlertTriangle,
  Activity,
  ArrowRight,
  Menu,
  X
} from "lucide-react";
import { Button } from "@/components/ui/button";
import { riskData } from "@/lib/generate-risk-data";
import { RiskData, ProvinceStats, TipoIndice } from "@/lib/types";
import { AnalyticsModal } from "@/components/dashboard/analytics-modal";

// Dynamic import for map to avoid SSR issues with Leaflet
const ArgentinaMap = dynamic(
  () => import("@/components/dashboard/argentina-map").then((mod) => mod.ArgentinaMap),
  { 
    ssr: false,
    loading: () => (
      <div className="w-full h-full rounded-2xl bg-surface-container-lowest overflow-hidden border border-border relative shadow-inner flex items-center justify-center">
        <div className="text-muted-foreground text-sm">Cargando mapa...</div>
      </div>
    )
  }
);

// Dynamic import for AI Chat
const AIChatPanel = dynamic(
  () => import("@/components/dashboard/ai-chat-panel").then((mod) => mod.AIChatPanel),
  { ssr: false }
);

const features = [
  {
    icon: Satellite,
    title: "Monitoreo Satelital",
    description: "Datos en tiempo real de 117+ estaciones de monitoreo distribuidas en toda Argentina."
  },
  {
    icon: Shield,
    title: "Deteccion de Riesgos",
    description: "Algoritmos avanzados que detectan amenazas climaticas y agricolas antes de que impacten."
  },
  {
    icon: Zap,
    title: "Alertas Instantaneas",
    description: "Notificaciones inmediatas cuando se detectan condiciones criticas en tu zona."
  },
  {
    icon: Bot,
    title: "Asistente IA",
    description: "Consulta con nuestro asistente inteligente para obtener recomendaciones personalizadas."
  }
];

export default function LandingPage() {
  const [selectedLocation, setSelectedLocation] = useState<RiskData | null>(null);
  const [isAnalyticsOpen, setIsAnalyticsOpen] = useState(false);
  const [isChatOpen, setIsChatOpen] = useState(false);
  const [mobileMenuOpen, setMobileMenuOpen] = useState(false);
  const [selectedIndex, setSelectedIndex] = useState<TipoIndice>('global');
  const dashboardRef = useRef<HTMLDivElement>(null);

  // Calculate KPIs
  const kpis = useMemo(() => {
    const criticalAlerts = riskData.filter((c) => c.riesgo > 0.8).length;
    const nationalRisk = Math.round(
      (riskData.reduce((a, b) => a + b.riesgo, 0) / riskData.length) * 100
    );
    const activeNodes = riskData.length;
    return { criticalAlerts, nationalRisk, activeNodes };
  }, []);

  // Calculate province statistics
  const provinceStats = useMemo<ProvinceStats[]>(() => {
    const stats: Record<string, { sum: number; count: number }> = {};
    riskData.forEach((c) => {
      if (!stats[c.province_name]) {
        stats[c.province_name] = { sum: 0, count: 0 };
      }
      stats[c.province_name].sum += c.riesgo;
      stats[c.province_name].count++;
    });
    return Object.entries(stats).map(([province, data]) => ({
      province,
      averageRisk: Math.round((data.sum / data.count) * 100),
      count: data.count,
    }));
  }, []);

  const handleLocationSelect = useCallback((location: RiskData) => {
    setSelectedLocation(location);
    // Stay on details tab when selecting a location
  }, []);

  const scrollToDashboard = () => {
    dashboardRef.current?.scrollIntoView({ behavior: 'smooth' });
  };

  return (
    <div className="min-h-screen bg-background text-foreground overflow-x-hidden">
      {/* Navigation */}
      <nav className="fixed top-0 left-0 right-0 z-50 bg-background/80 backdrop-blur-xl border-b border-border">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex items-center justify-between h-16">
            <div className="flex items-center gap-3">
              <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
                <Satellite className="w-5 h-5 text-primary" />
              </div>
              <span className="text-xl font-black tracking-tight">
                <span className="text-primary">Agro</span>Protect
              </span>
            </div>

            {/* Desktop Nav */}
            <div className="hidden md:flex items-center gap-8">
              <a href="#features" className="text-sm text-muted-foreground hover:text-foreground transition-colors">
                Caracteristicas
              </a>
              <a href="#dashboard" className="text-sm text-muted-foreground hover:text-foreground transition-colors">
                Dashboard
              </a>
              <button 
                onClick={() => setIsAnalyticsOpen(true)}
                className="text-sm text-muted-foreground hover:text-foreground transition-colors"
              >
                Analytics
              </button>
              <Button 
                onClick={scrollToDashboard}
                className="bg-primary text-primary-foreground hover:bg-primary/90"
              >
                Ver Demo
              </Button>
            </div>

            {/* Mobile menu button */}
            <button 
              className="md:hidden p-2"
              onClick={() => setMobileMenuOpen(!mobileMenuOpen)}
            >
              {mobileMenuOpen ? <X className="w-6 h-6" /> : <Menu className="w-6 h-6" />}
            </button>
          </div>
        </div>

        {/* Mobile Nav */}
        {mobileMenuOpen && (
          <div className="md:hidden bg-surface-container border-t border-border">
            <div className="px-4 py-4 space-y-3">
              <a href="#features" className="block text-sm text-muted-foreground hover:text-foreground">
                Caracteristicas
              </a>
              <a href="#dashboard" className="block text-sm text-muted-foreground hover:text-foreground">
                Dashboard
              </a>
              <button 
                onClick={() => { setIsAnalyticsOpen(true); setMobileMenuOpen(false); }}
                className="block text-sm text-muted-foreground hover:text-foreground"
              >
                Analytics
              </button>
              <Button 
                onClick={() => { scrollToDashboard(); setMobileMenuOpen(false); }}
                className="w-full bg-primary text-primary-foreground"
              >
                Ver Demo
              </Button>
            </div>
          </div>
        )}
      </nav>

      {/* Hero Section */}
      <section className="relative min-h-screen flex items-center justify-center pt-16 overflow-hidden">
        {/* Background gradient */}
        <div className="absolute inset-0 bg-gradient-to-b from-primary/5 via-transparent to-transparent" />
        <div className="absolute top-1/4 left-1/4 w-96 h-96 bg-primary/10 rounded-full blur-3xl" />
        <div className="absolute bottom-1/4 right-1/4 w-64 h-64 bg-secondary/10 rounded-full blur-3xl" />

        <div className="relative max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-20">
          <div className="text-center space-y-8">
            {/* Badge */}
            <div className="inline-flex items-center gap-2 px-4 py-2 rounded-full bg-primary/10 border border-primary/20">
              <span className="w-2 h-2 rounded-full bg-primary animate-pulse" />
              <span className="text-sm text-primary font-medium">Monitoreo en Tiempo Real</span>
            </div>

            {/* Headline */}
            <h1 className="text-4xl sm:text-5xl lg:text-7xl font-black tracking-tight text-balance">
              <span className="text-foreground">Precision Sentinel</span>
              <br />
              <span className="text-primary">para el Agro Argentino</span>
            </h1>

            {/* Subheadline */}
            <p className="text-lg sm:text-xl text-muted-foreground max-w-2xl mx-auto text-pretty">
              Sistema de monitoreo agricola de precision con IA. Detectamos riesgos climaticos y fitosanitarios 
              antes de que afecten tus cultivos.
            </p>

            {/* CTA Buttons */}
            <div className="flex flex-col sm:flex-row items-center justify-center gap-4 pt-4">
              <Button 
                size="lg"
                onClick={scrollToDashboard}
                className="bg-primary text-primary-foreground hover:bg-primary/90 text-lg px-8 py-6 rounded-xl font-semibold group"
              >
                Explorar Dashboard
                <ArrowRight className="w-5 h-5 ml-2 group-hover:translate-x-1 transition-transform" />
              </Button>
              <Button 
                size="lg"
                variant="outline"
                onClick={() => setIsAnalyticsOpen(true)}
                className="text-lg px-8 py-6 rounded-xl font-semibold border-border hover:bg-accent"
              >
                <BarChart3 className="w-5 h-5 mr-2" />
                Ver Analytics
              </Button>
            </div>

            {/* Stats Preview */}
            <div className="grid grid-cols-3 gap-4 sm:gap-8 pt-12 max-w-xl mx-auto">
              <div className="text-center">
                <div className="text-2xl sm:text-4xl font-black text-primary tabular-nums">{kpis.activeNodes}</div>
                <div className="text-xs sm:text-sm text-muted-foreground mt-1">Estaciones Activas</div>
              </div>
              <div className="text-center">
                <div className="text-2xl sm:text-4xl font-black text-secondary tabular-nums">{kpis.nationalRisk}%</div>
                <div className="text-xs sm:text-sm text-muted-foreground mt-1">Riesgo Nacional</div>
              </div>
              <div className="text-center">
                <div className="text-2xl sm:text-4xl font-black text-destructive tabular-nums">{kpis.criticalAlerts}</div>
                <div className="text-xs sm:text-sm text-muted-foreground mt-1">Alertas Criticas</div>
              </div>
            </div>

            {/* Scroll indicator */}
            <button 
              onClick={scrollToDashboard}
              className="absolute bottom-8 left-1/2 -translate-x-1/2 animate-bounce"
            >
              <ChevronDown className="w-8 h-8 text-muted-foreground" />
            </button>
          </div>
        </div>
      </section>

      {/* Features Section */}
      <section id="features" className="py-24 bg-surface-container-low">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-16">
            <h2 className="text-3xl sm:text-4xl font-black mb-4">
              Tecnologia de <span className="text-primary">Vanguardia</span>
            </h2>
            <p className="text-muted-foreground max-w-2xl mx-auto">
              Combinamos datos satelitales, sensores IoT y algoritmos de IA para brindarte 
              la informacion mas precisa del sector agricola.
            </p>
          </div>

          <div className="grid md:grid-cols-2 lg:grid-cols-4 gap-6">
            {features.map((feature, index) => (
              <div 
                key={index}
                className="group p-6 rounded-2xl bg-surface-container border border-border hover:border-primary/30 transition-all hover:shadow-lg hover:shadow-primary/5"
              >
                <div className="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center mb-4 group-hover:bg-primary/20 transition-colors">
                  <feature.icon className="w-6 h-6 text-primary" />
                </div>
                <h3 className="text-lg font-bold mb-2">{feature.title}</h3>
                <p className="text-sm text-muted-foreground">{feature.description}</p>
              </div>
            ))}
          </div>
        </div>
      </section>

      {/* Dashboard Section */}
      <section id="dashboard" ref={dashboardRef} className="py-16 bg-background">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="text-center mb-12">
            <h2 className="text-3xl sm:text-4xl font-black mb-4">
              Dashboard <span className="text-primary">Interactivo</span>
            </h2>
            <p className="text-muted-foreground max-w-2xl mx-auto">
              Explora el mapa de riesgo en tiempo real. Haz clic en cualquier punto para obtener 
              informacion detallada y consultar con nuestro asistente IA.
            </p>
          </div>

          {/* KPI Cards */}
          <div className="grid grid-cols-1 sm:grid-cols-3 gap-4 mb-8">
            <div className="p-6 rounded-2xl bg-surface-container border border-border">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 rounded-xl bg-destructive/10 flex items-center justify-center">
                  <AlertTriangle className="w-6 h-6 text-destructive" />
                </div>
                <div>
                  <div className="text-3xl font-black text-destructive tabular-nums">{kpis.criticalAlerts}</div>
                  <div className="text-sm text-muted-foreground">Alertas Criticas</div>
                </div>
              </div>
            </div>
            <div className="p-6 rounded-2xl bg-surface-container border border-border">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 rounded-xl bg-secondary/10 flex items-center justify-center">
                  <TrendingUp className="w-6 h-6 text-secondary" />
                </div>
                <div>
                  <div className="text-3xl font-black text-secondary tabular-nums">{kpis.nationalRisk}%</div>
                  <div className="text-sm text-muted-foreground">Riesgo Nacional</div>
                </div>
              </div>
            </div>
            <div className="p-6 rounded-2xl bg-surface-container border border-border">
              <div className="flex items-center gap-4">
                <div className="w-12 h-12 rounded-xl bg-primary/10 flex items-center justify-center">
                  <Activity className="w-6 h-6 text-primary" />
                </div>
                <div>
                  <div className="text-3xl font-black text-primary tabular-nums">{kpis.activeNodes}</div>
                  <div className="text-sm text-muted-foreground">Nodos Activos</div>
                </div>
              </div>
            </div>
          </div>

          {/* Map and Detail Panel */}
          <div className="grid lg:grid-cols-3 gap-6">
            {/* Map */}
            <div className="lg:col-span-2 h-[500px] lg:h-[600px] rounded-2xl overflow-hidden border border-border bg-surface-container-lowest">
              <ArgentinaMap 
                data={riskData} 
                onLocationSelect={handleLocationSelect}
                selectedIndex={selectedIndex}
                onIndexChange={setSelectedIndex}
              />
            </div>

            {/* Detail Panel */}
            <div className="h-[500px] lg:h-[600px] rounded-2xl border border-border bg-surface-container overflow-hidden flex flex-col">
              {/* Header */}
              <div className="flex items-center justify-between px-6 py-4 border-b border-border">
                <div className="flex items-center gap-2">
                  <MapPin className="w-4 h-4 text-primary" />
                  <span className="font-semibold">Detalles de Zona</span>
                </div>
                <Button
                  size="sm"
                  onClick={() => setIsChatOpen(true)}
                  className="bg-primary/10 text-primary hover:bg-primary/20 border-0"
                >
                  <Bot className="w-4 h-4 mr-2" />
                  Asistente IA
                </Button>
              </div>

              {/* Content */}
              <div className="flex-1 p-6 overflow-y-auto">
                {selectedLocation ? (
                  <div className="space-y-5">
                    <div>
                      <h3 className="text-xl font-bold text-primary">{selectedLocation.location_name}</h3>
                      <p className="text-sm text-muted-foreground">{selectedLocation.province_name}</p>
                    </div>

                    {/* Indice Global */}
                    <div className={`p-4 rounded-xl ${
                      selectedLocation.indiceGlobal > 0.7 
                        ? 'bg-destructive/10 border border-destructive/30' 
                        : selectedLocation.indiceGlobal > 0.4 
                        ? 'bg-secondary/10 border border-secondary/30' 
                        : 'bg-primary/10 border border-primary/30'
                    }`}>
                      <div className="flex items-center justify-between mb-2">
                        <div className="flex items-center gap-2">
                          <AlertTriangle className={`w-4 h-4 ${
                            selectedLocation.indiceGlobal > 0.7 
                              ? 'text-destructive' 
                              : selectedLocation.indiceGlobal > 0.4 
                              ? 'text-secondary' 
                              : 'text-primary'
                          }`} />
                          <span className="font-bold text-sm">Indice Global</span>
                        </div>
                        <span className={`text-lg font-black ${
                          selectedLocation.indiceGlobal > 0.7 
                            ? 'text-destructive' 
                            : selectedLocation.indiceGlobal > 0.4 
                            ? 'text-secondary' 
                            : 'text-primary'
                        }`}>
                          {Math.round(selectedLocation.indiceGlobal * 100)}%
                        </span>
                      </div>
                      <div className="h-2 w-full bg-surface-container-highest rounded-full overflow-hidden">
                        <div
                          className={`h-full transition-all duration-700 ${
                            selectedLocation.indiceGlobal > 0.7 
                              ? 'bg-destructive' 
                              : selectedLocation.indiceGlobal > 0.4 
                              ? 'bg-secondary' 
                              : 'bg-primary'
                          }`}
                          style={{ width: `${selectedLocation.indiceGlobal * 100}%` }}
                        />
                      </div>
                    </div>

                    {/* Indice Financiero */}
                    <div className="p-4 rounded-xl bg-surface-container-high border border-border">
                      <div className="flex items-center justify-between mb-3">
                        <span className="font-bold text-sm text-blue-400">1. Indice Financiero</span>
                        <span className="font-bold text-blue-400">{Math.round(selectedLocation.indiceFinanciero.total * 100)}%</span>
                      </div>
                      <div className="space-y-2">
                        <div>
                          <div className="flex justify-between text-xs mb-1">
                            <span className="text-muted-foreground">Costo Insumos</span>
                            <span className="text-foreground">{selectedLocation.indiceFinanciero.costoInsumos}%</span>
                          </div>
                          <div className="h-1.5 w-full bg-surface-container-highest rounded-full overflow-hidden">
                            <div className="h-full bg-blue-500 transition-all duration-700" style={{ width: `${selectedLocation.indiceFinanciero.costoInsumos}%` }} />
                          </div>
                        </div>
                        <div>
                          <div className="flex justify-between text-xs mb-1">
                            <span className="text-muted-foreground">Precio Mercado</span>
                            <span className="text-foreground">{selectedLocation.indiceFinanciero.precioMercado}%</span>
                          </div>
                          <div className="h-1.5 w-full bg-surface-container-highest rounded-full overflow-hidden">
                            <div className="h-full bg-blue-400 transition-all duration-700" style={{ width: `${selectedLocation.indiceFinanciero.precioMercado}%` }} />
                          </div>
                        </div>
                        <div>
                          <div className="flex justify-between text-xs mb-1">
                            <span className="text-muted-foreground">Rentabilidad</span>
                            <span className="text-foreground">{selectedLocation.indiceFinanciero.rentabilidad}%</span>
                          </div>
                          <div className="h-1.5 w-full bg-surface-container-highest rounded-full overflow-hidden">
                            <div className="h-full bg-blue-300 transition-all duration-700" style={{ width: `${selectedLocation.indiceFinanciero.rentabilidad}%` }} />
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Indice de Produccion */}
                    <div className="p-4 rounded-xl bg-surface-container-high border border-border">
                      <div className="flex items-center justify-between mb-3">
                        <span className="font-bold text-sm text-amber-400">2. Indice de Produccion</span>
                        <span className="font-bold text-amber-400">{Math.round(selectedLocation.indiceProduccion.total * 100)}%</span>
                      </div>
                      <div className="space-y-2">
                        <div>
                          <div className="flex justify-between text-xs mb-1">
                            <span className="text-muted-foreground">Rendimiento</span>
                            <span className="text-foreground">{selectedLocation.indiceProduccion.rendimiento}%</span>
                          </div>
                          <div className="h-1.5 w-full bg-surface-container-highest rounded-full overflow-hidden">
                            <div className="h-full bg-amber-500 transition-all duration-700" style={{ width: `${selectedLocation.indiceProduccion.rendimiento}%` }} />
                          </div>
                        </div>
                        <div>
                          <div className="flex justify-between text-xs mb-1">
                            <span className="text-muted-foreground">Calidad Cultivo</span>
                            <span className="text-foreground">{selectedLocation.indiceProduccion.calidadCultivo}%</span>
                          </div>
                          <div className="h-1.5 w-full bg-surface-container-highest rounded-full overflow-hidden">
                            <div className="h-full bg-amber-400 transition-all duration-700" style={{ width: `${selectedLocation.indiceProduccion.calidadCultivo}%` }} />
                          </div>
                        </div>
                        <div>
                          <div className="flex justify-between text-xs mb-1">
                            <span className="text-muted-foreground">Eficiencia</span>
                            <span className="text-foreground">{selectedLocation.indiceProduccion.eficiencia}%</span>
                          </div>
                          <div className="h-1.5 w-full bg-surface-container-highest rounded-full overflow-hidden">
                            <div className="h-full bg-amber-300 transition-all duration-700" style={{ width: `${selectedLocation.indiceProduccion.eficiencia}%` }} />
                          </div>
                        </div>
                      </div>
                    </div>

                    {/* Indice Climatico */}
                    <div className="p-4 rounded-xl bg-surface-container-high border border-border">
                      <div className="flex items-center justify-between mb-3">
                        <span className="font-bold text-sm text-cyan-400">3. Indice Climatico</span>
                        <span className="font-bold text-cyan-400">{Math.round(selectedLocation.indiceClimatico.total * 100)}%</span>
                      </div>
                      <div className="space-y-2">
                        <div>
                          <div className="flex justify-between text-xs mb-1">
                            <span className="text-muted-foreground">Prob. Lluvia</span>
                            <span className="text-foreground">{selectedLocation.indiceClimatico.lluvia}%</span>
                          </div>
                          <div className="h-1.5 w-full bg-surface-container-highest rounded-full overflow-hidden">
                            <div className="h-full bg-cyan-500 transition-all duration-700" style={{ width: `${selectedLocation.indiceClimatico.lluvia}%` }} />
                          </div>
                        </div>
                        <div>
                          <div className="flex justify-between text-xs mb-1">
                            <span className="text-muted-foreground">Estres Hidrico</span>
                            <span className="text-foreground">{selectedLocation.indiceClimatico.estresHidrico}%</span>
                          </div>
                          <div className="h-1.5 w-full bg-surface-container-highest rounded-full overflow-hidden">
                            <div className="h-full bg-cyan-400 transition-all duration-700" style={{ width: `${selectedLocation.indiceClimatico.estresHidrico}%` }} />
                          </div>
                        </div>
                        <div>
                          <div className="flex justify-between text-xs mb-1">
                            <span className="text-muted-foreground">Riesgo Temperatura</span>
                            <span className="text-foreground">{selectedLocation.indiceClimatico.temperatura}%</span>
                          </div>
                          <div className="h-1.5 w-full bg-surface-container-highest rounded-full overflow-hidden">
                            <div className="h-full bg-cyan-300 transition-all duration-700" style={{ width: `${selectedLocation.indiceClimatico.temperatura}%` }} />
                          </div>
                        </div>
                      </div>
                    </div>

                    <Button 
                      onClick={() => setIsChatOpen(true)}
                      className="w-full bg-primary text-primary-foreground hover:bg-primary/90"
                    >
                      <Bot className="w-4 h-4 mr-2" />
                      Consultar Asistente IA
                    </Button>
                  </div>
                ) : (
                  <div className="h-full flex flex-col items-center justify-center text-center">
                    <div className="w-16 h-16 rounded-2xl bg-surface-container-high flex items-center justify-center mb-4">
                      <MapPin className="w-8 h-8 text-muted-foreground" />
                    </div>
                    <h3 className="font-bold mb-2">Selecciona una ubicacion</h3>
                    <p className="text-sm text-muted-foreground max-w-xs">
                      Haz clic en cualquier zona del mapa de calor para ver los detalles de esa area.
                    </p>
                  </div>
                )}
              </div>
            </div>
          </div>

          {/* Map Legend */}
          <div className="mt-6 flex flex-wrap items-center justify-center gap-6">
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-primary shadow-[0_0_10px_#39ff14]" />
              <span className="text-sm text-muted-foreground">Bajo Riesgo</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-secondary shadow-[0_0_10px_#fd9000]" />
              <span className="text-sm text-muted-foreground">Vigilancia</span>
            </div>
            <div className="flex items-center gap-2">
              <div className="w-3 h-3 rounded-full bg-destructive shadow-[0_0_10px_#c50100]" />
              <span className="text-sm text-muted-foreground">Critico</span>
            </div>
          </div>
        </div>
      </section>

      {/* CTA Section */}
      <section className="py-24 bg-surface-container-low">
        <div className="max-w-4xl mx-auto px-4 sm:px-6 lg:px-8 text-center">
          <h2 className="text-3xl sm:text-4xl font-black mb-4">
            Protege tus <span className="text-primary">Cultivos</span> Hoy
          </h2>
          <p className="text-muted-foreground mb-8 max-w-2xl mx-auto">
            Unete a los productores que ya confian en AgroProtect para proteger sus inversiones 
            y maximizar sus rendimientos agricolas.
          </p>
          <div className="flex flex-col sm:flex-row items-center justify-center gap-4">
            <Button 
              size="lg"
              className="bg-primary text-primary-foreground hover:bg-primary/90 text-lg px-8 py-6 rounded-xl font-semibold"
            >
              Solicitar Demo
              <ArrowRight className="w-5 h-5 ml-2" />
            </Button>
            <Button 
              size="lg"
              variant="outline"
              onClick={() => setIsAnalyticsOpen(true)}
              className="text-lg px-8 py-6 rounded-xl font-semibold border-border hover:bg-accent"
            >
              Ver Estadisticas
            </Button>
          </div>
        </div>
      </section>

      {/* Footer */}
      <footer className="py-12 bg-surface-container border-t border-border">
        <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
          <div className="flex flex-col md:flex-row items-center justify-between gap-4">
            <div className="flex items-center gap-3">
              <div className="w-8 h-8 rounded-lg bg-primary/10 flex items-center justify-center">
                <Satellite className="w-4 h-4 text-primary" />
              </div>
              <span className="font-bold">
                <span className="text-primary">Agro</span>Protect
              </span>
            </div>
            <p className="text-sm text-muted-foreground">
              Precision Sentinel Dashboard - Argentina
            </p>
          </div>
        </div>
      </footer>

      {/* Analytics Modal */}
      <AnalyticsModal
        isOpen={isAnalyticsOpen}
        onClose={() => setIsAnalyticsOpen(false)}
        provinceStats={provinceStats}
      />

      {/* AI Chat Modal */}
      {isChatOpen && (
        <div className="fixed inset-0 z-[2000] flex items-center justify-center bg-black/60 backdrop-blur-sm p-4">
          <div className="bg-surface-container border border-border w-full max-w-lg h-[600px] rounded-2xl overflow-hidden flex flex-col shadow-2xl">
            {/* Modal Header */}
            <div className="flex items-center justify-between px-6 py-4 border-b border-border bg-surface-container-low">
              <div className="flex items-center gap-3">
                <div className="w-10 h-10 rounded-xl bg-primary/10 flex items-center justify-center">
                  <Bot className="w-5 h-5 text-primary" />
                </div>
                <div>
                  <h3 className="font-bold text-foreground">AgroProtect AI</h3>
                  <p className="text-xs text-muted-foreground">
                    {selectedLocation 
                      ? `Analizando: ${selectedLocation.location_name}` 
                      : 'Asistente de analisis agricola'}
                  </p>
                </div>
              </div>
              <button
                onClick={() => setIsChatOpen(false)}
                className="p-2 rounded-lg hover:bg-surface-container-high transition-colors"
              >
                <X className="w-5 h-5 text-muted-foreground" />
              </button>
            </div>

            {/* Chat Content */}
            <div className="flex-1 overflow-hidden">
              <AIChatPanel 
                selectedLocation={selectedLocation} 
                allData={riskData}
                embedded
              />
            </div>
          </div>
        </div>
      )}
    </div>
  );
}
