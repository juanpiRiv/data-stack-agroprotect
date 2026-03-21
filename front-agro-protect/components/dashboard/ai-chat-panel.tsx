"use client";

import { useState, useRef, useEffect } from "react";
import { useChat } from "@ai-sdk/react";
import { DefaultChatTransport } from "ai";
import { Send, Bot, User, Sparkles, Loader2 } from "lucide-react";
import { RiskData } from "@/lib/types";

interface AIChatPanelProps {
  selectedLocation: RiskData | null;
  allData: RiskData[];
  embedded?: boolean;
}

export function AIChatPanel({ selectedLocation, allData, embedded = false }: AIChatPanelProps) {
  const [input, setInput] = useState("");
  const messagesEndRef = useRef<HTMLDivElement>(null);

  // Prepare location data for context
  const getLocationContext = () => {
    if (selectedLocation) {
      return `
UBICACIÓN SELECCIONADA:
- Ciudad: ${selectedLocation.location_name}
- Provincia: ${selectedLocation.province_name}
- Índice de Riesgo: ${Math.round(selectedLocation.riesgo * 100)}%
- Probabilidad de Lluvia: ${selectedLocation.lluvia}%
- Estrés Hídrico: ${selectedLocation.estres}%
- Estado: ${selectedLocation.riesgo > 0.8 ? "CRÍTICO" : selectedLocation.riesgo > 0.5 ? "VIGILANCIA" : "SEGURO"}
- Coordenadas: ${selectedLocation.latitude.toFixed(4)}, ${selectedLocation.longitude.toFixed(4)}

RESUMEN GENERAL:
- Total de nodos monitoreados: ${allData.length}
- Zonas críticas: ${allData.filter(d => d.riesgo > 0.8).length}
- Zonas en vigilancia: ${allData.filter(d => d.riesgo > 0.5 && d.riesgo <= 0.8).length}
- Zonas seguras: ${allData.filter(d => d.riesgo <= 0.5).length}
- Riesgo promedio nacional: ${Math.round((allData.reduce((a, b) => a + b.riesgo, 0) / allData.length) * 100)}%
`;
    }
    return `
No hay ubicación seleccionada. Datos generales:
- Total de nodos monitoreados: ${allData.length}
- Zonas críticas: ${allData.filter(d => d.riesgo > 0.8).length}
- Zonas en vigilancia: ${allData.filter(d => d.riesgo > 0.5 && d.riesgo <= 0.8).length}
- Zonas seguras: ${allData.filter(d => d.riesgo <= 0.5).length}
- Riesgo promedio nacional: ${Math.round((allData.reduce((a, b) => a + b.riesgo, 0) / allData.length) * 100)}%
`;
  };

  const { messages, sendMessage, status } = useChat({
    transport: new DefaultChatTransport({
      api: "/api/chat",
      prepareSendMessagesRequest: ({ messages }) => ({
        body: {
          messages,
          locationData: getLocationContext(),
        },
      }),
    }),
  });

  const isLoading = status === "streaming" || status === "submitted";

  // Auto-scroll to bottom
  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }, [messages]);

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault();
    if (!input.trim() || isLoading) return;
    sendMessage({ text: input });
    setInput("");
  };

  const suggestedQuestions = [
    "¿Cuál es el estado de riesgo actual?",
    "¿Qué medidas preventivas recomiendas?",
    "¿Cómo afecta el estrés hídrico a los cultivos?",
  ];

  // For embedded mode, render without fixed positioning
  if (embedded) {
    return (
      <div className="h-full flex flex-col">
        {/* Messages */}
        <div className="flex-1 overflow-y-auto p-4 space-y-4">
          {messages.length === 0 ? (
            <div className="space-y-4">
              <div className="text-center py-4">
                <div className="w-10 h-10 rounded-full bg-primary/10 flex items-center justify-center mx-auto mb-3">
                  <Bot className="w-5 h-5 text-primary" />
                </div>
                <p className="text-sm text-muted-foreground mb-1">
                  {selectedLocation
                    ? `Analizando: ${selectedLocation.location_name}`
                    : "Selecciona una ubicacion en el mapa"}
                </p>
                <p className="text-xs text-muted-foreground/70">
                  Pregunta sobre riesgos, clima y recomendaciones
                </p>
              </div>

              <div className="space-y-2">
                <p className="text-[10px] uppercase font-bold text-muted-foreground tracking-wider">
                  Preguntas sugeridas
                </p>
                {suggestedQuestions.map((question, i) => (
                  <button
                    key={i}
                    onClick={() => setInput(question)}
                    className="w-full text-left text-xs p-3 rounded-lg bg-surface-container-high hover:bg-surface-container-highest transition-colors text-foreground/80"
                  >
                    {question}
                  </button>
                ))}
              </div>
            </div>
          ) : (
            messages.map((message) => (
              <div
                key={message.id}
                className={`flex gap-2 ${
                  message.role === "user" ? "justify-end" : "justify-start"
                }`}
              >
                {message.role === "assistant" && (
                  <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-1">
                    <Bot className="w-3 h-3 text-primary" />
                  </div>
                )}
                <div
                  className={`max-w-[85%] rounded-xl px-3 py-2 text-sm ${
                    message.role === "user"
                      ? "bg-primary text-primary-foreground"
                      : "bg-surface-container-high text-foreground"
                  }`}
                >
                  {message.parts.map((part, index) => {
                    if (part.type === "text") {
                      return (
                        <span key={index} className="whitespace-pre-wrap">
                          {part.text}
                        </span>
                      );
                    }
                    return null;
                  })}
                </div>
                {message.role === "user" && (
                  <div className="w-6 h-6 rounded-full bg-secondary/20 flex items-center justify-center flex-shrink-0 mt-1">
                    <User className="w-3 h-3 text-secondary" />
                  </div>
                )}
              </div>
            ))
          )}
          
          {isLoading && (
            <div className="flex gap-2 justify-start">
              <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0">
                <Bot className="w-3 h-3 text-primary" />
              </div>
              <div className="bg-surface-container-high rounded-xl px-3 py-2">
                <Loader2 className="w-4 h-4 animate-spin text-primary" />
              </div>
            </div>
          )}
          
          <div ref={messagesEndRef} />
        </div>

        {/* Input */}
        <form onSubmit={handleSubmit} className="p-4 border-t border-border">
          <div className="flex gap-2">
            <input
              type="text"
              value={input}
              onChange={(e) => setInput(e.target.value)}
              placeholder="Escribe tu pregunta..."
              disabled={isLoading}
              className="flex-1 bg-surface-container-high border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/50 disabled:opacity-50"
            />
            <button
              type="submit"
              disabled={isLoading || !input.trim()}
              className="w-10 h-10 rounded-lg bg-primary text-primary-foreground flex items-center justify-center hover:bg-primary/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
            >
              <Send className="w-4 h-4" />
            </button>
          </div>
        </form>
      </div>
    );
  }

  return (
    <div className="fixed right-0 top-16 w-80 h-[calc(100vh-64px)] bg-surface-container border-l border-border flex flex-col z-50">
      {/* Header */}
      <div className="p-4 border-b border-border">
        <div className="flex items-center gap-2">
          <div className="w-8 h-8 rounded-lg bg-primary/20 flex items-center justify-center">
            <Sparkles className="w-4 h-4 text-primary" />
          </div>
          <div>
            <h3 className="font-bold text-sm text-foreground">AgroProtect AI</h3>
            <p className="text-[10px] text-muted-foreground">Asistente de analisis</p>
          </div>
        </div>
      </div>

      {/* Messages */}
      <div className="flex-1 overflow-y-auto p-4 space-y-4">
        {messages.length === 0 ? (
          <div className="space-y-4">
            <div className="text-center py-6">
              <div className="w-12 h-12 rounded-full bg-primary/10 flex items-center justify-center mx-auto mb-3">
                <Bot className="w-6 h-6 text-primary" />
              </div>
              <p className="text-sm text-muted-foreground mb-1">
                {selectedLocation
                  ? `Analizando: ${selectedLocation.location_name}`
                  : "Selecciona una ubicación en el mapa"}
              </p>
              <p className="text-xs text-muted-foreground/70">
                Pregunta sobre riesgos, clima y recomendaciones
              </p>
            </div>

            <div className="space-y-2">
              <p className="text-[10px] uppercase font-bold text-muted-foreground tracking-wider">
                Preguntas sugeridas
              </p>
              {suggestedQuestions.map((question, i) => (
                <button
                  key={i}
                  onClick={() => {
                    setInput(question);
                  }}
                  className="w-full text-left text-xs p-3 rounded-lg bg-surface-container-high hover:bg-surface-container-highest transition-colors text-foreground/80"
                >
                  {question}
                </button>
              ))}
            </div>
          </div>
        ) : (
          messages.map((message) => (
            <div
              key={message.id}
              className={`flex gap-2 ${
                message.role === "user" ? "justify-end" : "justify-start"
              }`}
            >
              {message.role === "assistant" && (
                <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0 mt-1">
                  <Bot className="w-3 h-3 text-primary" />
                </div>
              )}
              <div
                className={`max-w-[85%] rounded-xl px-3 py-2 text-sm ${
                  message.role === "user"
                    ? "bg-primary text-primary-foreground"
                    : "bg-surface-container-high text-foreground"
                }`}
              >
                {message.parts.map((part, index) => {
                  if (part.type === "text") {
                    return (
                      <span key={index} className="whitespace-pre-wrap">
                        {part.text}
                      </span>
                    );
                  }
                  return null;
                })}
              </div>
              {message.role === "user" && (
                <div className="w-6 h-6 rounded-full bg-secondary/20 flex items-center justify-center flex-shrink-0 mt-1">
                  <User className="w-3 h-3 text-secondary" />
                </div>
              )}
            </div>
          ))
        )}
        
        {isLoading && (
          <div className="flex gap-2 justify-start">
            <div className="w-6 h-6 rounded-full bg-primary/20 flex items-center justify-center flex-shrink-0">
              <Bot className="w-3 h-3 text-primary" />
            </div>
            <div className="bg-surface-container-high rounded-xl px-3 py-2">
              <Loader2 className="w-4 h-4 animate-spin text-primary" />
            </div>
          </div>
        )}
        
        <div ref={messagesEndRef} />
      </div>

      {/* Input */}
      <form onSubmit={handleSubmit} className="p-4 border-t border-border">
        <div className="flex gap-2">
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder="Escribe tu pregunta..."
            disabled={isLoading}
            className="flex-1 bg-surface-container-high border border-border rounded-lg px-3 py-2 text-sm text-foreground placeholder:text-muted-foreground focus:outline-none focus:ring-2 focus:ring-primary/50 disabled:opacity-50"
          />
          <button
            type="submit"
            disabled={isLoading || !input.trim()}
            className="w-10 h-10 rounded-lg bg-primary text-primary-foreground flex items-center justify-center hover:bg-primary/90 transition-colors disabled:opacity-50 disabled:cursor-not-allowed"
          >
            <Send className="w-4 h-4" />
          </button>
        </div>
      </form>
    </div>
  );
}
