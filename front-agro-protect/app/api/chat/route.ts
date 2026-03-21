import {
  consumeStream,
  convertToModelMessages,
  streamText,
  UIMessage,
} from 'ai'

export const maxDuration = 30

export async function POST(req: Request) {
  const { messages, locationData }: { messages: UIMessage[]; locationData: string } = await req.json()

  const systemPrompt = `Eres AgroProtect AI, un asistente experto en análisis de riesgo agrícola para Argentina. 
Tienes acceso a los datos de monitoreo de las zonas agrícolas en tiempo real.

DATOS DE LA ZONA ACTUAL:
${locationData}

Tu rol es:
- Analizar los datos de riesgo de la zona seleccionada
- Proporcionar recomendaciones agrícolas basadas en los indicadores
- Explicar qué significan los niveles de riesgo, estrés hídrico y probabilidad de lluvia
- Sugerir acciones preventivas según el estado de la zona
- Responder preguntas sobre agricultura, clima y gestión de cultivos en Argentina

Mantén respuestas concisas pero informativas. Usa datos específicos cuando estén disponibles.
Responde siempre en español.`

  const result = streamText({
    model: 'openai/gpt-4o-mini',
    system: systemPrompt,
    messages: await convertToModelMessages(messages),
    abortSignal: req.signal,
  })

  return result.toUIMessageStreamResponse({
    originalMessages: messages,
    consumeSseStream: consumeStream,
  })
}
