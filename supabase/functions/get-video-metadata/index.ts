import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-api-key',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const MAX_DURATION_MINUTES = 20
const MAX_DURATION_SECONDS = MAX_DURATION_MINUTES * 60

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
    const timeoutId = setTimeout(() => controller.abort(), 45000)

    const resp = await fetch(`${mediaServiceUrl}/api/metadata`, {
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

    // Early decision tree flag enforcement
    const durationSeconds = Number(data.duration_seconds) || 0
    const exceedsLimit = data.exceeds_duration_limit ?? (durationSeconds > MAX_DURATION_SECONDS)

    return new Response(JSON.stringify({
      ...data,
      exceeds_duration_limit: exceedsLimit,
      allowed_for_transcription: !exceedsLimit
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
