import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages"
const ANTHROPIC_MODELS_ENDPOINT = "https://api.anthropic.com/v1/models"
const MAX_INPUT_CHARS = 4000

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

    let { inputText, scriptStyle, inputType } = payload
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

    // 6. Style-Specific "Act As" Prompts for 2-Minute Social Media Reaction Dialog (Response/Reaction Format)
    const stylePrompts: Record<string, string> = {
      'Casual & Relatable': `Act as a relatable content creator filming a casual reaction and breakdown video for social media. You are reacting to the source content from a third-person perspective (NEVER pretend to be the original person in the transcript or retell their story as your own). Talk directly to your audience like a friend sharing commentary: "Okay, you guys have to see what this creator just said...", "I was watching this video and one thing completely blew my mind..."

Create a response to the source text in the style of a casual, conversational social media reaction. Make this a robust 2-minute dialog reacting to the text specifically for social media hooks and reactions. Use rhetorical questions, relatable commentary, and genuine enthusiasm. Structure your hook as a "wait, you guys need to hear this" pattern interrupt. The body should feel like an excited friend breaking down something they just discovered. End with a natural, non-salesy CTA that feels like peer advice.`,

      'Direct Response Sales': `Act as a high-converting direct response creator filming an expert critique and reaction video for social media. You are analyzing and reacting to the source content as an external strategist (NEVER speak as the original author in the transcript). Reference the source material directly: "Everyone is talking about this claim, but here's the real reason it works...", "Look at what this case study actually proves for your business..."

Create a response to the source text in the style of a direct response reaction script optimized for maximum clicks, conversions, and engagement. Make this a robust 2-minute dialog reacting to the text specifically for social media hooks and reactions. Open with a bold claim or shocking reaction to the content that creates an open loop. Stack tangible benefits and takeaways in the body. Use power words, time-pressure language, and social proof framing. Close with a crystal-clear, urgent call to action.`,

      'Storytelling & Narrative': `Act as a master storytelling creator filming a commentary and narrative reaction video for social media. You are reacting to and exploring the story/ideas inside the source content as an observer (NEVER retell the transcript in the first person as if it happened to you). Frame it as a compelling external narrative: "This story about [topic] is one of the wildest things I've come across...", "When you hear what actually happened here, it completely changes how you look at [topic]..."

Create a response to the source text in the style of an emotionally compelling story-driven social media reaction. Make this a robust 2-minute dialog reacting to the text specifically for social media hooks and reactions. Open with a moment of tension or mystery reacting to the source material. Build the narrative with vivid observations, emotional stakes, and pacing shifts. Land on a powerful takeaway that resonates on a human level and compels sharing.`,

      'Controversial / Hot Take': `Act as a bold, opinionated content creator filming an unfiltered hot-take reaction video for social media. You are reacting to and challenging the source content from an external perspective (NEVER speak as the original author). Open with a contrarian reaction: "I just saw this take and I completely disagree...", "Everyone in the comments is praising this video, but here is the huge flaw nobody is talking about..."

Create a response to the source text in the style of a controversial hot-take reaction that challenges conventional wisdom. Make this a robust 2-minute dialog reacting to the text specifically for social media hooks and reactions. Open with your most provocative reaction statement first. Systematically dismantle the source claims with sharp logic, counter-examples, and uncomfortable truths. End with a mic-drop question that forces viewers to pick a side in the comments.`,

      'High-Value Educational': `Act as an expert educator and analyst filming a breakdown and reaction video for social media. You are analyzing the source content to extract and teach valuable lessons to your audience (NEVER pretend to be the person who created the transcript). Frame the response as an authoritative analysis: "Let's break down what this video gets 100% right and how you can apply it...", "Here are the 3 biggest lessons from this clip that you can use today..."

Create a response to the source text in the style of a high-value educational breakdown for social media. Make this a robust 2-minute dialog reacting to the text specifically for social media hooks and reactions. Open with a counterintuitive insight or "most people missed this key part" hook that establishes your authority. Deliver the value in a numbered framework or step-by-step breakdown that feels immediately actionable. Close with the single most important takeaway and a CTA to save and share.`
    }

    const selectedPrompt = stylePrompts[style] || stylePrompts['Casual & Relatable']

    const systemPrompt = `${selectedPrompt}

CRITICAL PERSPECTIVE RULES:
1. RESPONSE/REACTION FORMAT ONLY: You are a creator REACTING TO, COMMENTING ON, and BREAKING DOWN the source content for your followers.
2. NO FIRST-PERSON IMPERSONATION: NEVER write as if you are the original speaker/author in the source text (do NOT say "My podcast", "When I built my company", "I was arrested", etc.). ALWAYS speak as an outside creator reacting to what the source content shared (e.g., "This video claims...", "Look at what happened here...", "Here is my breakdown...").
3. DIRECT-TO-CAMERA: Write spoken dialogue for the creator talking directly to their audience.

Output ONLY valid JSON matching this exact structure — no markdown formatting, backticks, or preamble:
{
  "script": {
    "title": "Short punchy video title",
    "hook": "0-3s high retention reaction hook with pattern interrupt that stops the scroll",
    "body": "90-110s robust social media reaction dialog breaking down the source content with energy and personality",
    "callToAction": "Clear viral engagement call to action",
    "estimatedDuration": "~2 min",
    "visualCues": ["Opening reaction visual cue", "Mid-video camera/editing cue", "Ending banner or graphic cue"]
  }
}`

    const maxTokensBudget = 1800

    const maskedKey = anthropicApiKey.length > 10 
      ? `${anthropicApiKey.substring(0, 7)}...${anthropicApiKey.substring(anthropicApiKey.length - 4)}` 
      : "***"

    console.log("================ [generate-scripts] DISPATCH START ================")
    console.log(`[generate-scripts] Endpoint: ${ANTHROPIC_ENDPOINT}`)
    console.log(`[generate-scripts] Model Hierarchy: ${JSON.stringify(modelHierarchy)}`)
    console.log(`[generate-scripts] Masked API Key: ${maskedKey}`)
    console.log(`[generate-scripts] Input Text Length: ${sanitizedInput.length} chars (clamped)`)
    console.log(`[generate-scripts] Max Tokens: ${maxTokensBudget}`)
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
        messages: [{ role: "user", content: `${systemPrompt}\n\nSource Content:\n${sanitizedInput}` }]
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

    // 10. Clean and Parse Script Object JSON
    let contentText = result.content[0].text.trim()
    if (contentText.startsWith("```")) {
      contentText = contentText.replace(/^```(?:json)?\n?/, "").replace(/\n?```$/, "").trim()
    }

    let parsedJSON: any
    try {
      parsedJSON = JSON.parse(contentText)
    } catch (jsonErr) {
      console.error("[generate-scripts] Failed to parse script JSON:", contentText)
      return new Response(
        JSON.stringify({ 
          error: `Failed to parse generated script JSON from model: ${jsonErr.message}`,
          rawOutput: contentText.substring(0, 500)
        }),
        { status: 502, headers: { ...corsHeaders, "Content-Type": "application/json" } }
      )
    }

    // Extract standardized script object
    let scriptObj: any = null
    if (parsedJSON.script && typeof parsedJSON.script === 'object') {
      scriptObj = parsedJSON.script
    } else if (Array.isArray(parsedJSON.scripts) && parsedJSON.scripts.length > 0) {
      scriptObj = parsedJSON.scripts[0]
    } else if (Array.isArray(parsedJSON.data) && parsedJSON.data.length > 0) {
      scriptObj = parsedJSON.data[0]
    } else if (Array.isArray(parsedJSON) && parsedJSON.length > 0) {
      scriptObj = parsedJSON[0]
    } else if (parsedJSON.hook && parsedJSON.body) {
      scriptObj = parsedJSON
    }

    if (!scriptObj) {
      scriptObj = {
        title: "Universal Short-Form Script",
        hook: "Stop scrolling and check this out!",
        body: contentText.substring(0, 200),
        callToAction: "Follow for more daily tips!",
        estimatedDuration: "30-45s",
        visualCues: ["Point directly at camera", "Text overlay with key insight"]
      }
    }

    // Standardize fields for universal compatibility
    const normalizedScript = {
      title: scriptObj.title || "Universal Short-Form Script",
      hook: scriptObj.hook || "",
      body: scriptObj.body || "",
      callToAction: scriptObj.callToAction || scriptObj.cta || "",
      cta: scriptObj.callToAction || scriptObj.cta || "",
      estimatedDuration: scriptObj.estimatedDuration || "30-45s",
      visualCues: Array.isArray(scriptObj.visualCues) ? scriptObj.visualCues : (scriptObj.visualCue ? [scriptObj.visualCue] : ["Camera focus with energetic delivery"]),
      visualCue: Array.isArray(scriptObj.visualCues) ? scriptObj.visualCues.join("; ") : (scriptObj.visualCue || "Dynamic camera zoom and captions")
    }

    console.log(`[generate-scripts] Successfully generated single universal script with model '${successfulModel}'.`)

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
    console.error("[generate-scripts] Unexpected unhandled error:", error)
    return new Response(
      JSON.stringify({ error: `Internal Edge Function Error: ${error.message}` }),
      { status: 500, headers: { ...corsHeaders, "Content-Type": "application/json" } }
    )
  }
})