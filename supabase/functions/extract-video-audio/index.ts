import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-key',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const MAX_DURATION_MINUTES = 20
const MAX_AUDIO_SIZE_BYTES = 25 * 1024 * 1024 // 25 MB

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const { url, bypass_cache = false, max_duration_minutes = MAX_DURATION_MINUTES } = await req.json()
    if (!url || typeof url !== 'string') {
      return new Response(JSON.stringify({ error: "Missing required parameter: url" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    const mediaServiceUrl = Deno.env.get("MEDIA_SERVICE_URL")?.trim().replace(/\/+$/, '')
    const mediaServiceKey = Deno.env.get("MEDIA_SERVICE_KEY")?.trim()

    if (!mediaServiceUrl) {
      return new Response(JSON.stringify({ error: "MEDIA_SERVICE_URL secret is not configured" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 60000)

    const resp = await fetch(`${mediaServiceUrl}/api/extract-audio`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(mediaServiceKey ? { "X-API-Key": mediaServiceKey } : {})
      },
      body: JSON.stringify({
        url,
        bypass_cache,
        max_duration_minutes
      }),
      signal: controller.signal
    })
    clearTimeout(timeoutId)

    const data = await resp.json()
    if (!resp.ok) {
      return new Response(JSON.stringify(data), {
        status: resp.status,
        headers: { ...corsHeaders, "Content-Type": "application/json" }
      })
    }

    // Guardrail: verify file size <= 25MB
    const sizeBytes = Number(data.file_size_bytes || data.size_bytes) || 0
    const isOver25Mb = data.is_over_25mb ?? (sizeBytes > MAX_AUDIO_SIZE_BYTES)

    return new Response(JSON.stringify({
      ...data,
      is_over_25mb: isOver25Mb,
      ready_for_transcription: !isOver25Mb
    }), {
      status: 200,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  } catch (err: any) {
    return new Response(JSON.stringify({ error: err?.message || String(err) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" }
    })
  }
})
