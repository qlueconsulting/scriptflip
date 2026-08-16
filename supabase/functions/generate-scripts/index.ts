import { serve } from "https://deno.land/std@0.168.0/http/server.ts"

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
}

const ANTHROPIC_ENDPOINT = "https://api.anthropic.com/v1/messages"
const ANTHROPIC_MODELS_ENDPOINT = "https://api.anthropic.com/v1/models"

function extractYouTubeVideoId(input: string): string | null {
  const trimmed = input.trim()
  const patterns = [
    /(?:https?:\/\/)?(?:www\.)?youtube\.com\/watch\?(?:.*&)?v=([a-zA-Z0-9_-]{11})/,
    /(?:https?:\/\/)?(?:www\.)?youtu\.be\/([a-zA-Z0-9_-]{11})/,
    /(?:https?:\/\/)?(?:www\.)?youtube\.com\/shorts\/([a-zA-Z0-9_-]{11})/,
    /(?:https?:\/\/)?(?:www\.)?youtube\.com\/embed\/([a-zA-Z0-9_-]{11})/,
    /(?:https?:\/\/)?(?:www\.)?youtube\.com\/v\/([a-zA-Z0-9_-]{11})/,
  ]
  for (const p of patterns) {
    const m = trimmed.match(p)
    if (m && m[1]) return m[1]
  }
  return null
}

async function fetchYouTubeTranscript(videoId: string): Promise<string | null> {
  console.log(`[generate-scripts] Fetching YouTube transcript for videoId: ${videoId}`)
  try {
    const watchUrl = `https://www.youtube.com/watch?v=${videoId}`
    const pageResp = await fetch(watchUrl, {
      headers: {
        "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
        "Accept-Language": "en-US,en;q=0.9",
      }
    })

    if (!pageResp.ok) {
      console.warn(`[generate-scripts] YouTube page fetch returned status ${pageResp.status}`)
      return null
    }

    const html = await pageResp.text()

    // 1. Extract ytInitialPlayerResponse JSON
    const playerResponseMatch = html.match(/ytInitialPlayerResponse\s*=\s*({.+?});(?:var|\n|<\/script>)/) ||
                                html.match(/var ytInitialPlayerResponse = ({.+?});/)
    
    if (!playerResponseMatch || !playerResponseMatch[1]) {
      console.warn("[generate-scripts] Could not find ytInitialPlayerResponse in YouTube HTML.")
      return null
    }

    let playerResponse: any
    try {
      playerResponse = JSON.parse(playerResponseMatch[1])
    } catch (e) {
      console.warn("[generate-scripts] Error parsing ytInitialPlayerResponse:", e)
      return null
    }

    const captionTracks = playerResponse?.captions?.playerCaptionsTracklistRenderer?.captionTracks
    if (!captionTracks || !Array.isArray(captionTracks) || captionTracks.length === 0) {
      console.warn("[generate-scripts] No caption tracks available for this video.")
      return null
    }

    // 2. Select English track if available, else first track
    const selectedTrack = captionTracks.find((t: any) => t.languageCode === 'en' || t.vssId?.includes('.en')) || captionTracks[0]
    if (!selectedTrack?.baseUrl) {
      console.warn("[generate-scripts] Selected caption track lacks baseUrl.")
      return null
    }

    console.log(`[generate-scripts] Fetching caption track from: ${selectedTrack.baseUrl.substring(0, 80)}...`)
    const transcriptResp = await fetch(selectedTrack.baseUrl)
    if (!transcriptResp.ok) {
      console.warn(`[generate-scripts] Caption track fetch returned HTTP ${transcriptResp.status}`)
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

    if (cleanText.length < 20) {
      console.warn("[generate-scripts] Parsed transcript text too short.")
      return null
    }

    console.log(`[generate-scripts] Successfully extracted YouTube transcript (${cleanText.length} characters).`)
    return cleanText
  } catch (err) {
    console.error("[generate-scripts] Error extracting YouTube transcript:", err)
    return null
  }
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

    // 3. YouTube URL Resolution
    const youtubeVideoId = extractYouTubeVideoId(inputText)
    if (inputType === 'youtube' || youtubeVideoId !== null) {
      if (youtubeVideoId) {
        const transcript = await fetchYouTubeTranscript(youtubeVideoId)
        if (transcript) {
          inputText = transcript
        } else {
          return new Response(
            JSON.stringify({ 
              error: "No captions found for this YouTube video. Please paste the transcript or summary text manually." 
            }),
            { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
          )
        }
      } else {
        return new Response(
          JSON.stringify({ 
            error: "Invalid YouTube URL format. Please provide a valid YouTube video link or paste text manually." 
          }),
          { status: 400, headers: { ...corsHeaders, "Content-Type": "application/json" } }
        )
      }
    }

    const requestHeaders = {
      "x-api-key": anthropicApiKey,
      "anthropic-version": "2023-06-01",
      "content-type": "application/json",
    }

    // 4. Dynamic Model Discovery & Hierarchy
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

    const count = outputCount || 3
    const systemPrompt = `You are an expert scriptwriter. Output ONLY valid JSON containing a 'scripts' array. Do not include markdown formatting, backticks, or conversational preamble.

Generate ${count} distinct, high-retention short-form video scripts in a ${scriptStyle || 'Casual & Relatable'} tone.
Each item in the 'scripts' array MUST have:
- "hook": Compelling 0-3s opening spoken sentence with high tension or curiosity.
- "body": 15-25s core value delivery broken into fast-paced actionable points.
- "visualCue": Specific on-screen camera directions, text overlays, and framing tips.
- "cta": Engagement-driving call to action for the end of the video.`

    const maskedKey = anthropicApiKey.length > 10 
      ? `${anthropicApiKey.substring(0, 7)}...${anthropicApiKey.substring(anthropicApiKey.length - 4)}` 
      : "***"

    console.log("================ [generate-scripts] DISPATCH START ================")
    console.log(`[generate-scripts] Endpoint: ${ANTHROPIC_ENDPOINT}`)
    console.log(`[generate-scripts] Model Hierarchy: ${JSON.stringify(modelHierarchy)}`)
    console.log(`[generate-scripts] Masked API Key: ${maskedKey}`)
    console.log(`[generate-scripts] Input Text Length: ${inputText.length} chars`)
    console.log("====================================================================")

    let finalResponse: Response | null = null
    let rawResponseText = ""
    let successfulModel = ""

    // 5. Iterate through Model Hierarchy with Automatic Fallback
    for (const currentModel of modelHierarchy) {
      console.log(`[generate-scripts] Attempting dispatch with model: '${currentModel}'...`)
      
      const requestBody = {
        model: currentModel,
        max_tokens: 1500,
        temperature: 0.7,
        messages: [{ role: "user", content: `${systemPrompt}\n\nSource Content:\n${inputText}` }]
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

    // 6. Handle Non-OK Anthropic Responses Gracefully
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

    // 7. Parse Successful Response Payload
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

    // 8. Clean and Parse Script Array JSON
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

    console.log(`[generate-scripts] Successfully generated ${finalArray.length} scripts with model '${successfulModel}'.`)

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