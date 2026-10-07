import { serve } from "https://deno.land/std@0.168.0/http/server.ts"
import { createClient } from "https://esm.sh/@supabase/supabase-js@2.39.0"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const supabaseUrl = Deno.env.get("SUPABASE_URL") || ""
const supabaseServiceKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") || ""
const supabase = (supabaseUrl && supabaseServiceKey) 
  ? createClient(supabaseUrl, supabaseServiceKey) 
  : null

const ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages"
const MAX_INPUT_CHARS = 3500

/**
 * SHA-256 hash helper for O(1) transcript cache lookup.
 */
async function hashUrl(url: string): Promise<string> {
  const msgUint8 = new TextEncoder().encode(url.trim().toLowerCase())
  const hashBuffer = await crypto.subtle.digest('SHA-256', msgUint8)
  const hashArray = Array.from(new Uint8Array(hashBuffer))
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('')
}

/**
 * Check if a transcript has already been scraped/transcribed and cached.
 */
async function getCachedTranscript(urlHash: string): Promise<{ transcript: string; transcriptType: string; platform: string; title?: string; creator?: string } | null> {
  if (!supabase) return null
  try {
    const { data, error } = await supabase
      .from('video_transcripts')
      .select('transcript, transcript_type, platform, title, creator')
      .eq('url_hash', urlHash)
      .maybeSingle()
    if (!error && data && data.transcript) {
      console.log(`[generate-scripts] Cache HIT for hash ${urlHash.substring(0, 10)} (${data.platform})`)
      return {
        transcript: data.transcript,
        transcriptType: data.transcript_type || 'whisper',
        platform: data.platform,
        title: data.title,
        creator: data.creator
      }
    }
  } catch (e: any) {
    console.warn("[generate-scripts] Cache check notice (continuing without cache):", e?.message || e)
  }
  return null
}

/**
 * Save newly resolved transcript to the database cache.
 */
async function saveCachedTranscript(urlHash: string, sourceUrl: string, platform: string, transcript: string, transcriptType: string, title?: string, creator?: string) {
  if (!supabase || !transcript || transcript.length < 20) return
  try {
    await supabase
      .from('video_transcripts')
      .upsert({
        url_hash: urlHash,
        source_url: sourceUrl,
        platform,
        transcript,
        transcript_type: transcriptType,
        title: title || null,
        creator: creator || null
      }, { onConflict: 'url_hash' })
    console.log(`[generate-scripts] Saved cache record for ${platform} (${urlHash.substring(0, 10)})`)
  } catch (e: any) {
    console.warn("[generate-scripts] Cache save notice (continuing without cache):", e?.message || e)
  }
}

/**
 * Robustly extract clean 11-character YouTube video IDs from any URL format.
 */
function extractYouTubeVideoId(input: string): string | null {
  const trimmed = input.trim()
  try {
    const url = new URL(trimmed.startsWith("http") ? trimmed : `https://${trimmed}`)
    if (url.hostname.includes("youtube.com")) {
      if (url.pathname.startsWith("/watch")) {
        const v = url.searchParams.get("v")
        if (v && /^[a-zA-Z0-9_-]{11}$/.test(v)) return v
      }
      const shortsMatch = url.pathname.match(/\/shorts\/([a-zA-Z0-9_-]{11})/)
      if (shortsMatch) return shortsMatch[1]
      const embedMatch = url.pathname.match(/\/(?:embed|v)\/([a-zA-Z0-9_-]{11})/)
      if (embedMatch) return embedMatch[1]
    } else if (url.hostname.includes("youtu.be")) {
      const idMatch = url.pathname.match(/^\/([a-zA-Z0-9_-]{11})/)
      if (idMatch) return idMatch[1]
    }
  } catch (_) {}

  const patterns = [
    /[?&]v=([a-zA-Z0-9_-]{11})(?:[&?]|$)/,
    /youtu\.be\/([a-zA-Z0-9_-]{11})(?:[?&/]|$)/,
    /youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})(?:[?&/]|$)/,
    /youtube\.com\/embed\/([a-zA-Z0-9_-]{11})(?:[?&/]|$)/,
    /youtube\.com\/v\/([a-zA-Z0-9_-]{11})(?:[?&/]|$)/,
    /^([a-zA-Z0-9_-]{11})$/
  ]
  for (const p of patterns) {
    const m = trimmed.match(p)
    if (m && m[1]) return m[1]
  }
  return null
}

/**
 * Detect social video platforms (TikTok, Instagram Reels, Facebook Reels, YouTube)
 */
function detectVideoPlatform(input: string): { platform: string; isVideoUrl: boolean } {
  const lower = input.toLowerCase()
  if (lower.includes("youtube.com") || lower.includes("youtu.be")) {
    return { platform: "YouTube", isVideoUrl: true }
  }
  if (lower.includes("tiktok.com")) {
    return { platform: "TikTok", isVideoUrl: true }
  }
  if (lower.includes("instagram.com")) {
    return { platform: "Instagram Reels", isVideoUrl: true }
  }
  if (lower.includes("facebook.com") || lower.includes("fb.watch")) {
    return { platform: "Facebook Reels", isVideoUrl: true }
  }
  return { platform: "Generic", isVideoUrl: input.startsWith("http://") || input.startsWith("https://") }
}

const MAX_AUDIO_EXTRACTION_DURATION_SECONDS = 20 * 60 // 20 minutes (1200 seconds)

function formatDuration(seconds: number): string {
  if (seconds <= 0) return ""
  const m = Math.floor(seconds / 60)
  const s = seconds % 60
  if (m >= 60) {
    const h = Math.floor(m / 60)
    const remM = m % 60
    return `${h} hr ${remM} min`
  }
  return s > 0 ? `${m} min ${s}s` : `${m} min`
}

/**
 * Tier 0 (Self-Hosted Priority): MediaMetaData_Transcriber Microservice
 * Resolves metadata and transcribes audio via local residential GPU server.
 */
interface MediaServiceMetadata {
  job_id?: string | null
  url: string
  title?: string
  creator?: string
  uploader?: string
  duration_seconds?: number
  duration_formatted?: string
  platform?: string
  description?: string
  exceeds_duration_limit?: boolean
  max_duration_seconds?: number
  allowed_for_transcription?: boolean
}

interface MediaServiceTranscribe {
  job_id?: string
  url?: string
  status?: string
  elapsed_time?: number
  metadata?: {
    title?: string
    duration_seconds?: number
    duration_formatted?: string
  }
  transcript?: {
    text?: string
    language?: string
    engine?: string
    segments?: any[]
  }
}

async function callMediaServiceMetadata(url: string, bypassCache: boolean = false, diagnostics?: any): Promise<MediaServiceMetadata | null> {
  const baseUrl = Deno.env.get("MEDIA_SERVICE_URL")?.trim()
  const apiKey = Deno.env.get("MEDIA_SERVICE_KEY")?.trim()
  if (!baseUrl) return null

  try {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 45000)
    const normalizedUrl = baseUrl.replace(/\/+$/, '')
    console.log(`[generate-scripts] [MediaService] Requesting metadata for: ${url} via ${normalizedUrl}`)

    const resp = await fetch(`${normalizedUrl}/api/metadata`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(apiKey ? { "X-API-Key": apiKey } : {})
      },
      body: JSON.stringify({
        url,
        bypass_cache: bypassCache,
        max_duration_minutes: 20
      }),
      signal: controller.signal
    })
    clearTimeout(timeoutId)

    if (diagnostics) {
      diagnostics.mediaService = { metadataStatus: resp.status }
    }

    if (resp.ok) {
      const data = await resp.json()
      console.log(`[generate-scripts] [MediaService] Metadata received: "${data.title}" (${data.duration_formatted || data.duration_seconds + 's'})`)
      return data
    } else {
      console.warn(`[generate-scripts] [MediaService] Metadata returned HTTP ${resp.status}`)
    }
  } catch (err: any) {
    console.warn(`[generate-scripts] [MediaService] Metadata notice:`, err?.message || err)
    if (diagnostics) {
      diagnostics.mediaService = { ...(diagnostics.mediaService || {}), metadataError: err?.message || String(err) }
    }
  }
  return null
}

async function callMediaServiceTranscribe(url: string, bypassCache: boolean = false, diagnostics?: any): Promise<MediaServiceTranscribe | null> {
  const baseUrl = Deno.env.get("MEDIA_SERVICE_URL")?.trim()
  const apiKey = Deno.env.get("MEDIA_SERVICE_KEY")?.trim()
  if (!baseUrl) return null

  try {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 120000) // 120s timeout for GPU inference
    const normalizedUrl = baseUrl.replace(/\/+$/, '')
    console.log(`[generate-scripts] [MediaService] Requesting transcription for: ${url} via ${normalizedUrl}`)

    const resp = await fetch(`${normalizedUrl}/api/transcribe`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        ...(apiKey ? { "X-API-Key": apiKey } : {})
      },
      body: JSON.stringify({
        url,
        speed_profile: "adaptive",
        bypass_cache: bypassCache,
        max_duration_minutes: 20
      }),
      signal: controller.signal
    })
    clearTimeout(timeoutId)

    if (diagnostics) {
      diagnostics.mediaService = { ...(diagnostics.mediaService || {}), transcribeStatus: resp.status }
    }

    if (resp.ok) {
      const data = await resp.json()
      const textLen = data.transcript?.text?.length || 0
      console.log(`[generate-scripts] [MediaService] Transcription SUCCESS in ${data.elapsed_time}s (${textLen} chars, engine: ${data.transcript?.engine})`)
      if (diagnostics) {
        diagnostics.mediaService.transcribeResult = {
          elapsed: data.elapsed_time,
          engine: data.transcript?.engine,
          textLength: textLen
        }
      }
      return data
    } else {
      const errText = await resp.text().catch(() => "")
      console.warn(`[generate-scripts] [MediaService] Transcription returned HTTP ${resp.status}:`, errText)
    }
  } catch (err: any) {
    console.warn(`[generate-scripts] [MediaService] Transcription notice:`, err?.message || err)
    if (diagnostics) {
      diagnostics.mediaService = { ...(diagnostics.mediaService || {}), transcribeError: err?.message || String(err) }
    }
  }
  return null
}

/**
 * Tier 1: Fetch official creator or automated closed captions directly from YouTube player, plus metadata and duration.
 */
async function fetchYouTubeData(videoId: string, diagnostics?: any): Promise<{ 
  transcript: string | null; 
  durationSeconds: number; 
  title?: string; 
  creator?: string;
  description?: string;
}> {
  console.log(`[generate-scripts] [YouTube Tier 1] Fetching caption tracks and details for videoId: ${videoId}`)
  try {
    const watchUrl = `https://www.youtube.com/watch?v=${videoId}`
    const pageResp = await fetch(watchUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      }
    })

    if (!pageResp.ok) {
      if (diagnostics) diagnostics.youtube = { pageStatus: pageResp.status }
      return { transcript: null, durationSeconds: 0 }
    }
    const html = await pageResp.text()

    const playerResponseMatch = html.match(/ytInitialPlayerResponse\s*=\s*({.+?});(?:var|\n|<\/script>)/) ||
                                html.match(/var ytInitialPlayerResponse = ({.+?});/)
    
    if (!playerResponseMatch || !playerResponseMatch[1]) {
      if (diagnostics) diagnostics.youtube = { playerResponseFound: false }
      return { transcript: null, durationSeconds: 0 }
    }

    let playerResponse: any
    try {
      playerResponse = JSON.parse(playerResponseMatch[1])
    } catch (_) {
      return { transcript: null, durationSeconds: 0 }
    }

    const durationSeconds = Number(playerResponse?.videoDetails?.lengthSeconds) || 0
    const title = playerResponse?.videoDetails?.title || ""
    const creator = playerResponse?.videoDetails?.author || ""
    const description = playerResponse?.videoDetails?.shortDescription || ""

    const captionTracks = playerResponse?.captions?.playerCaptionsTracklistRenderer?.captionTracks
    if (diagnostics) {
      diagnostics.youtube = {
        title,
        durationSeconds,
        tracksCount: Array.isArray(captionTracks) ? captionTracks.length : 0
      }
    }
    if (!captionTracks || !Array.isArray(captionTracks) || captionTracks.length === 0) {
      return { transcript: null, durationSeconds, title, creator, description }
    }

    const selectedTrack = captionTracks.find((t: any) => t.languageCode === 'en' || t.vssId?.includes('.en')) || captionTracks[0]
    if (!selectedTrack?.baseUrl) {
      return { transcript: null, durationSeconds, title, creator, description }
    }

    if (diagnostics && diagnostics.youtube) {
      diagnostics.youtube.selectedLang = selectedTrack.languageCode || selectedTrack.vssId
      diagnostics.youtube.trackName = selectedTrack.name?.simpleText
    }

    const transcriptResp = await fetch(selectedTrack.baseUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Referer": "https://www.youtube.com/"
      }
    })
    if (diagnostics && diagnostics.youtube) {
      diagnostics.youtube.transcriptHttpStatus = transcriptResp.status
    }
    if (!transcriptResp.ok) {
      return { transcript: null, durationSeconds, title, creator, description }
    }

    const transcriptXml = await transcriptResp.text()
    if (diagnostics && diagnostics.youtube) {
      diagnostics.youtube.xmlLength = transcriptXml.length
      if (transcriptXml.length > 0) {
        diagnostics.youtube.xmlPreview = transcriptXml.substring(0, 100)
      }
    }
    if (!transcriptXml || transcriptXml.trim() === "") {
      return { transcript: null, durationSeconds, title, creator, description }
    }

    const cleanText = transcriptXml
      .replace(/&amp;/g, '&')
      .replace(/&lt;/g, '<')
      .replace(/&gt;/g, '>')
      .replace(/&quot;/g, '"')
      .replace(/&#39;/g, "'")
      .replace(/&apos;/g, "'")
      .replace(/<[^>]+>/g, ' ')
      .replace(/\s+/g, ' ')
      .trim()

    const transcript = cleanText.length >= 30 ? cleanText : null
    return { transcript, durationSeconds, title, creator, description }
  } catch (err) {
    console.warn("[generate-scripts] [YouTube Tier 1] Transcript extraction error:", err)
    if (diagnostics) diagnostics.youtube = { error: String(err) }
    return { transcript: null, durationSeconds: 0 }
  }
}

/**
 * Universal video metadata resolution via OpenGraph & oEmbed
 */
async function fetchUniversalVideoMetadata(rawUrl: string, platform: string): Promise<{
  title?: string;
  creator?: string;
  description?: string;
  durationSeconds?: number;
}> {
  console.log(`[generate-scripts] Resolving video metadata for platform: ${platform} - URL: ${rawUrl}`)
  let title = ""
  let description = ""
  let creator = ""
  let durationSeconds = 0

  // 1. YouTube specific oEmbed
  if (platform === "YouTube") {
    const videoId = extractYouTubeVideoId(rawUrl)
    if (videoId) {
      try {
        const oembedResp = await fetch(`https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${videoId}&format=json`)
        if (oembedResp.ok) {
          const data = await oembedResp.json()
          title = data.title || ""
          creator = data.author_name || ""
        }
      } catch (_) {}
    }
  }

  // 2. Generic HTML OpenGraph scraper for all platforms
  try {
    const formattedUrl = rawUrl.startsWith("http") ? rawUrl : `https://${rawUrl}`
    const pageResp = await fetch(formattedUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9"
      }
    })

    if (pageResp.ok) {
      const html = await pageResp.text()
      if (!title) {
        const titleMatch = html.match(/<meta property="og:title" content="(.+?)"/) ||
                           html.match(/<title>(.+?)<\/title>/)
        if (titleMatch && titleMatch[1]) {
          title = titleMatch[1].replace(/ - (?:YouTube|TikTok|Instagram|Facebook)$/i, "").trim()
        }
      }
      if (!description) {
        const descMatch = html.match(/<meta property="og:description" content="(.+?)"/) ||
                          html.match(/<meta name="description" content="(.+?)"/)
        if (descMatch && descMatch[1]) {
          description = descMatch[1]
            .replace(/&amp;/g, '&')
            .replace(/&quot;/g, '"')
            .replace(/&#39;/g, "'")
            .trim()
        }
      }
      const durMatch = html.match(/"lengthSeconds":"(\d+)"/) || html.match(/<meta property="video:duration" content="(\d+)"/)
      if (durMatch && durMatch[1]) {
        durationSeconds = Number(durMatch[1]) || 0
      }
    }
  } catch (e) {
    console.warn("[generate-scripts] Universal metadata scrape notice:", e)
  }

  return { title, creator, description, durationSeconds }
}

function buildMetadataDisplayText(
  platform: string,
  rawUrl: string,
  title?: string,
  creator?: string,
  description?: string,
  durationSeconds?: number,
  limitNotice?: string
): string {
  const durationText = durationSeconds && durationSeconds > 0 ? formatDuration(durationSeconds) : null

  const lines = [
    `Platform: ${platform}`,
    `Source URL: ${rawUrl}`,
    durationText ? `Video Duration: ${durationText}` : null,
    title ? `Video Title: ${title}` : null,
    creator ? `Creator: ${creator}` : null,
    limitNotice ? `Notice: ${limitNotice}` : null,
    description ? `Description / Summary:\n${description}` : null
  ].filter(Boolean)

  if (lines.length <= 2) {
    return `Video Source: ${platform} Link (${rawUrl}). Create a high-value, detailed 3-5 minute speaking reaction and breakdown for this video topic.`
  }

  return lines.join("\n\n")
}

/**
 * Dedicated TikTok media resolver via TikWM API (retrieves direct MP3 audio stream).
 */
async function fetchTikTokMedia(rawUrl: string): Promise<{ audioUrl: string | null; title?: string; creator?: string; durationSeconds?: number }> {
  console.log(`[generate-scripts] Querying TikWM audio extraction for: ${rawUrl}`)
  try {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 6000)
    const resp = await fetch(`https://www.tikwm.com/api/?url=${encodeURIComponent(rawUrl)}`, {
      signal: controller.signal,
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      }
    })
    clearTimeout(timeoutId)

    if (resp.ok) {
      const json = await resp.json()
      if (json.code === 0 && json.data) {
        const audioUrl = json.data.music_info?.play || json.data.music || json.data.play || null
        const title = json.data.title || ""
        const creator = json.data.author?.nickname || json.data.author?.unique_id || ""
        const durationSeconds = Number(json.data.duration) || 0
        if (audioUrl) {
          console.log(`[generate-scripts] TikWM found audio URL: ${audioUrl.substring(0, 50)}...`)
          return { audioUrl, title, creator, durationSeconds }
        }
      }
    }
  } catch (e: any) {
    console.warn("[generate-scripts] TikWM notice:", e?.message || e)
  }
  return { audioUrl: null }
}



/**
 * Downloads audio stream and sends to Groq Whisper Large v3 Turbo (with OpenAI Whisper fallback).
 */
async function transcribeAudioWithWhisper(audioUrl: string, diagnostics?: any): Promise<string | null> {
  const groqApiKey = Deno.env.get("GROQ_API_KEY")?.trim().replace(/^["']|["']$/g, "")
  const openaiApiKey = Deno.env.get("OPENAI_API_KEY")?.trim().replace(/^["']|["']$/g, "")

  if (!groqApiKey && !openaiApiKey) {
    console.log("[generate-scripts] Neither GROQ_API_KEY nor OPENAI_API_KEY is configured. Skipping Whisper.")
    if (diagnostics) diagnostics.whisper = { status: "no_whisper_keys" }
    return null
  }

  console.log(`[generate-scripts] Streaming audio from: ${audioUrl.substring(0, 70)}...`)
  try {
    const controller = new AbortController()
    const timeoutId = setTimeout(() => controller.abort(), 12000)

    const audioResp = await fetch(audioUrl, {
      signal: controller.signal,
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      }
    })
    clearTimeout(timeoutId)

    if (!audioResp.ok) {
      console.warn(`[generate-scripts] Audio stream fetch failed with HTTP ${audioResp.status}`)
      if (diagnostics) diagnostics.whisper = { audioFetchStatus: audioResp.status }
      return null
    }

    const audioBlob = await audioResp.blob()
    const sizeKb = Math.round(audioBlob.size / 1024)
    console.log(`[generate-scripts] Audio stream downloaded (${sizeKb} KB). Forwarding to Whisper...`)
    if (diagnostics) diagnostics.whisper = { audioBlobSizeKb: sizeKb }
    if (audioBlob.size < 2048) {
      console.warn("[generate-scripts] Audio stream is empty or too small.")
      return null
    }

    // 1. Priority: Groq Whisper Large v3 Turbo (<400ms, $0.00066/min)
    if (groqApiKey) {
      const groqFormData = new FormData()
      groqFormData.append("file", audioBlob, "audio.mp3")
      groqFormData.append("model", "whisper-large-v3-turbo")
      groqFormData.append("response_format", "json")
      groqFormData.append("temperature", "0.0")

      const startTime = performance.now()
      const groqResp = await fetch("https://api.groq.com/openai/v1/audio/transcriptions", {
        method: "POST",
        headers: { "Authorization": `Bearer ${groqApiKey}` },
        body: groqFormData
      })

      if (groqResp.ok) {
        const groqJson = await groqResp.json()
        const text = groqJson.text?.trim()
        const duration = Math.round(performance.now() - startTime)
        if (diagnostics) {
          diagnostics.whisper.groq = { status: 200, durationMs: duration, textLength: text?.length || 0 }
        }
        if (text && text.length >= 25) {
          console.log(`[generate-scripts] Groq Whisper Turbo transcription SUCCESS in ${duration}ms (${text.length} chars)`)
          return text
        }
      } else {
        const errText = await groqResp.text()
        console.warn(`[generate-scripts] Groq Whisper failed (${groqResp.status}):`, errText)
        if (diagnostics) diagnostics.whisper.groq = { status: groqResp.status, error: errText }
      }
    }

    // 2. Fallback: OpenAI Whisper-1
    if (openaiApiKey) {
      const oaiFormData = new FormData()
      oaiFormData.append("file", audioBlob, "audio.mp3")
      oaiFormData.append("model", "whisper-1")
      oaiFormData.append("response_format", "json")

      const oaiResp = await fetch("https://api.openai.com/v1/audio/transcriptions", {
        method: "POST",
        headers: { "Authorization": `Bearer ${openaiApiKey}` },
        body: oaiFormData
      })

      if (oaiResp.ok) {
        const oaiJson = await oaiResp.json()
        const text = oaiJson.text?.trim()
        if (text && text.length >= 25) {
          console.log(`[generate-scripts] OpenAI Whisper-1 transcription SUCCESS (${text.length} chars)`)
          return text
        }
      }
    }
  } catch (err: any) {
    console.warn("[generate-scripts] Whisper audio pipeline exception:", err?.message || err)
  }
  return null
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const requestStartTime = performance.now()

  try {
    const rawKey = Deno.env.get("ANTHROPIC_API_KEY") || ""
    const anthropicApiKey = rawKey.trim().replace(/^["']|["']$/g, "")
    if (!anthropicApiKey) {
      return new Response(
        JSON.stringify({ 
          error: "Configuration Error: ANTHROPIC_API_KEY is not set in Supabase Edge Function secrets." 
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    let payload: { 
      inputText?: string; 
      scriptStyle?: string; 
      model?: string; 
      outputCount?: number; 
      inputType?: string; 
      style?: string; 
      targetDurationMinutes?: number;
      anonymousUserId?: string;
      clientTier?: string;
    } = {}
    try {
      const bodyText = await req.text()
      payload = JSON.parse(bodyText)
    } catch (parseError: any) {
      return new Response(
        JSON.stringify({ error: `Malformed JSON request body: ${parseError.message}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 1. Quota Enforcement via Supabase Postgres RPC
    let quotaCheck: any = null
    if (supabase && payload.anonymousUserId) {
      try {
        console.log(`[generate-scripts] Checking quota for user: ${payload.anonymousUserId}, tier: ${payload.clientTier || 'free'}`)
        const { data, error } = await supabase.rpc('check_quota', {
          p_anon_id: payload.anonymousUserId,
          p_tier: payload.clientTier || 'free'
        })
        if (error) {
          console.warn(`[generate-scripts] check_quota error:`, error.message)
        } else if (data) {
          quotaCheck = data
          console.log(`[generate-scripts] Quota check result:`, quotaCheck)
          if (quotaCheck.allowed === false) {
            return new Response(
              JSON.stringify({ 
                error: `Usage limit reached (${quotaCheck.limit - quotaCheck.remaining}/${quotaCheck.limit}). Upgrade to Pro for more generations.`,
                quota: quotaCheck
              }),
              { status: 429, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            )
          }
        }
      } catch (dbErr: any) {
        console.warn(`[generate-scripts] Failed to execute check_quota RPC:`, dbErr?.message || dbErr)
      }
    }

    let { inputText, scriptStyle, style, inputType, targetDurationMinutes } = payload
    const effectiveStyle = scriptStyle || style || 'Casual & Relatable'
    const durationMinutes = Math.min(5, Math.max(1, Math.round(Number(targetDurationMinutes) || 3)))
    const durationLabel = durationMinutes === 1 ? "1 minute" : `${durationMinutes} minutes`
    const targetWordsMin = durationMinutes * 130
    const targetWordsMax = durationMinutes * 165

    if (!inputText || inputText.trim() === "") {
      return new Response(
        JSON.stringify({ error: "Missing required field: inputText cannot be empty." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const rawOriginalInput = inputText.trim()
    const { platform, isVideoUrl } = detectVideoPlatform(rawOriginalInput)
    let resolvedPlatform = isVideoUrl ? platform : "User Input"
    let resolvedTranscriptType = isVideoUrl ? "metadata" : "user_input"
    let finalTranscript = rawOriginalInput

    const diagnostics: any = payload.debug ? {} : null

    // 3. Multi-Platform Video Audio Extraction & Transcript Resolution
    if (inputType === 'video' || inputType === 'youtube' || inputType === 'url' || isVideoUrl) {
      const urlHash = await hashUrl(rawOriginalInput)

      // Step A: Check DB Cache (Bypass if requested or if existing cache is only metadata and we now have extraction keys)
      const cached = (payload.bypassCache === true) ? null : await getCachedTranscript(urlHash)
      const hasExtractionKeys = Boolean(
        Deno.env.get("MEDIA_SERVICE_URL") ||
        Deno.env.get("GROQ_API_KEY")
      )

      if (cached && (cached.transcriptType === 'whisper' || cached.transcriptType === 'closed_captions' || !hasExtractionKeys)) {
        finalTranscript = cached.transcript
        resolvedTranscriptType = cached.transcriptType
        resolvedPlatform = cached.platform
        if (diagnostics) diagnostics.cache = "hit"
      } else {
        if (diagnostics) diagnostics.cache = cached ? "upgrade_metadata" : "miss"

        // 1. Find video metadata across any platform
        let videoTitle: string | undefined = undefined
        let creatorName: string | undefined = undefined
        let videoDescription: string | undefined = undefined
        let durationSeconds: number = 0
        let platformCaptions: string | null = null
        let audioUrl: string | null = null
        let mediaServiceMetadata: MediaServiceMetadata | null = null

        // Step 1.0: Priority Self-Hosted MediaMetaData_Transcriber (bypasses Google CDN 403 & 429)
        if (Deno.env.get("MEDIA_SERVICE_URL")) {
          mediaServiceMetadata = await callMediaServiceMetadata(rawOriginalInput, payload.bypassCache === true, diagnostics)
          if (mediaServiceMetadata) {
            if (mediaServiceMetadata.title) videoTitle = mediaServiceMetadata.title
            if (mediaServiceMetadata.creator || mediaServiceMetadata.uploader) {
              creatorName = mediaServiceMetadata.creator || mediaServiceMetadata.uploader
            }
            if (mediaServiceMetadata.description) videoDescription = mediaServiceMetadata.description
            if (mediaServiceMetadata.duration_seconds) durationSeconds = Number(mediaServiceMetadata.duration_seconds)
            if (mediaServiceMetadata.platform) resolvedPlatform = mediaServiceMetadata.platform
            if (diagnostics) diagnostics.mediaService = { ...(diagnostics.mediaService || {}), resolved: true }
          }
        }

        // Step 1A: YouTube Specific Data Fallback (Captions, Metadata, Duration)
        if (resolvedPlatform === "YouTube" && (!videoTitle || durationSeconds === 0)) {
          const ytId = extractYouTubeVideoId(rawOriginalInput)
          if (ytId) {
            const ytData = await fetchYouTubeData(ytId, diagnostics)
            if (ytData.title && !videoTitle) videoTitle = ytData.title
            if (ytData.creator && !creatorName) creatorName = ytData.creator
            if (ytData.description && !videoDescription) videoDescription = ytData.description
            if (ytData.durationSeconds && durationSeconds === 0) durationSeconds = ytData.durationSeconds
            platformCaptions = ytData.transcript
          }
        }

        // Step 1B: TikTok Dedicated Data Fallback
        if (resolvedPlatform === "TikTok" && (!videoTitle || durationSeconds === 0)) {
          const tikMedia = await fetchTikTokMedia(rawOriginalInput)
          if (tikMedia.title) videoTitle = tikMedia.title
          if (tikMedia.creator) creatorName = tikMedia.creator
          if (tikMedia.durationSeconds) durationSeconds = tikMedia.durationSeconds
          if (tikMedia.audioUrl) audioUrl = tikMedia.audioUrl
        }

        // Step 1C: Universal OpenGraph fallback for missing title, author, or description
        if (!videoTitle || !videoDescription) {
          const ogMeta = await fetchUniversalVideoMetadata(rawOriginalInput, resolvedPlatform)
          if (ogMeta.title && !videoTitle) videoTitle = ogMeta.title
          if (ogMeta.creator && !creatorName) creatorName = ogMeta.creator
          if (ogMeta.description && !videoDescription) videoDescription = ogMeta.description
          if (ogMeta.durationSeconds && durationSeconds === 0) durationSeconds = ogMeta.durationSeconds
        }

        // 2a. If OVER 20 minutes (1200 seconds): return metadata & generate AI response (no Whisper)
        if (durationSeconds > MAX_AUDIO_EXTRACTION_DURATION_SECONDS || mediaServiceMetadata?.exceeds_duration_limit === true) {
          const durationStr = formatDuration(durationSeconds)
          console.log(`[generate-scripts] Video duration is ${durationStr} (> 20 min limit). Generating response from metadata.`)
          finalTranscript = buildMetadataDisplayText(
            resolvedPlatform,
            rawOriginalInput,
            videoTitle,
            creatorName,
            videoDescription,
            durationSeconds,
            `Video duration is ${durationStr} (exceeds the 20-minute audio limit). Response generated from video metadata & summary.`
          )
          resolvedTranscriptType = "metadata"
          if (diagnostics) {
            diagnostics.durationExceededLimit = { durationSeconds, formatted: durationStr }
          }
        } else {
          // 2b. If UNDER 20 minutes:
          // Priority 2b.1: Transcribe via self-hosted MediaMetaData_Transcriber GPU pipeline
          if (mediaServiceMetadata && mediaServiceMetadata.allowed_for_transcription !== false) {
            const mediaTranscribeResult = await callMediaServiceTranscribe(rawOriginalInput, payload.bypassCache === true, diagnostics)
            if (mediaTranscribeResult?.transcript?.text && mediaTranscribeResult.transcript.text.trim().length >= 25) {
              finalTranscript = mediaTranscribeResult.transcript.text.trim()
              resolvedTranscriptType = "whisper"
              if (mediaTranscribeResult.metadata?.title && !videoTitle) {
                videoTitle = mediaTranscribeResult.metadata.title
              }
              await saveCachedTranscript(urlHash, rawOriginalInput, resolvedPlatform, finalTranscript, 'whisper', videoTitle, creatorName)
            }
          }

          // Priority 2b.2: If MediaService didn't transcribe, check platform captions (e.g., closed captions)
          if (resolvedTranscriptType !== "whisper") {
            if (platformCaptions) {
              finalTranscript = platformCaptions
              resolvedTranscriptType = "closed_captions"
            } else if (audioUrl) {
              // Transcript not available on platform -> send to Groq for transcription
              const whisperText = await transcribeAudioWithWhisper(audioUrl, diagnostics)
              if (whisperText) {
                finalTranscript = whisperText
                resolvedTranscriptType = "whisper"
                await saveCachedTranscript(urlHash, rawOriginalInput, resolvedPlatform, finalTranscript, 'whisper', videoTitle, creatorName)
              }
            }
          }

          // If neither platform transcript nor Whisper was available, fall back to metadata
          if (resolvedTranscriptType !== "closed_captions" && resolvedTranscriptType !== "whisper") {
            const durationStr = durationSeconds > 0 ? formatDuration(durationSeconds) : ""
            finalTranscript = buildMetadataDisplayText(
              resolvedPlatform,
              rawOriginalInput,
              videoTitle,
              creatorName,
              videoDescription,
              durationSeconds,
              durationStr
                ? `Video duration is ${durationStr}. Platform captions and direct audio extraction were unavailable for this video. Response generated from video metadata & summary.`
                : `Platform captions and direct audio extraction were unavailable for this video. Response generated from video metadata & summary.`
            )
            resolvedTranscriptType = "metadata"
          }
        }

        // Step E: Save to Transcript Cache
        await saveCachedTranscript(urlHash, rawOriginalInput, resolvedPlatform, finalTranscript, resolvedTranscriptType, videoTitle, creatorName)
      }
    }

    // 4. Streamlined Input Clamping for Claude Prompting
    const trimmedForPrompt = finalTranscript.trim()
    const sanitizedInput = trimmedForPrompt.length > MAX_INPUT_CHARS
      ? trimmedForPrompt.substring(0, MAX_INPUT_CHARS) + "\n[...content truncated for concise processing...]"
      : trimmedForPrompt

    const requestHeaders = {
      "x-api-key": anthropicApiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    }

    // 5. Model selection driven by ANTHROPIC_MODEL secret
    const anthropicModelSecret = Deno.env.get("ANTHROPIC_MODEL")
    if (!anthropicModelSecret || anthropicModelSecret.trim() === "") {
      return new Response(
        JSON.stringify({ error: "Configuration Error: ANTHROPIC_MODEL secret is not set. Go to Supabase Dashboard → Edge Functions → Secrets and add ANTHROPIC_MODEL with your desired Claude model name." }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    const secretModels = anthropicModelSecret.split(",").map(m => m.trim()).filter(Boolean)
    const modelHierarchy = Array.from(new Set([payload.model, ...secretModels].filter(Boolean) as string[]))

    // 6. Style-Specific System Prompts for 3-5 Minute Continuous Spoken Monologue
    const stylePrompts: Record<string, string> = {
      'Casual & Relatable': `You are an engaging, relatable creator filming a direct-to-camera commentary and breakdown video. Speak directly to your audience like a close friend breaking down an eye-opening revelation. Use natural conversational rhythm, rhetorical questions, and authentic enthusiasm.`,

      'Direct Response Sales': `You are an authoritative strategist filming a high-converting video breakdown. Deliver sharp analysis, high-urgency logic, psychological hooks, and clear commercial takeaways designed for maximum viewer conviction.`,

      'Storytelling & Narrative': `You are a master storyteller filming an immersive narrative exploration. Build curiosity with a mystery or tension hook, develop emotional stakes through vivid observations, and land on a powerful human lesson.`,

      'Controversial / Hot Take': `You are a bold, contrarian thinker filming an unfiltered breakdown that challenges conventional wisdom. Open with your sharpest hot take, dismantle popular misconceptions with clear logic, and pose a provocative challenge to your audience.`,

      'High-Value Educational': `You are an expert educator delivering an in-depth, structured masterclass breakdown. Deliver immediate actionable value using a clear multi-point framework that leaves viewers with profound insights.`
    }

    const persona = stylePrompts[effectiveStyle] || stylePrompts['Casual & Relatable']

    const systemPrompt = `${persona}

CORE SCRIPTWRITING REQUIREMENTS:
1. PURE SPOKEN SCRIPT ONLY: Write pure, natural spoken dialogue designed for continuous teleprompter delivery. Do NOT include any video editing directions, camera cues, cutaway notes, sound effects, or bracketed stage markers (e.g., do NOT output "[CUE: ...]", "[Hook]", etc.).
2. TARGET SPOKEN DURATION (${durationLabel.toUpperCase()}): The user has specifically requested a spoken presentation length of ${durationLabel}. The body must contain approximately ${targetWordsMin} to ${targetWordsMax} spoken words of substantive, high-retention text divided into natural, readable paragraphs (representing exactly ${durationLabel} of speech at 130-165 words per minute). Calibrate the depth, examples, and narrative pacing so that reading aloud fills this target length naturally.
3. THIRD-PERSON PERSPECTIVE: React to and explore the source material as an outside creator/expert presenting commentary to your audience. Never pretend to be the original person in the source transcript.
4. TELEPROMPTER READY: Write with natural pauses, rhetorical cadence, and smooth vocal transitions.

Output ONLY valid JSON matching this exact structure (no markdown fences, no backticks, no preamble):
{
  "script": {
    "title": "Compelling Presentation Title",
    "hook": "Strong 10-15s opening spoken hook capturing immediate attention (approx 25-40 words)",
    "body": "Detailed ${durationLabel} spoken presentation text (~${targetWordsMin}-${targetWordsMax} words) divided into clear thematic paragraphs without any camera cues or bracketed stage markers",
    "callToAction": "Natural closing takeaway and engagement call to action (approx 25-35 words)",
    "estimatedDuration": "${durationLabel}",
    "keyTakeaway": "Single-sentence core summary of the breakdown"
  }
}`

    const maxTokensBudget = 4400

    let finalResponse: Response | null = null
    let rawResponseText = ""
    let successfulModel = ""
    const modelErrors: string[] = []

    for (const currentModel of modelHierarchy) {
      console.log(`[generate-scripts] Dispatching with model '${currentModel}' (budget: ${maxTokensBudget})...`)
      
      const requestBody = {
        model: currentModel,
        max_tokens: maxTokensBudget,
        temperature: 0.7,
        messages: [{ role: "user", content: `${systemPrompt}\n\nSource Content:\n${sanitizedInput}` }]
      }

      try {
        const resp = await fetch(ANTHROPIC_ENDPOINT, {
          method: "POST",
          headers: requestHeaders,
          body: JSON.stringify(requestBody)
        })

        if (resp.ok) {
          rawResponseText = await resp.text()
          successfulModel = currentModel
          finalResponse = resp
          console.log(`[generate-scripts] Model '${currentModel}' succeeded.`)
          break
        } else {
          const errBody = await resp.text()
          const errMsg = `Model '${currentModel}' failed (${resp.status}): ${errBody}`
          console.warn(`[generate-scripts] ${errMsg}`)
          modelErrors.push(errMsg)
        }
      } catch (networkErr: any) {
        const errMsg = `Model '${currentModel}' network error: ${networkErr?.message || networkErr}`
        console.warn(`[generate-scripts] ${errMsg}`)
        modelErrors.push(errMsg)
      }
    }

    if (!finalResponse || !rawResponseText) {
      const combinedErrors = modelErrors.join(" | ")
      console.error(`[generate-scripts] All models failed: ${combinedErrors}`)
      return new Response(
        JSON.stringify({ 
          error: `Anthropic API Error: ${combinedErrors}` 
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 8. Parse Anthropic Response
    const result = JSON.parse(rawResponseText)
    if (!result.content || !Array.isArray(result.content) || result.content.length === 0 || !result.content[0].text) {
      return new Response(
        JSON.stringify({ error: "Unexpected Anthropic response structure" }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    let contentText = result.content[0].text.trim()
    if (contentText.startsWith("```")) {
      contentText = contentText.replace(/^```(?:json)?\n?/, "").replace(/\n?```$/, "").trim()
    }

    let parsedJSON: any
    try {
      parsedJSON = JSON.parse(contentText)
    } catch (jsonErr: any) {
      console.error("[generate-scripts] JSON parse error:", contentText)
      return new Response(
        JSON.stringify({ error: `Failed to parse generated script JSON: ${jsonErr.message}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    let scriptObj: any = parsedJSON.script || (Array.isArray(parsedJSON.scripts) ? parsedJSON.scripts[0] : parsedJSON)

    const normalizedScript = {
      title: scriptObj.title || "Universal Speaking Script",
      hook: scriptObj.hook || "",
      body: scriptObj.body || "",
      callToAction: scriptObj.callToAction || scriptObj.cta || "Follow and share for more daily breakdowns!",
      cta: scriptObj.callToAction || scriptObj.cta || "Follow and share for more daily breakdowns!",
      estimatedDuration: scriptObj.estimatedDuration || "3-5 min",
      keyTakeaway: scriptObj.keyTakeaway || "Substantive 3-5 minute spoken presentation engineered for maximum retention.",
      transcript: finalTranscript,
      sourceText: finalTranscript,
      transcriptType: resolvedTranscriptType,
      platform: resolvedPlatform
    }

    // 9. Record generation audit and increment quota
    let finalQuota = quotaCheck
    if (supabase && payload.anonymousUserId) {
      try {
        const durationMs = Math.round(performance.now() - requestStartTime)
        const usage = result.usage || {}
        const { data: recordData, error: recordErr } = await supabase.rpc('record_generation', {
          p_anon_id: payload.anonymousUserId,
          p_tier: payload.clientTier || 'free',
          p_input_type: inputType || (isVideoUrl ? 'video' : 'text'),
          p_duration: durationMinutes,
          p_model: successfulModel,
          p_input_tokens: usage.input_tokens || 0,
          p_output_tokens: usage.output_tokens || 0,
          p_duration_ms: durationMs
        })
        if (recordErr) {
          console.warn(`[generate-scripts] record_generation error:`, recordErr.message)
        } else if (recordData) {
          finalQuota = recordData
          console.log(`[generate-scripts] Quota recorded:`, finalQuota)
        }
      } catch (recordErr: any) {
        console.warn(`[generate-scripts] Failed to record generation audit:`, recordErr?.message || recordErr)
      }
    }

    const responsePayload: any = { 
      script: normalizedScript,
      data: [normalizedScript],
      scripts: [normalizedScript],
      activeModel: successfulModel,
      quota: finalQuota
    }
    if (diagnostics) {
      responsePayload.diagnostics = diagnostics
    }

    return new Response(
      JSON.stringify(responsePayload),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (error: any) {
    console.error("[generate-scripts] Unhandled error:", error)
    return new Response(
      JSON.stringify({ error: `Internal Server Error: ${error.message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})