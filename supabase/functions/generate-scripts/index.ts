import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages"
const ANTHROPIC_MODELS_ENDPOINT = "https://api.anthropic.com/v1/models"
const MAX_INPUT_CHARS = 2800

/**
 * Robustly extract clean 11-character YouTube video IDs from any URL format,
 * automatically discarding tracking query params like ?si=, ?is=, &t=, etc.
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
  } catch (_) {
    // fallback to regex matching
  }

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
 * Tier 1: Attempt to fetch automated or creator captions from YouTube player response.
 */
async function fetchYouTubeTranscript(videoId: string): Promise<string | null> {
  console.log(`[generate-scripts] [Tier 1] Attempting YouTube transcript fetch for videoId: ${videoId}`)
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
      console.warn(`[generate-scripts] [Tier 1] YouTube page fetch returned status ${pageResp.status}`)
      return null
    }

    const html = await pageResp.text()

    // 1. Extract ytInitialPlayerResponse JSON
    const playerResponseMatch = html.match(/ytInitialPlayerResponse\s*=\s*({.+?});(?:var|\n|<\/script>)/) ||
                                html.match(/var ytInitialPlayerResponse = ({.+?});/)
    
    if (!playerResponseMatch || !playerResponseMatch[1]) {
      console.warn("[generate-scripts] [Tier 1] Could not find ytInitialPlayerResponse in YouTube HTML.")
      return null
    }

    let playerResponse: any
    try {
      playerResponse = JSON.parse(playerResponseMatch[1])
    } catch (e) {
      console.warn("[generate-scripts] [Tier 1] Error parsing ytInitialPlayerResponse:", e)
      return null
    }

    const captionTracks = playerResponse?.captions?.playerCaptionsTracklistRenderer?.captionTracks
    if (!captionTracks || !Array.isArray(captionTracks) || captionTracks.length === 0) {
      console.warn("[generate-scripts] [Tier 1] No caption tracks available for this video.")
      return null
    }

    // 2. Select English track if available, else first track
    const selectedTrack = captionTracks.find((t: any) => t.languageCode === 'en' || t.vssId?.includes('.en')) || captionTracks[0]
    if (!selectedTrack?.baseUrl) {
      console.warn("[generate-scripts] [Tier 1] Selected caption track lacks baseUrl.")
      return null
    }

    console.log(`[generate-scripts] [Tier 1] Fetching caption track from baseUrl...`)
    const transcriptResp = await fetch(selectedTrack.baseUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      }
    })
    if (!transcriptResp.ok) {
      console.warn(`[generate-scripts] [Tier 1] Caption track fetch returned HTTP ${transcriptResp.status}`)
      return null
    }

    const transcriptXml = await transcriptResp.text()
    if (!transcriptXml || transcriptXml.trim() === "") {
      return null
    }

    // 3. Parse XML / HTML caption text
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

    if (cleanText.length < 30) {
      console.warn("[generate-scripts] [Tier 1] Parsed transcript text too short.")
      return null
    }

    console.log(`[generate-scripts] [Tier 1] Successfully extracted YouTube transcript (${cleanText.length} characters).`)
    return cleanText
  } catch (err) {
    console.error("[generate-scripts] [Tier 1] Error extracting YouTube transcript:", err)
    return null
  }
}

/**
 * Tier 2: Fetch video metadata via YouTube oEmbed API and HTML OpenGraph tags as automatic fallback.
 */
async function fetchYouTubeMetadataFallback(videoId: string): Promise<string | null> {
  console.log(`[generate-scripts] [Tier 2] Fetching public metadata fallback for videoId: ${videoId}`)
  let title = ""
  let author = ""
  let description = ""

  // 1. Fetch official YouTube oEmbed JSON endpoint
  try {
    const oembedUrl = `https://www.youtube.com/oembed?url=https://www.youtube.com/watch?v=${videoId}&format=json`
    const oembedResp = await fetch(oembedUrl)
    if (oembedResp.ok) {
      const oembedData = await oembedResp.json()
      title = oembedData.title || ""
      author = oembedData.author_name || ""
      console.log(`[generate-scripts] [Tier 2] oEmbed found title: "${title}" by "${author}"`)
    }
  } catch (err) {
    console.warn("[generate-scripts] [Tier 2] oEmbed fetch warning:", err)
  }

  // 2. Fetch watch page HTML for OpenGraph description and keywords
  try {
    const watchUrl = `https://www.youtube.com/watch?v=${videoId}`
    const pageResp = await fetch(watchUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9"
      }
    })

    if (pageResp.ok) {
      const html = await pageResp.text()

      if (!title) {
        const titleMatch = html.match(/<title>(.+?)<\/title>/) || html.match(/<meta property="og:title" content="(.+?)"/)
        if (titleMatch && titleMatch[1]) {
          title = titleMatch[1].replace(" - YouTube", "").trim()
        }
      }

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
  } catch (err) {
    console.warn("[generate-scripts] [Tier 2] HTML metadata scrape warning:", err)
  }

  if (!title && !description) {
    console.warn(`[generate-scripts] [Tier 2] Failed to resolve any metadata for videoId: ${videoId}`)
    return null
  }

  const structuredContent = [
    `Video Title: ${title || "Short-Form Video"}`,
    author ? `Channel / Creator: ${author}` : null,
    description ? `Description & Overview:\n${description}` : null
  ].filter(Boolean).join("\n\n")

  console.log(`[generate-scripts] [Tier 2] Successfully compiled metadata context (${structuredContent.length} characters).`)
  return structuredContent
}

serve(async (req) => {
  // 1. Handle CORS Pre-Flight OPTIONS Request
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const anthropicApiKey = Deno.env.get("ANTHROPIC_API_KEY")
    if (!anthropicApiKey) {
      console.error("[generate-scripts] Missing ANTHROPIC_API_KEY secret in environment.")
      return new Response(
        JSON.stringify({ 
          error: "Configuration Error: ANTHROPIC_API_KEY is not set in Supabase Edge Function secrets. Please add it via `supabase secrets set ANTHROPIC_API_KEY=...`." 
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 2. Parse and Validate Client Request Payload
    let bodyText = ""
    let payload: { inputText?: string; scriptStyle?: string; model?: string; outputCount?: number; inputType?: string } = {}
    try {
      bodyText = await req.text()
      payload = JSON.parse(bodyText)
    } catch (parseError) {
      return new Response(
        JSON.stringify({ error: `Malformed JSON request body: ${parseError.message}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    let { inputText, scriptStyle, outputCount, inputType } = payload
    if (!inputText || inputText.trim() === "") {
      return new Response(
        JSON.stringify({ error: "Missing required field: inputText cannot be empty." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 3. Multi-Tier YouTube URL & Content Resolution
    const youtubeVideoId = extractYouTubeVideoId(inputText)
    if (inputType === 'youtube' || youtubeVideoId !== null) {
      if (youtubeVideoId) {
        console.log(`[generate-scripts] Processing YouTube videoId: ${youtubeVideoId}`)
        // Tier 1: Transcript / Captions
        const transcript = await fetchYouTubeTranscript(youtubeVideoId)
        if (transcript) {
          inputText = transcript
        } else {
          // Tier 2: Automatic Metadata Fallback (oEmbed + HTML meta description)
          console.log(`[generate-scripts] Captions unavailable. Engaging Tier 2 metadata fallback for videoId: ${youtubeVideoId}`)
          const metadataFallback = await fetchYouTubeMetadataFallback(youtubeVideoId)
          if (metadataFallback) {
            inputText = metadataFallback
          } else {
            return new Response(
              JSON.stringify({ 
                error: "Unable to retrieve content or captions for this YouTube video. Please paste the transcript or summary text manually." 
              }),
              { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
            )
          }
        }
      } else {
        return new Response(
          JSON.stringify({ 
            error: "Invalid YouTube URL format. Please provide a valid YouTube link or paste text manually." 
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        )
      }
    }

    // 4. Token Reduction: Input Clamping & Sanitization
    const trimmedInput = inputText.trim()
    const sanitizedInput = trimmedInput.length > MAX_INPUT_CHARS
      ? trimmedInput.substring(0, MAX_INPUT_CHARS) + "\n[...content truncated for maximum brevity...]"
      : trimmedInput

    const requestHeaders = {
      "x-api-key": anthropicApiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    }

    // 5. Dynamic Model Discovery & Hierarchy
    let dynamicModels: string[] = []
    try {
      const modelsResp = await fetch(ANTHROPIC_MODELS_ENDPOINT, {
        headers: requestHeaders
      })
      if (modelsResp.ok) {
        const modelsJson = await modelsResp.json()
        if (modelsJson.data && Array.isArray(modelsJson.data)) {
          dynamicModels = modelsJson.data.map((m: any) => m.id)
          console.log("[generate-scripts] Discovered active models via /v1/models:", dynamicModels)
        }
      } else {
        console.warn(`[generate-scripts] /v1/models returned HTTP ${modelsResp.status}`)
      }
    } catch (e) {
      console.warn("[generate-scripts] Error querying /v1/models:", e)
    }

    const baseModelHierarchy = [
      payload.model,
      Deno.env.get("ANTHROPIC_MODEL"),
      ...dynamicModels,
      "claude-3-5-sonnet-20241022",
      "claude-3-5-sonnet-latest",
      "claude-3-5-haiku-20241022",
      "claude-3-5-haiku-latest",
      "claude-3-5-sonnet-20240620",
      "claude-3-haiku-20240307",
      "claude-3-sonnet-20240229",
      "claude-3-opus-20240229"
    ].filter(Boolean) as string[]

    const modelHierarchy = Array.from(new Set(baseModelHierarchy))

    const count = outputCount || 1
    const style = scriptStyle || 'Casual & Relatable'

    // 6. Token-Minimized Ultra-Dense System Prompt for Universal Short-Form Script
    const systemPrompt = `Expert viral scriptwriter. Output ONLY valid JSON: {"scripts":[{"hook":"...","body":"...","visualCue":"...","cta":"..."}]}. Write ${count} Universal Short-Form Script (optimized for TikTok, Instagram Reels, and YouTube Shorts) in ${style} tone: 0-3s high-tension hook, 15-25s fast value body, specific visual/framing cues, and high-converting CTA. No markdown, no pre/post-amble.`

    // Calculate strict minimal token budget: 500 tokens for 1 script, or count * 450 tokens
    const maxTokensBudget = count === 1 ? 500 : count * 450

    const maskedKey = anthropicApiKey.length > 10 
      ? `${anthropicApiKey.substring(0, 7)}...${anthropicApiKey.substring(anthropicApiKey.length - 4)}` 
      : "***"

    console.log("================ [generate-scripts] DISPATCH START ================")
    console.log(`[generate-scripts] Endpoint: ${ANTHROPIC_ENDPOINT}`)
    console.log(`[generate-scripts] Model Hierarchy: ${JSON.stringify(modelHierarchy)}`)
    console.log(`[generate-scripts] Masked API Key: ${maskedKey}`)
    console.log(`[generate-scripts] Input Text Length: ${sanitizedInput.length} chars (clamped)`)
    console.log(`[generate-scripts] Output Script Count: ${count}, Max Tokens: ${maxTokensBudget}`)
    console.log("====================================================================")

    let finalResponse: Response | null = null
    let rawResponseText = ""
    let successfulModel = ""

    // 7. Iterate through Model Hierarchy with Automatic Fallback
    for (const currentModel of modelHierarchy) {
      console.log(`[generate-scripts] Attempting dispatch with model: '${currentModel}'...`)
      
      const requestBody = {
        model: currentModel,
        max_tokens: maxTokensBudget,
        temperature: 0.7,
        messages: [{ role: "user", content: `${systemPrompt}\n\nSource:\n${sanitizedInput}` }]
      }

      try {
        const resp = await fetch(ANTHROPIC_ENDPOINT, {
          method: "POST",
          headers: requestHeaders,
          body: JSON.stringify(requestBody),
        })

        const text = await resp.text()
        console.log(`[generate-scripts] Model '${currentModel}' returned HTTP ${resp.status}`)

        if (resp.ok) {
          finalResponse = resp
          rawResponseText = text
          successfulModel = currentModel
          console.log(`[generate-scripts] Model '${currentModel}' succeeded!`)
          break
        } else {
          console.warn(`[generate-scripts] Model '${currentModel}' failed with HTTP ${resp.status}: ${text.substring(0, 200)}`)
          finalResponse = resp
          rawResponseText = text
          if (resp.status === 401 || resp.status === 403) {
            break
          }
        }
      } catch (fetchErr) {
        console.error(`[generate-scripts] Network error connecting to Anthropic with model '${currentModel}':`, fetchErr)
      }
    }

    // 8. Handle Non-OK Anthropic Responses Gracefully
    if (!finalResponse || !finalResponse.ok) {
      console.error(`[generate-scripts] All models in hierarchy failed. Last response:`, rawResponseText)
      let parsedError = rawResponseText
      try {
        const errorJson = JSON.parse(rawResponseText)
        parsedError = errorJson.error?.message || errorJson.message || rawResponseText
      } catch (_) {
        // use raw text
      }
      return new Response(
        JSON.stringify({ 
          error: `Anthropic API Error (${finalResponse?.status || 502}): ${parsedError}`,
          modelsAttempted: modelHierarchy
        }),
        { status: finalResponse?.status && finalResponse.status >= 400 && finalResponse.status < 600 ? finalResponse.status : 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 9. Parse Successful Response Payload
    let result: any
    try {
      result = JSON.parse(rawResponseText)
    } catch (e) {
      console.error("[generate-scripts] Failed to parse Anthropic JSON response:", rawResponseText)
      return new Response(
        JSON.stringify({ error: `Invalid JSON received from Anthropic: ${rawResponseText.substring(0, 300)}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    if (!result.content || !Array.isArray(result.content) || result.content.length === 0 || !result.content[0].text) {
      console.error("[generate-scripts] Anthropic response missing content text:", result)
      return new Response(
        JSON.stringify({ error: `Unexpected Anthropic response structure: ${JSON.stringify(result).substring(0, 300)}` }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 10. Clean and Parse Script Array JSON
    let contentText = result.content[0].text.trim()
    if (contentText.startsWith("```")) {
      contentText = contentText.replace(/^```(?:json)?\n?/, "").replace(/\n?```$/, "").trim()
    }

    let parsedScripts: any
    try {
      parsedScripts = JSON.parse(contentText)
    } catch (jsonErr) {
      console.error("[generate-scripts] Failed to parse script array JSON:", contentText)
      return new Response(
        JSON.stringify({ 
          error: `Failed to parse generated scripts JSON from model: ${jsonErr.message}`,
          rawOutput: contentText.substring(0, 500)
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // Support both { scripts: [...] }, { data: [...] }, and [...] root array
    let finalArray: any[] = []
    if (Array.isArray(parsedScripts)) {
      finalArray = parsedScripts
    } else if (parsedScripts.scripts && Array.isArray(parsedScripts.scripts)) {
      finalArray = parsedScripts.scripts
    } else if (parsedScripts.data && Array.isArray(parsedScripts.data)) {
      finalArray = parsedScripts.data
    } else if (parsedScripts.hook && parsedScripts.body) {
      finalArray = [parsedScripts]
    }

    console.log(`[generate-scripts] Successfully generated ${finalArray.length} universal scripts with model '${successfulModel}'.`)

    return new Response(
      JSON.stringify({ 
        data: finalArray,
        scripts: finalArray,
        activeModel: successfulModel
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (error) {
    console.error("[generate-scripts] Unexpected unhandled error:", error)
    return new Response(
      JSON.stringify({ error: `Internal Edge Function Error: ${error.message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})