import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages"
const MAX_INPUT_CHARS = 3000

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

/**
 * Tier 1: Attempt to fetch automated or creator captions from YouTube player response.
 */
async function fetchYouTubeTranscript(videoId: string): Promise<string | null> {
  console.log(`[generate-scripts] [YouTube Tier 1] Fetching transcript for videoId: ${videoId}`)
  try {
    const watchUrl = `https://www.youtube.com/watch?v=${videoId}`
    const pageResp = await fetch(watchUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8"
      }
    })

    if (!pageResp.ok) return null
    const html = await pageResp.text()

    const playerResponseMatch = html.match(/ytInitialPlayerResponse\s*=\s*({.+?});(?:var|\n|<\/script>)/) ||
                                html.match(/var ytInitialPlayerResponse = ({.+?});/)
    
    if (!playerResponseMatch || !playerResponseMatch[1]) return null

    let playerResponse: any
    try {
      playerResponse = JSON.parse(playerResponseMatch[1])
    } catch (_) {
      return null
    }

    const captionTracks = playerResponse?.captions?.playerCaptionsTracklistRenderer?.captionTracks
    if (!captionTracks || !Array.isArray(captionTracks) || captionTracks.length === 0) return null

    const selectedTrack = captionTracks.find((t: any) => t.languageCode === 'en' || t.vssId?.includes('.en')) || captionTracks[0]
    if (!selectedTrack?.baseUrl) return null

    const transcriptResp = await fetch(selectedTrack.baseUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36"
      }
    })
    if (!transcriptResp.ok) return null

    const transcriptXml = await transcriptResp.text()
    if (!transcriptXml || transcriptXml.trim() === "") return null

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

    return cleanText.length >= 30 ? cleanText : null
  } catch (err) {
    console.warn("[generate-scripts] [YouTube Tier 1] Transcript extraction error:", err)
    return null
  }
}

/**
 * Universal video metadata resolution (YouTube, TikTok, Instagram, Facebook)
 */
async function fetchUniversalVideoMetadata(rawUrl: string, platform: string): Promise<string> {
  console.log(`[generate-scripts] Resolving video metadata for platform: ${platform} - URL: ${rawUrl}`)
  let title = ""
  let description = ""
  let creator = ""

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
    }
  } catch (e) {
    console.warn("[generate-scripts] Universal metadata scrape notice:", e)
  }

  // Build clean structured context
  const lines = [
    `Platform: ${platform}`,
    `Source URL: ${rawUrl}`,
    title ? `Video Title: ${title}` : null,
    creator ? `Creator: ${creator}` : null,
    description ? `Description / Summary:\n${description}` : null
  ].filter(Boolean)

  if (lines.length <= 2) {
    return `Video Source: ${platform} Link (${rawUrl}). Create a high-value, detailed 3-5 minute speaking reaction and breakdown for this video topic.`
  }

  return lines.join("\n\n")
}

serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const anthropicApiKey = Deno.env.get("ANTHROPIC_API_KEY")
    if (!anthropicApiKey) {
      return new Response(
        JSON.stringify({ 
          error: "Configuration Error: ANTHROPIC_API_KEY is not set in Supabase Edge Function secrets." 
        }),
        { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    let payload: { inputText?: string; scriptStyle?: string; model?: string; outputCount?: number; inputType?: string; style?: string } = {}
    try {
      const bodyText = await req.text()
      payload = JSON.parse(bodyText)
    } catch (parseError) {
      return new Response(
        JSON.stringify({ error: `Malformed JSON request body: ${parseError.message}` }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    let { inputText, scriptStyle, style, inputType } = payload
    const effectiveStyle = scriptStyle || style || 'Casual & Relatable'

    if (!inputText || inputText.trim() === "") {
      return new Response(
        JSON.stringify({ error: "Missing required field: inputText cannot be empty." }),
        { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // 3. Universal Video Link Resolution (#10: YouTube, TikTok, Instagram Reels, Facebook Reels)
    const { platform, isVideoUrl } = detectVideoPlatform(inputText.trim())
    if (inputType === 'video' || inputType === 'youtube' || inputType === 'url' || isVideoUrl) {
      const ytId = extractYouTubeVideoId(inputText)
      if (ytId) {
        const transcript = await fetchYouTubeTranscript(ytId)
        if (transcript) {
          inputText = transcript
        } else {
          inputText = await fetchUniversalVideoMetadata(inputText, "YouTube")
        }
      } else {
        inputText = await fetchUniversalVideoMetadata(inputText, platform)
      }
    }

    // 4. Streamlined Input Clamping (3000 chars limit for high-signal, cost-effective requests)
    const trimmedInput = inputText.trim()
    const sanitizedInput = trimmedInput.length > MAX_INPUT_CHARS
      ? trimmedInput.substring(0, MAX_INPUT_CHARS) + "\n[...content truncated for concise processing...]"
      : trimmedInput

    const requestHeaders = {
      "x-api-key": anthropicApiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    }

    // 5. Model Hierarchy — always prefer -latest aliases so Anthropic resolves current supported version
    const baseModelHierarchy = [
      payload.model,
      Deno.env.get("ANTHROPIC_MODEL"),
      "claude-3-5-sonnet-latest",       // Recommended: always current Sonnet
      "claude-3-5-haiku-latest",         // Fast fallback: always current Haiku
      "claude-3-5-sonnet-20241022",      // Pinned fallback
      "claude-3-5-haiku-20241022",       // Pinned fast fallback
    ].filter(Boolean) as string[]

    const modelHierarchy = Array.from(new Set(baseModelHierarchy))

    // 6. Style-Specific System Prompts for 3-5 Minute Continuous Spoken Monologue (No Clip Cues)
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
2. 3 TO 5 MINUTE SPEAKING DURATION: The body must contain 700 to 1000 words of substantive, high-retention speaking text divided into natural, readable paragraphs (representing approx. 3 to 5 minutes of speech at 140-200 words per minute). Do not cut short — fill the full word count.
3. THIRD-PERSON PERSPECTIVE: React to and explore the source material as an outside creator/expert presenting commentary to your audience. Never pretend to be the original person in the source transcript.
4. TELEPROMPTER READY: Write with natural pauses, rhetorical cadence, and smooth vocal transitions.

Output ONLY valid JSON matching this exact structure (no markdown fences, no backticks, no preamble):
{
  "script": {
    "title": "Compelling Presentation Title",
    "hook": "Strong 10-15s opening spoken hook capturing immediate attention (approx 30-40 words)",
    "body": "Detailed 3-5 minute spoken presentation text (700-1000 words) divided into clear thematic paragraphs without any camera cues or bracketed stage markers",
    "callToAction": "Natural closing takeaway and engagement call to action (approx 30 words)",
    "estimatedDuration": "3-5 min",
    "keyTakeaway": "Single-sentence core summary of the breakdown"
  }
}`

    // 7. Token Budget: 4,400 tokens allows ~1,000 words of rich JSON body output
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
          body: JSON.stringify(requestBody),
        })

        const text = await resp.text()
        if (resp.ok) {
          finalResponse = resp
          rawResponseText = text
          successfulModel = currentModel
          break
        } else {
          let errMsg = text.substring(0, 200)
          try { errMsg = JSON.parse(text)?.error?.message || errMsg } catch (_) {}
          const modelErr = `${currentModel} (HTTP ${resp.status}): ${errMsg}`
          modelErrors.push(modelErr)
          console.warn(`[generate-scripts] Model failed — ${modelErr}`)
          finalResponse = resp
          rawResponseText = text
          if (resp.status === 401 || resp.status === 403) break
        }
      } catch (fetchErr) {
        const netErr = `${currentModel}: network error — ${fetchErr}`
        modelErrors.push(netErr)
        console.error(`[generate-scripts] ${netErr}`)
      }
    }

    if (!finalResponse || !finalResponse.ok) {
      const combinedErrors = modelErrors.join(" | ")
      console.error(`[generate-scripts] All models failed: ${combinedErrors}`)
      return new Response(
        JSON.stringify({ error: `All models failed. ${combinedErrors}` }),
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
    } catch (jsonErr) {
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
      keyTakeaway: scriptObj.keyTakeaway || "Substantive 3-5 minute spoken presentation engineered for maximum retention."
    }

    return new Response(
      JSON.stringify({ 
        script: normalizedScript,
        data: [normalizedScript],
        scripts: [normalizedScript],
        activeModel: successfulModel
      }),
      { status: 200, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  } catch (error) {
    console.error("[generate-scripts] Unhandled error:", error)
    return new Response(
      JSON.stringify({ error: `Internal Server Error: ${error.message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})